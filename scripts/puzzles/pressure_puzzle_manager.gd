class_name PressurePuzzleManager
extends Interactable

## The hydraulic press console: one compact machine in its own room,
## guarding the Heavy Battery's caged vault next to it. [E] opens the
## fullscreen PressurePanel overlay (FusePanel-style first-person view)
## where the whole three-phase puzzle is played by clicking:
##   Phase 1  SMALL_FITTINGS  — tighten 1-3 small fittings (Small Wrench).
##   Phase 2  BIG_FITTINGS    — torque 1-2 main fittings (Brass Wrench).
##   Phase 3  VALVES          — five ON/OFF valves, each adding its signed
##                              PSI while open; hit the target exactly.
## No timers, no fail state. On balance everything locks, both wrenches
## go spent, and `puzzle_solved` fires (wired to the hydraulic gate and
## the vault door's hydraulics lamp).
##
## Attach with set_script to a StaticBody3D (garage-button pattern) and
## seed counts/pressures/target BEFORE add_child. Panel clicks route
## through request_* which replicate via any_peer RPCs (breaker-box
## pattern), so every co-op peer holds identical state under identical
## node paths.

signal phase_changed(phase: Phase)
signal state_changed
signal wrong_item_used(by: Node3D)
signal puzzle_solved

enum Phase { SMALL_FITTINGS, BIG_FITTINGS, VALVES, SOLVED }

const PANEL_SCENE := preload("res://scenes/Puzzles/PressurePanel.tscn")
const VALVE_COUNT := 5

## Seeded by the generator before add_child.
@export_range(1, 3) var small_point_count := 2
@export_range(1, 2) var big_point_count := 1
@export var valve_pressures: Array[int] = [15, -10, 25, 40, -5]
@export var base_psi := 0
@export var target_psi := 45

var phase := Phase.SMALL_FITTINGS
var current_psi := 0
var solved := false
var small_tight: Array[bool] = []
var big_tight: Array[bool] = []
var valve_on: Array[bool] = []
var minigame: PressurePanel

var _needle: Node3D
var _lamp_mat := StandardMaterial3D.new()
var _needle_tween: Tween

var _iron_mat := _make_mat(Color(0.28, 0.29, 0.32), 0.6, 0.5)
var _brass_mat := _make_mat(Color(0.72, 0.55, 0.25), 0.7, 0.4)
var _steel_mat := _make_mat(Color(0.5, 0.52, 0.56), 0.75, 0.35)


func _ready() -> void:
	add_to_group("pressure_puzzles")
	display_name = "Hydraulic Press"
	prompt_action = "Inspect Hydraulic Press"
	prompt_height = 2.3
	small_tight.resize(small_point_count)
	small_tight.fill(false)
	big_tight.resize(big_point_count)
	big_tight.fill(false)
	valve_on.resize(VALVE_COUNT)
	valve_on.fill(false)
	current_psi = base_psi
	_build_console()
	minigame = PANEL_SCENE.instantiate()
	add_child(minigame)
	minigame.setup(self)


func get_prompt(_by: Node3D = null) -> String:
	if solved:
		return "[E] Inspect Hydraulic Press (balanced)"
	return "[E] Inspect Hydraulic Press"


## RE-style: [E] always inspects; fittings and valves are worked from
## inside the overlay. The overlay only opens on the interacting machine.
func interact(by: Node3D) -> void:
	if by == null or not by.has_method("is_local_player") or by.is_local_player():
		minigame.open()
	super.interact(by)


# --- Replicated puzzle actions (called by the panel overlay) -------------


func request_tighten(by: Node3D, big: bool, index: int) -> void:
	if NetworkSession.multiplayer_active:
		_net_tighten.rpc(by.get_path(), big, index)
	else:
		_apply_tighten(by, big, index)


@rpc("any_peer", "call_local", "reliable")
func _net_tighten(by_path: NodePath, big: bool, index: int) -> void:
	_apply_tighten(get_node_or_null(by_path), big, index)


func _apply_tighten(by: Node3D, big: bool, index: int) -> void:
	if solved or by == null:
		return
	var arr := big_tight if big else small_tight
	if index < 0 or index >= arr.size() or arr[index]:
		return
	# Sequence gate: each tier only turns during its own phase.
	var phase_ok := phase == (Phase.BIG_FITTINGS if big else Phase.SMALL_FITTINGS)
	if not phase_ok:
		AudioSynthesizer.play_at("tick", global_position, -8.0, 0.55)
		return
	# Wrench gate: the right size or nothing. A wrong wrench in the pack
	# raises the explicit wrong-item event.
	if not _holds_wrench(by, big):
		if by.has_method("inventory_find") and by.inventory_find("wrenches") != null:
			AudioSynthesizer.play_at("zap", global_position, -16.0, 0.8)
			wrong_item_used.emit(by)
		return
	arr[index] = true
	AudioSynthesizer.play_at("ratchet", global_position, -4.0)
	state_changed.emit()
	if not big and small_tight.all(func(t: bool) -> bool: return t):
		_advance_to(Phase.BIG_FITTINGS)
	elif big and big_tight.all(func(t: bool) -> bool: return t):
		_advance_to(Phase.VALVES)


func request_toggle_valve(by: Node3D, index: int) -> void:
	if NetworkSession.multiplayer_active:
		_net_toggle_valve.rpc(by.get_path(), index)
	else:
		_apply_toggle_valve(by, index)


@rpc("any_peer", "call_local", "reliable")
func _net_toggle_valve(by_path: NodePath, index: int) -> void:
	_apply_toggle_valve(get_node_or_null(by_path), index)


func _apply_toggle_valve(by: Node3D, index: int) -> void:
	if solved or by == null or index < 0 or index >= VALVE_COUNT:
		return
	if phase != Phase.VALVES:
		AudioSynthesizer.play_at("tick", global_position, -8.0, 0.55)
		return
	valve_on[index] = not valve_on[index]
	# Recompute from scratch every toggle — no incremental drift, ever.
	current_psi = base_psi
	for i in VALVE_COUNT:
		if valve_on[i]:
			current_psi += valve_pressures[i]
	AudioSynthesizer.play_at("ratchet", global_position, -6.0)
	if valve_on[index]:
		AudioSynthesizer.play_at("steam", global_position, -18.0, 1.7)
	_update_world_gauge()
	state_changed.emit()
	if current_psi == target_psi:
		_solve()


func _advance_to(next: Phase) -> void:
	phase = next
	AudioSynthesizer.play_at("power_up", global_position, -14.0, 1.3)
	phase_changed.emit(phase)


## Target hit: freeze the combination, retire the wrenches, celebrate.
func _solve() -> void:
	if solved:
		return
	solved = true
	phase = Phase.SOLVED
	_apply_lamp(Color(0.3, 1.0, 0.5), 2.2)
	# Both wrenches have done their last job; the HUD crosses them out.
	for wrench in get_tree().get_nodes_in_group("wrenches"):
		wrench.set("spent", true)
	Player.shake(0.45, global_position)
	AudioSynthesizer.play_at("chime", global_position, -6.0, 0.8)
	puzzle_solved.emit()


func _holds_wrench(by: Node3D, big: bool) -> bool:
	return by.has_method("inventory_find") \
		and by.inventory_find("big_wrenches" if big else "small_wrenches") != null


## Dial extremes: all negative valves open .. all positive valves open.
## The panel's gauge and the console needle share this scale.
func gauge_min() -> int:
	var lo := base_psi
	for value in valve_pressures:
		if value < 0:
			lo += value
	return lo


func gauge_max() -> int:
	var hi := base_psi
	for value in valve_pressures:
		if value > 0:
			hi += value
	return hi


# --- World console (compact; the real puzzle face is the overlay) --------
# Local frame: +Z is the console front.


func _build_console() -> void:
	# Cabinet with a manifold tank on top and feed pipes down the sides.
	_add_box(Vector3(0, 0.75, 0), Vector3(1.7, 1.5, 0.55), _steel_mat)
	_add_box(Vector3(0, 0.06, 0.05), Vector3(1.9, 0.12, 0.75), _iron_mat)
	_add_cylinder(Vector3(0, 1.72, -0.05), 0.28, 1.6, _iron_mat, true)
	for pipe_x in [-0.72, 0.72]:
		_add_cylinder(Vector3(pipe_x, 0.85, 0.0), 0.07, 1.7, _brass_mat, false)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.9, 2.0, 0.7)
	col.shape = shape
	col.position = Vector3(0, 1.0, 0)
	add_child(col)

	# Front dial: face, needle, red target tick.
	var face_mat := _make_mat(Color(0.9, 0.86, 0.7))
	var face := MeshInstance3D.new()
	var face_mesh := CylinderMesh.new()
	face_mesh.top_radius = 0.3
	face_mesh.bottom_radius = 0.3
	face_mesh.height = 0.05
	face_mesh.material = face_mat
	face.mesh = face_mesh
	face.rotation.x = PI / 2.0
	face.position = Vector3(0, 1.05, 0.29)
	add_child(face)
	_needle = Node3D.new()
	_needle.position = Vector3(0, 1.05, 0.33)
	add_child(_needle)
	var needle_mesh := MeshInstance3D.new()
	needle_mesh.mesh = _box_mesh(Vector3(0.03, 0.22, 0.015), _make_mat(Color(0.1, 0.1, 0.12)))
	needle_mesh.position = Vector3(0, 0.09, 0)
	_needle.add_child(needle_mesh)
	_needle.rotation.z = _psi_to_angle(current_psi)
	var target_pivot := Node3D.new()
	target_pivot.position = Vector3(0, 1.05, 0.32)
	target_pivot.rotation.z = _psi_to_angle(target_psi)
	add_child(target_pivot)
	var tick := MeshInstance3D.new()
	tick.mesh = _box_mesh(Vector3(0.025, 0.08, 0.012), _make_mat(Color(0.85, 0.1, 0.1)))
	tick.position = Vector3(0, 0.24, 0)
	target_pivot.add_child(tick)

	# Status lamp on the tank: amber while working, green once balanced.
	_lamp_mat.emission_enabled = true
	_apply_lamp(Color(1.0, 0.55, 0.1), 1.6)
	var lamp := MeshInstance3D.new()
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.06
	lamp_mesh.height = 0.12
	lamp.mesh = lamp_mesh
	lamp.material_override = _lamp_mat
	lamp.position = Vector3(0, 2.06, 0)
	add_child(lamp)

	var label := Label3D.new()
	label.text = "HYDRAULIC PRESS"
	label.font_size = 44
	label.pixel_size = 0.004
	label.modulate = Color(0.85, 0.68, 0.3)
	label.position = Vector3(0, 1.62, 0.31)
	add_child(label)


func _update_world_gauge() -> void:
	if _needle_tween:
		_needle_tween.kill()
	_needle_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_needle_tween.tween_property(_needle, "rotation:z", _psi_to_angle(current_psi), 0.4)


func _psi_to_angle(psi: int) -> float:
	var lo := gauge_min()
	var hi := gauge_max()
	var t := inverse_lerp(float(lo), float(hi), float(psi)) if hi > lo else 0.5
	return deg_to_rad(lerpf(125.0, -125.0, clampf(t, 0.0, 1.0)))


func _apply_lamp(color: Color, energy: float) -> void:
	_lamp_mat.albedo_color = color
	_lamp_mat.emission = color
	_lamp_mat.emission_energy_multiplier = energy


# --- Small mesh helpers (the console is code-built) ----------------------


func _add_box(at: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _box_mesh(size, mat)
	mesh.position = at
	add_child(mesh)


## `lying` lays the cylinder along X (the tank); upright otherwise.
func _add_cylinder(at: Vector3, radius: float, length: float, mat: StandardMaterial3D, lying: bool) -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = length
	cyl.material = mat
	mesh.mesh = cyl
	mesh.position = at
	if lying:
		mesh.rotation.z = PI / 2.0
	add_child(mesh)


func _box_mesh(size: Vector3, mat: StandardMaterial3D) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	return box


static func _make_mat(color: Color, metallic := 0.0, roughness := 0.7) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat
