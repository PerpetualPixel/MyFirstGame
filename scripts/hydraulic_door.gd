class_name HydraulicDoor
extends Node3D

## Pressure-locked gate sealing the Heavy Battery's cage. Sits shut with
## an amber lamp until the hydraulic press balances (`activate()`), then
## vents and sinks into the floor for good — there is no way to close it
## again, so the reward can never be re-sealed. The slab is a CSG panel
## in "fade_walls" (same contract as the garage roll door), so the
## camera see-through fade keeps the caged battery readable.

signal opened

@export var open_duration: float = 1.4

const COLOR_WAIT := Color(1.0, 0.55, 0.1)
const COLOR_DONE := Color(0.35, 1.0, 1.0)

var is_open := false

var _slab: CSGBox3D
var _lamp_mat := StandardMaterial3D.new()
var _lamp_light: OmniLight3D


func _ready() -> void:
	add_to_group("hydraulic_doors")
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.35, 0.38, 0.42)
	steel.metallic = 0.6
	steel.roughness = 0.45

	# Sliding slab: CSG so it carries its own collision AND exposes
	# `.material` for the player's wall-fade pass.
	_slab = CSGBox3D.new()
	_slab.size = Vector3(2.36, 2.3, 0.14)
	_slab.position = Vector3(0, 1.15, 0)
	_slab.use_collision = true
	_slab.material = steel
	_slab.add_to_group("fade_walls")
	add_child(_slab)
	for groove_y in [-0.75, -0.25, 0.25, 0.75]:
		var groove := CSGBox3D.new()
		groove.operation = CSGShape3D.OPERATION_SUBTRACTION
		groove.size = Vector3(2.38, 0.03, 0.03)
		groove.position = Vector3(0, groove_y, 0.06)
		_slab.add_child(groove)

	# Frame posts with piston rams the slab "rides" on.
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.13, 0.13, 0.16)
	for post_x in [-1.26, 1.26]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.16, 2.5, 0.24)
		post_mesh.material = iron
		post.mesh = post_mesh
		post.position = Vector3(post_x, 1.25, 0)
		add_child(post)
	for ram_x in [-1.08, 1.08]:
		var ram := MeshInstance3D.new()
		var ram_mesh := CylinderMesh.new()
		ram_mesh.top_radius = 0.05
		ram_mesh.bottom_radius = 0.05
		ram_mesh.height = 2.3
		ram_mesh.material = steel
		ram.mesh = ram_mesh
		ram.position = Vector3(ram_x, 1.15, 0.12)
		add_child(ram)

	# Status lamp: amber = locked, cyan = vented.
	_lamp_mat.emission_enabled = true
	_apply_lamp_color(COLOR_WAIT)
	var lamp := MeshInstance3D.new()
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.07
	lamp_mesh.height = 0.14
	lamp.mesh = lamp_mesh
	lamp.material_override = _lamp_mat
	lamp.position = Vector3(0, 2.62, 0.08)
	add_child(lamp)
	_lamp_light = OmniLight3D.new()
	_lamp_light.light_color = COLOR_WAIT
	_lamp_light.light_energy = 0.7
	_lamp_light.omni_range = 3.0
	_lamp_light.position = Vector3(0, 2.62, 0.4)
	add_child(_lamp_light)

	var label := Label3D.new()
	label.text = "PRESSURE LOCK"
	label.font_size = 40
	label.pixel_size = 0.004
	label.modulate = Color(0.85, 0.68, 0.3)
	label.position = Vector3(0, 2.38, 0.09)
	add_child(label)


## Wired to PressurePuzzleManager.puzzle_solved: vent and sink the slab.
func activate() -> void:
	if is_open:
		return
	is_open = true
	_apply_lamp_color(COLOR_DONE)
	_lamp_light.light_color = COLOR_DONE
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_slab, "position:y", _slab.position.y - 2.35, open_duration)
	Player.shake(0.4, global_position)
	Door._dust_puff(global_position + Vector3(-0.7, 0, 0), 10)
	Door._dust_puff(global_position + Vector3(0.7, 0, 0), 10)
	AudioSynthesizer.play_at("steam", global_position, -8.0, 1.3)
	AudioSynthesizer.play_at("chime", global_position, -12.0, 0.7)
	opened.emit()


func _apply_lamp_color(color: Color) -> void:
	_lamp_mat.albedo_color = color
	_lamp_mat.emission = color
	_lamp_mat.emission_energy_multiplier = 2.0
