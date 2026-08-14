class_name MainMenu
extends Control

## 2D main menu built on the painted concept-art backdrop. Layered live
## effects sit on top of the art: rising ember particles and flickering
## PointLight2D glows over the painted fireplace and candles, plus looping
## fire-crackle ambience. Brass-styled buttons overlay the art's baked-in
## button plates. Solo runs launch straight into Main; co-op buttons route
## to the Lobby scene.

const MAIN_SCENE := "res://scenes/Main.tscn"
const LOBBY_SCENE := "res://scenes/Lobby.tscn"

## The art is authored at 1024x575 and drawn KeepAspectCovered into the
## 1152x648 design viewport, so image-space positions scale by ~1.127.
## Positions below are already converted to design-space pixels.
const FIRE_POS := Vector2(613, 262)      # center of the painted flames
const EMBER_POS := Vector2(613, 300)     # hearth floor, where embers spawn
const CANDLE_POS := Vector2(756, 349)    # candle cluster on the desk

@onready var _controls_modal: Control = $UI/ControlsModal
@onready var _music_player: AudioStreamPlayer = $MusicPlayer
@onready var _fire_crackle: AudioStreamPlayer = $FireCrackle
@onready var _music_slider: HSlider = $UI/MusicVolumeContainer/MusicVolumeSlider

var _fire_light: PointLight2D
var _candle_light: PointLight2D
var _flicker_time := 0.0
var _music_stream: AudioStream


func _ready() -> void:
	# Returning from a lobby or finished run: clear stale network state.
	NetworkSession.reset()
	multiplayer.multiplayer_peer = null

	_build_fire_effects()
	_shield_ui_from_lights($UI)
	_style_buttons()

	$UI/Buttons/StartButton.pressed.connect(_start_solo)
	$UI/Buttons/HostButton.pressed.connect(_open_lobby.bind("host"))
	$UI/Buttons/JoinButton.pressed.connect(_open_lobby.bind("join"))
	$UI/Buttons/ControlsButton.pressed.connect(func() -> void: _controls_modal.visible = true)
	$UI/Buttons/QuitButton.pressed.connect(func() -> void: get_tree().quit())
	$UI/ControlsModal/Center/Panel/VBox/CloseControlsButton.pressed.connect(
		func() -> void: _controls_modal.visible = false)

	# Music volume slider
	_music_slider.value = 30.0  # 30% default
	_music_slider.value_changed.connect(_on_music_volume_changed)

	# Load and play menu music on loop
	_music_stream = load("res://assets/music/MainMenu.mp3")
	if _music_stream:
		_music_player.stream = _music_stream
		_music_player.bus = "Master"
		_music_player.volume_db = linear_to_db(0.3)
		_music_player.play()

	# Fire crackle autoplays from the scene; make sure the MP3 loops.
	if _fire_crackle.stream is AudioStreamMP3:
		_fire_crackle.stream.loop = true


func _process(delta: float) -> void:
	_flicker_time += delta
	# Organic dual-sine flicker with a touch of noise, fire and candles
	# on different rhythms so the room feels alive.
	if _fire_light:
		var flicker := sin(_flicker_time * 3.4) * 0.12 + sin(_flicker_time * 7.7 + 2.0) * 0.06
		_fire_light.energy = clampf(0.9 + flicker + randf_range(-0.05, 0.05), 0.65, 1.15)
	if _candle_light:
		var waver := sin(_flicker_time * 5.1 + 1.3) * 0.08
		_candle_light.energy = clampf(0.5 + waver + randf_range(-0.04, 0.04), 0.3, 0.7)


func _on_music_volume_changed(value: float) -> void:
	var volume_db := linear_to_db(value / 100.0)
	if _music_player:
		_music_player.volume_db = volume_db


# --- Fire & ambient effects ----------------------------------------------


func _build_fire_effects() -> void:
	var fx: Node2D = $FireFX

	# Soft radial glow texture shared by both lights.
	var glow := GradientTexture2D.new()
	glow.width = 256
	glow.height = 256
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(0.5, 0.0)
	var glow_gradient := Gradient.new()
	glow_gradient.set_color(0, Color(1, 1, 1, 1))
	glow_gradient.set_color(1, Color(1, 1, 1, 0))
	glow.gradient = glow_gradient

	_fire_light = PointLight2D.new()
	_fire_light.texture = glow
	_fire_light.color = Color(1.0, 0.6, 0.28)
	_fire_light.energy = 0.9
	_fire_light.texture_scale = 3.2
	_fire_light.blend_mode = Light2D.BLEND_MODE_ADD
	_fire_light.position = FIRE_POS
	fx.add_child(_fire_light)

	_candle_light = PointLight2D.new()
	_candle_light.texture = glow
	_candle_light.color = Color(1.0, 0.75, 0.42)
	_candle_light.energy = 0.5
	_candle_light.texture_scale = 1.5
	_candle_light.blend_mode = Light2D.BLEND_MODE_ADD
	_candle_light.position = CANDLE_POS
	fx.add_child(_candle_light)

	# Rising embers over the fireplace opening.
	var embers := GPUParticles2D.new()
	embers.amount = 36
	embers.lifetime = 1.6
	embers.position = EMBER_POS

	var ember_mat := ParticleProcessMaterial.new()
	ember_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	ember_mat.emission_box_extents = Vector3(50, 6, 1)
	ember_mat.direction = Vector3(0, -1, 0)
	ember_mat.spread = 12.0
	ember_mat.initial_velocity_min = 26.0
	ember_mat.initial_velocity_max = 60.0
	ember_mat.gravity = Vector3(0, -26, 0)  # embers accelerate gently upward
	ember_mat.scale_min = 0.15
	ember_mat.scale_max = 0.35
	ember_mat.color_ramp = _get_ember_color_gradient()
	embers.process_material = ember_mat

	# Soft round dot texture for each ember.
	var dot := GradientTexture2D.new()
	dot.width = 16
	dot.height = 16
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(0.5, 0.0)
	var dot_gradient := Gradient.new()
	dot_gradient.set_color(0, Color(1, 1, 1, 1))
	dot_gradient.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = dot_gradient
	embers.texture = dot

	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	embers.material = additive
	fx.add_child(embers)


func _get_ember_color_gradient() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.9, 0.55, 0.0))    # fade in from nothing
	gradient.set_color(1, Color(0.3, 0.05, 0.02, 0.0))   # cooled ember, gone
	gradient.add_point(0.15, Color(1.0, 0.7, 0.3, 0.9))  # hot orange
	gradient.add_point(0.6, Color(0.85, 0.25, 0.06, 0.6))  # dimming red
	var tex := GradientTexture1D.new()
	tex.gradient = gradient
	return tex


## The 2D lights should only warm the painted backdrop, not tint the UI.
func _shield_ui_from_lights(node: Node) -> void:
	if node is CanvasItem:
		node.light_mask = 0
	for child in node.get_children():
		_shield_ui_from_lights(child)


# --- Navigation -----------------------------------------------------------


func _start_solo() -> void:
	NetworkSession.reset()
	get_tree().change_scene_to_file(MAIN_SCENE)


func _open_lobby(mode: String) -> void:
	NetworkSession.lobby_mode = mode
	get_tree().change_scene_to_file(LOBBY_SCENE)


# --- Presentation --------------------------------------------------------


func _style_buttons() -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.09, 0.07, 0.045, 0.96)
	normal.border_color = Color(0.55, 0.42, 0.18)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 16.0
	normal.content_margin_right = 16.0
	normal.content_margin_top = 10.0
	normal.content_margin_bottom = 10.0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = Color(1.0, 0.82, 0.35)
	hover.bg_color = Color(0.14, 0.105, 0.06, 0.97)
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.05, 0.04, 0.03, 0.97)

	for button in _all_buttons($UI):
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", pressed)
		button.add_theme_stylebox_override("focus", normal)
		button.add_theme_color_override("font_color", Color(0.9, 0.8, 0.6))
		button.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.68))
		button.add_theme_font_size_override("font_size", 20)
		button.mouse_entered.connect(func() -> void: AudioSynthesizer.play_ui("ratchet", -20.0, 1.7))
		button.pressed.connect(func() -> void: AudioSynthesizer.play_ui("tick", -8.0, 1.25))


func _all_buttons(node: Node) -> Array:
	var found: Array = []
	for child in node.get_children():
		if child is Button:
			found.append(child)
		found.append_array(_all_buttons(child))
	return found
