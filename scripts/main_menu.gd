class_name MainMenu
extends Node3D

## Cinematic 3D main menu: a moody diorama of the inventor's desk under a
## slow orbiting camera. Solo runs launch straight into Main; co-op buttons
## route to the Lobby scene (ENet LAN, port 8910).

const MAIN_SCENE := "res://scenes/Main.tscn"
const LOBBY_SCENE := "res://scenes/Lobby.tscn"

@onready var _pivot: Node3D = $CameraPivot
@onready var _camera: Camera3D = $CameraPivot/Camera3D
@onready var _controls_modal: Control = $UI/Root/ControlsModal

var _gears: Array[MeshInstance3D] = []
var _orbit_time := 0.0


func _ready() -> void:
	# Returning from a lobby or finished run: clear stale network state.
	NetworkSession.reset()
	multiplayer.multiplayer_peer = null

	_build_diorama()
	_style_buttons()

	$UI/Root/Buttons/StartButton.pressed.connect(_start_solo)
	$UI/Root/Buttons/HostButton.pressed.connect(_open_lobby.bind("host"))
	$UI/Root/Buttons/JoinButton.pressed.connect(_open_lobby.bind("join"))
	$UI/Root/Buttons/ControlsButton.pressed.connect(func() -> void: _controls_modal.visible = true)
	$UI/Root/Buttons/QuitButton.pressed.connect(func() -> void: get_tree().quit())
	$UI/Root/ControlsModal/Center/Panel/VBox/CloseControlsButton.pressed.connect(
		func() -> void: _controls_modal.visible = false)

	# Ambience: wind/rain bed plus a slow grandfather-clock tick.
	AudioSynthesizer.create_ui_loop("wind", -14.0)
	var tick := Timer.new()
	tick.wait_time = 1.2
	tick.autostart = true
	tick.timeout.connect(func() -> void: AudioSynthesizer.play_ui("tick", -18.0, 0.8))
	add_child(tick)


func _process(delta: float) -> void:
	_orbit_time += delta
	_pivot.rotation.y += delta * 0.06
	_camera.position.y = 2.3 + sin(_orbit_time * 0.4) * 0.12
	_camera.look_at(Vector3(0, 1.0, 0))
	for gear in _gears:
		gear.rotate_object_local(Vector3.UP, delta * 0.8)


func _start_solo() -> void:
	NetworkSession.reset()
	get_tree().change_scene_to_file(MAIN_SCENE)


func _open_lobby(mode: String) -> void:
	NetworkSession.lobby_mode = mode
	get_tree().change_scene_to_file(LOBBY_SCENE)


# --- Presentation --------------------------------------------------------


func _style_buttons() -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.07, 0.055, 0.04, 0.75)
	normal.border_color = Color(0.55, 0.42, 0.18)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 16.0
	normal.content_margin_right = 16.0
	normal.content_margin_top = 10.0
	normal.content_margin_bottom = 10.0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = Color(1.0, 0.82, 0.35)
	hover.bg_color = Color(0.13, 0.1, 0.055, 0.85)
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.05, 0.04, 0.03, 0.9)

	for button in _all_buttons($UI):
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", pressed)
		button.add_theme_stylebox_override("focus", normal)
		button.add_theme_color_override("font_color", Color(0.9, 0.8, 0.6))
		button.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.68))
		button.mouse_entered.connect(func() -> void: AudioSynthesizer.play_ui("ratchet", -20.0, 1.7))
		button.pressed.connect(func() -> void: AudioSynthesizer.play_ui("tick", -8.0, 1.25))


func _all_buttons(node: Node) -> Array:
	var found: Array = []
	for child in node.get_children():
		if child is Button:
			found.append(child)
		found.append_array(_all_buttons(child))
	return found


func _build_diorama() -> void:
	var mahogany := _mat(Color(0.3, 0.14, 0.08), 0.0, 0.55)
	var brass := _mat(Color(0.72, 0.55, 0.25), 0.7, 0.4)
	var dark_brass := _mat(Color(0.4, 0.3, 0.14), 0.6, 0.5)
	var paper := _mat(Color(0.22, 0.32, 0.55), 0.0, 0.8)
	var floor_mat := _mat(Color(0.1, 0.09, 0.1), 0.0, 0.8)

	_box(Vector3(0, -0.05, 0), Vector3(8, 0.1, 8), floor_mat)
	_box(Vector3(0, 1.5, -2.2), Vector3(6, 3.2, 0.15), _mat(Color(0.14, 0.12, 0.12), 0.0, 0.8))

	_box(Vector3(0, 0.92, 0), Vector3(2.3, 0.12, 1.25), mahogany)
	for corner in [Vector3(1.0, 0.45, 0.5), Vector3(-1.0, 0.45, 0.5), Vector3(1.0, 0.45, -0.5), Vector3(-1.0, 0.45, -0.5)]:
		_box(corner, Vector3(0.12, 0.9, 0.12), mahogany)

	var gold := _mat(Color(0.95, 0.78, 0.3), 0.7, 0.3)
	gold.emission_enabled = true
	gold.emission = Color(0.9, 0.7, 0.25)
	gold.emission_energy_multiplier = 1.4
	var scroll := _cylinder(Vector3(0, 1.06, 0), 0.07, 0.5, gold)
	scroll.rotation.z = PI / 2.0
	var will_light := OmniLight3D.new()
	will_light.light_color = Color(1.0, 0.85, 0.45)
	will_light.light_energy = 1.1
	will_light.omni_range = 2.6
	will_light.position = Vector3(0, 1.4, 0)
	add_child(will_light)

	var tube_glow := _mat(Color(1.0, 0.7, 0.35), 0.0, 0.3)
	tube_glow.emission_enabled = true
	tube_glow.emission = Color(1.0, 0.6, 0.25)
	tube_glow.emission_energy_multiplier = 2.2
	for spot in [Vector3(-0.75, 0, 0.3), Vector3(-0.55, 0, -0.35), Vector3(-0.95, 0, -0.05)]:
		_cylinder(spot + Vector3(0, 1.01, 0), 0.07, 0.06, brass)
		_cylinder(spot + Vector3(0, 1.16, 0), 0.045, 0.24, tube_glow)

	_box(Vector3(0.75, 1.13, -0.3), Vector3(0.5, 0.3, 0.35), dark_brass)
	var gear_a := _cylinder(Vector3(0.65, 1.34, -0.1), 0.12, 0.03, brass)
	gear_a.rotation.x = PI / 2.0
	_gears.append(gear_a)
	var gear_b := _cylinder(Vector3(0.88, 1.31, -0.1), 0.08, 0.03, brass)
	gear_b.rotation.x = PI / 2.0
	_gears.append(gear_b)

	var print_a := _box(Vector3(0.35, 0.985, 0.35), Vector3(0.55, 0.01, 0.4), paper)
	print_a.rotation.y = 0.4
	var print_b := _box(Vector3(-0.4, 0.985, -0.38), Vector3(0.5, 0.01, 0.36), paper)
	print_b.rotation.y = -0.3
	_cylinder(Vector3(0.15, 1.0, -0.45), 0.09, 0.03, brass)

	for spot in [Vector3(1.3, 1.9, 0.9), Vector3(-1.3, 1.7, 0.6)]:
		var flame := FlickerLight.new()
		flame.base_energy = 0.55
		flame.light_color = Color(1.0, 0.75, 0.4)
		flame.omni_range = 4.0
		flame.position = spot
		add_child(flame)

	var dust := GPUParticles3D.new()
	dust.amount = 26
	dust.lifetime = 7.0
	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(1.4, 0.8, 0.8)
	pmat.direction = Vector3(0, 1, 0)
	pmat.spread = 180.0
	pmat.initial_velocity_min = 0.01
	pmat.initial_velocity_max = 0.06
	pmat.gravity = Vector3.ZERO
	dust.process_material = pmat
	var mote := SphereMesh.new()
	mote.radius = 0.008
	mote.height = 0.016
	var mote_mat := StandardMaterial3D.new()
	mote_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote_mat.albedo_color = Color(1.0, 0.95, 0.8, 0.25)
	mote.material = mote_mat
	dust.draw_pass_1 = mote
	dust.position = Vector3(0, 1.6, 0)
	add_child(dust)


func _box(at: Vector3, size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	mesh.mesh = box
	mesh.position = at
	add_child(mesh)
	return mesh


func _cylinder(at: Vector3, radius: float, height: float, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.material = material
	mesh.mesh = cyl
	mesh.position = at
	add_child(mesh)
	return mesh


static func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat
