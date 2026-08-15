class_name PressurePuzzleManager
extends Node3D

## The hydraulic press: a three-phase machine guarding the Heavy
## Battery's vault (which in turn powers the laser emitter).
##   Phase 1  SMALL_FITTINGS  — tighten 1-3 small fittings (Small Wrench).
##   Phase 2  BIG_FITTINGS    — torque 1-2 big fittings (Brass Wrench).
##   Phase 3  VALVES          — five ON/OFF valves, each adding its signed
##                              PSI while open; match the gauge's target
##                              exactly. Pure logic, no timers, no fail
##                              state — toggle freely until it balances.
## On balance the valves lock, both wrenches are marked spent, and
## `puzzle_solved` fires (the mansion wires it to the hydraulic gate and
## the vault door's hydraulics lamp).
##
## The generator seeds counts/PSI values/target and sets them BEFORE
## add_child, so every co-op peer builds an identical machine with
## deterministic child names — interactions replicate through the
## player's interact RPC with no extra netcode (state changes are pure
## functions of the interact sequence).

signal point_tightened(point: TighteningPoint)
signal phase_changed(phase: Phase)
signal valve_toggled(valve: PressureValve, psi: int)
signal wrong_item_used(point: TighteningPoint, by: Node3D)
signal puzzle_solved

enum Phase { SMALL_FITTINGS, BIG_FITTINGS, VALVES, SOLVED }

const TIGHTENING_POINT_SCENE := preload("res://scenes/Puzzles/TighteningPoint.tscn")
const PRESSURE_VALVE_SCENE := preload("res://scenes/Puzzles/PressureValve.tscn")
const VALVE_COUNT := 5

## X slots for 1..3 small fittings along the front feed pipe.
const SMALL_POINT_SLOTS := [[0.0], [-0.7, 0.7], [-0.9, 0.0, 0.9]]
## X slots for 1..2 big fittings on the low junction bosses.
const BIG_POINT_SLOTS := [[1.5], [-1.5, 1.5]]

@export_range(1, 3) var small_point_count := 2
@export_range(1, 2) var big_point_count := 1
## Signed PSI contribution of each of the five valves, left to right.
@export var valve_pressures: Array[int] = [15, -10, 25, 40, -5]
@export var base_psi := 0
@export var target_psi := 45

var phase := Phase.SMALL_FITTINGS
var current_psi := 0
var solved := false
var small_points: Array[TighteningPoint] = []
var big_points: Array[TighteningPoint] = []
var valves: Array[PressureValve] = []

var _body: StaticBody3D
var _needle: Node3D
var _psi_label: Label3D
var _gauge_mat := StandardMaterial3D.new()
var _needle_tween: Tween

var _iron_mat := _make_mat(Color(0.28, 0.29, 0.32), 0.6, 0.5)
var _brass_mat := _make_mat(Color(0.72, 0.55, 0.25), 0.7, 0.4)
var _steel_mat := _make_mat(Color(0.5, 0.52, 0.56), 0.75, 0.35)


func _ready() -> void:
	add_to_group("pressure_puzzles")
	current_psi = base_psi
	_build_machine()
	_spawn_fittings()
	_spawn_valves()
	_build_gauge()
	# Phase 1 opens immediately; later tiers wait their turn.
	for point in small_points:
		point.enabled = true
	_update_gauge()


# --- Game loop -----------------------------------------------------------


func _on_fitting_tightened(point: TighteningPoint) -> void:
	point_tightened.emit(point)
	match phase:
		Phase.SMALL_FITTINGS:
			if small_points.all(func(p: TighteningPoint) -> bool: return p.is_tight):
				_advance_to(Phase.BIG_FITTINGS)
		Phase.BIG_FITTINGS:
			if big_points.all(func(p: TighteningPoint) -> bool: return p.is_tight):
				_advance_to(Phase.VALVES)


func _advance_to(next: Phase) -> void:
	phase = next
	match next:
		Phase.BIG_FITTINGS:
			for point in big_points:
				point.enabled = true
		Phase.VALVES:
			for valve in valves:
				valve.enabled = true
	AudioSynthesizer.play_at("power_up", global_position, -14.0, 1.3)
	phase_changed.emit(phase)


func _on_valve_toggled(valve: PressureValve) -> void:
	# Recompute from scratch every toggle — no incremental drift, ever.
	current_psi = base_psi
	for v in valves:
		if v.is_on:
			current_psi += v.pressure_value
	_update_gauge()
	valve_toggled.emit(valve, current_psi)
	if phase == Phase.VALVES and current_psi == target_psi:
		_solve()


func _on_wrong_item(point: TighteningPoint, by: Node3D) -> void:
	wrong_item_used.emit(point, by)


## Target hit: freeze the combination, retire the wrenches, celebrate,
## and let the wiring (hydraulic gate, vault lamp) know.
func _solve() -> void:
	if solved:
		return
	solved = true
	phase = Phase.SOLVED
	for valve in valves:
		valve.lock()
	_gauge_mat.albedo_color = Color(0.3, 1.0, 0.5)
	_gauge_mat.emission = Color(0.2, 1.0, 0.45)
	_gauge_mat.emission_energy_multiplier = 1.6
	_psi_label.modulate = Color(0.55, 1.0, 0.65)
	_psi_label.text = "PRESSURE %+d PSI\nLOCKED" % current_psi
	# Both wrenches have done their last job; the HUD crosses them out.
	for wrench in get_tree().get_nodes_in_group("wrenches"):
		wrench.set("spent", true)
	Player.shake(0.45, global_position)
	AudioSynthesizer.play_at("chime", global_position, -6.0, 0.8)
	AudioSynthesizer.play_ui("power_up", -10.0)
	puzzle_solved.emit()


# --- Construction --------------------------------------------------------
# Local frame: +Z is the machine's front (the side the player works from).


func _build_machine() -> void:
	_body = StaticBody3D.new()
	_body.name = "Body"
	add_child(_body)
	# Manifold tank lying along X, on a skid with support legs.
	_add_cylinder(Vector3(0, 1.0, -0.15), 0.34, 3.0, _iron_mat, true)
	_add_box(Vector3(0, 0.06, -0.1), Vector3(3.3, 0.12, 0.9), _steel_mat)
	for leg_x in [-1.45, 1.45]:
		_add_box(Vector3(leg_x, 0.5, -0.15), Vector3(0.16, 0.9, 0.5), _iron_mat)
	# Front feed pipe carrying the small fittings.
	_add_cylinder(Vector3(0, 0.42, 0.42), 0.09, 2.6, _iron_mat, true)
	# One collision box for the whole chassis. Interactables live UNDER
	# this body so the player's line-of-sight check treats the machine as
	# part of its own targets rather than an occluder.
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.3, 1.1, 0.75)
	col.shape = shape
	col.position = Vector3(0, 0.75, -0.15)
	_body.add_child(col)


func _spawn_fittings() -> void:
	var small_slots: Array = SMALL_POINT_SLOTS[small_point_count - 1]
	for i in small_slots.size():
		var point := TIGHTENING_POINT_SCENE.instantiate() as TighteningPoint
		point.name = "SmallPoint_%d" % i
		point.wrench_size = TighteningPoint.WrenchSize.SMALL
		point.display_name = "Small Fitting"
		point.position = Vector3(small_slots[i], 0.51, 0.42)
		_body.add_child(point)
		point.fitting_tightened.connect(_on_fitting_tightened)
		point.wrong_item.connect(_on_wrong_item)
		small_points.append(point)

	var big_slots: Array = BIG_POINT_SLOTS[big_point_count - 1]
	for i in big_slots.size():
		var point := TIGHTENING_POINT_SCENE.instantiate() as TighteningPoint
		point.name = "BigPoint_%d" % i
		point.wrench_size = TighteningPoint.WrenchSize.BIG
		point.display_name = "Heavy Fitting"
		point.scale = Vector3.ONE * 1.45
		point.position = Vector3(big_slots[i], 0.3, 0.35)
		_body.add_child(point)
		point.fitting_tightened.connect(_on_fitting_tightened)
		point.wrong_item.connect(_on_wrong_item)
		big_points.append(point)


func _spawn_valves() -> void:
	assert(valve_pressures.size() == VALVE_COUNT,
		"the press wants exactly %d valve pressures" % VALVE_COUNT)
	for i in VALVE_COUNT:
		var valve := PRESSURE_VALVE_SCENE.instantiate() as PressureValve
		valve.name = "Valve_%d" % i
		valve.pressure_value = valve_pressures[i]
		valve.position = Vector3(-1.2 + 0.6 * i, 1.36, -0.15)
		_body.add_child(valve)
		valve.valve_toggled.connect(_on_valve_toggled)
		valves.append(valve)


## Round gauge on a back riser: needle sweeps min..max PSI, a fixed red
## tick marks the target, and the label spells both numbers out.
func _build_gauge() -> void:
	_add_cylinder(Vector3(0, 1.55, -0.6), 0.05, 0.7, _iron_mat, false)
	_gauge_mat.albedo_color = Color(0.9, 0.86, 0.7)
	var face := MeshInstance3D.new()
	var face_mesh := CylinderMesh.new()
	face_mesh.top_radius = 0.32
	face_mesh.bottom_radius = 0.32
	face_mesh.height = 0.06
	face_mesh.material = _gauge_mat
	face.mesh = face_mesh
	face.rotation.x = PI / 2.0
	face.position = Vector3(0, 1.95, -0.6)
	_body.add_child(face)

	_needle = Node3D.new()
	_needle.position = Vector3(0, 1.95, -0.555)
	_body.add_child(_needle)
	var needle_mesh := MeshInstance3D.new()
	needle_mesh.mesh = _box_mesh(Vector3(0.035, 0.24, 0.02), _make_mat(Color(0.1, 0.1, 0.12)))
	needle_mesh.position = Vector3(0, 0.1, 0)
	_needle.add_child(needle_mesh)

	var target_pivot := Node3D.new()
	target_pivot.position = Vector3(0, 1.95, -0.56)
	target_pivot.rotation.z = _psi_to_angle(target_psi)
	_body.add_child(target_pivot)
	var tick := MeshInstance3D.new()
	tick.mesh = _box_mesh(Vector3(0.03, 0.09, 0.015), _make_mat(Color(0.85, 0.1, 0.1)))
	tick.position = Vector3(0, 0.26, 0)
	target_pivot.add_child(tick)

	_psi_label = Label3D.new()
	_psi_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_psi_label.font_size = 40
	_psi_label.pixel_size = 0.005
	_psi_label.modulate = Color(1.0, 0.72, 0.25)
	_psi_label.position = Vector3(0, 2.5, -0.55)
	_body.add_child(_psi_label)


func _update_gauge() -> void:
	if not solved:
		_psi_label.text = "PRESSURE %+d PSI\nTARGET %+d PSI" % [current_psi, target_psi]
	if _needle_tween:
		_needle_tween.kill()
	_needle_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_needle_tween.tween_property(_needle, "rotation:z", _psi_to_angle(current_psi), 0.4)


## Map a PSI value onto the dial: the machine's reachable extremes (all
## negative valves open .. all positive valves open) span -125°..+125°.
func _psi_to_angle(psi: int) -> float:
	var lo := base_psi
	var hi := base_psi
	for value in valve_pressures:
		if value < 0:
			lo += value
		else:
			hi += value
	var t := inverse_lerp(float(lo), float(hi), float(psi)) if hi > lo else 0.5
	return deg_to_rad(lerpf(125.0, -125.0, clampf(t, 0.0, 1.0)))


# --- Small mesh helpers (self-contained; the machine is code-built) ------


func _add_box(at: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _box_mesh(size, mat)
	mesh.position = at
	_body.add_child(mesh)


## `lying` lays the cylinder along X (pipes); upright otherwise.
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
	_body.add_child(mesh)


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
