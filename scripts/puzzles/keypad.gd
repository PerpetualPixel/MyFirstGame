class_name Keypad
extends Interactable

## Front-door keypad. Dead (dark faceplate) until the fuse panel restores
## power, then the face lights up (KeypadOnline art) and [E] opens a
## fullscreen keypad: hotspot buttons over the painted digits, a 4-digit
## PIN (found in the notebook out by the garage trash) and the front
## doors swing open on a match. Wrong codes buzz and clear.

signal access_granted

const FACE_OFF_PATH := "res://assets/puzzles/Keypad.jpg"
const FACE_ON_PATH := "res://assets/puzzles/KeypadOnline.jpg"

## Board-space (1056x576) centers of the painted keys.
const KEYS := [
	["1", Vector2(417, 301)], ["2", Vector2(491, 301)], ["3", Vector2(562, 301)],
	["4", Vector2(417, 364)], ["5", Vector2(491, 364)], ["6", Vector2(562, 364)],
	["7", Vector2(417, 433)], ["8", Vector2(491, 433)], ["9", Vector2(562, 433)],
	["CLEAR", Vector2(417, 496)], ["0", Vector2(491, 496)],
	["X", Vector2(644, 317)], ["ENTER", Vector2(647, 454)],
]

@export var pin_code: int = 1234

var powered := false
var is_open := false
var is_unlocked := false

var _entered := ""
var _display: Label
var _overlay: CanvasLayer
var _face: MeshInstance3D
var _face_mat: StandardMaterial3D


func _ready() -> void:
	# The keypad UI pauses the tree in solo; keep processing so the ESC
	# handler and close timers still run while paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_face()
	_build_overlay()


func power_on() -> void:
	if powered:
		return
	powered = true
	if ResourceLoader.exists(FACE_ON_PATH):
		_face_mat.albedo_texture = load(FACE_ON_PATH)
		_face_mat.emission_enabled = true
		_face_mat.emission = Color(0.25, 0.6, 0.35)
		_face_mat.emission_energy_multiplier = 0.35
	AudioSynthesizer.play_at("tick", global_position, -8.0, 1.4)


func can_interact(_by: Node3D) -> bool:
	return not is_unlocked


func get_prompt(_by: Node3D = null) -> String:
	if not powered:
		return "Keypad — dead, no power"
	return "[E] Use Keypad"


func interact(by: Node3D) -> void:
	if not powered or is_unlocked:
		return
	if by == null or not by.has_method("is_local_player") or by.is_local_player():
		_open_ui()
	super.interact(by)


# --- Fullscreen keypad UI --------------------------------------------------


func _open_ui() -> void:
	if is_open:
		return
	is_open = true
	_entered = ""
	_refresh_display()
	_overlay.visible = true
	add_to_group("modal_ui")
	if NetworkSession.multiplayer_active:
		_set_local_lock(true)
	else:
		get_tree().paused = true


func _close_ui() -> void:
	if not is_open:
		return
	is_open = false
	_overlay.visible = false
	remove_from_group("modal_ui")
	if NetworkSession.multiplayer_active:
		_set_local_lock(false)
	else:
		get_tree().paused = false


func _set_local_lock(locked: bool) -> void:
	for player in get_tree().get_nodes_in_group("players"):
		if player.is_local_player():
			player.ui_locked = locked


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close_ui()
		return
	# Full keyboard entry: number row + numpad, Backspace/Delete to back
	# up, Enter to submit.
	if event is InputEventKey and event.pressed and not event.echo:
		var handled := true
		match event.keycode:
			KEY_0, KEY_KP_0: _on_key("0")
			KEY_1, KEY_KP_1: _on_key("1")
			KEY_2, KEY_KP_2: _on_key("2")
			KEY_3, KEY_KP_3: _on_key("3")
			KEY_4, KEY_KP_4: _on_key("4")
			KEY_5, KEY_KP_5: _on_key("5")
			KEY_6, KEY_KP_6: _on_key("6")
			KEY_7, KEY_KP_7: _on_key("7")
			KEY_8, KEY_KP_8: _on_key("8")
			KEY_9, KEY_KP_9: _on_key("9")
			KEY_BACKSPACE, KEY_DELETE: _on_key("BACK")
			KEY_ENTER, KEY_KP_ENTER: _on_key("ENTER")
			_: handled = false
		if handled:
			get_viewport().set_input_as_handled()


func _on_key(key: String) -> void:
	match key:
		"X":
			AudioSynthesizer.play_ui("tick", -12.0, 0.9)
			_close_ui()
		"CLEAR":
			AudioSynthesizer.play_ui("tick", -12.0, 0.9)
			_entered = ""
			_refresh_display()
		"BACK":
			if _entered.length() > 0:
				_entered = _entered.substr(0, _entered.length() - 1)
				AudioSynthesizer.play_ui("tick", -12.0, 0.85)
				_refresh_display()
		"ENTER":
			_try_pin()
		_:
			if _entered.length() < 4:
				_entered += key
				AudioSynthesizer.play_ui("tick", -10.0, 1.3)
				_refresh_display()


## Also the test hook: feed a full code and confirm.
func try_pin(code: String) -> bool:
	_entered = code
	_try_pin()
	return is_unlocked


func _try_pin() -> void:
	if _entered == "%04d" % pin_code:
		is_unlocked = true
		_display.text = "OPEN"
		_display.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
		AudioSynthesizer.play_ui("chime", -6.0, 1.2)
		if NetworkSession.multiplayer_active:
			_net_grant.rpc()
		else:
			access_granted.emit()
		var timer := get_tree().create_timer(0.6, true)
		timer.timeout.connect(_close_ui)
	else:
		AudioSynthesizer.play_ui("zap", -10.0)
		_display.text = "ERROR"
		_display.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
		_entered = ""
		var timer := get_tree().create_timer(0.7, true)
		timer.timeout.connect(_refresh_display)


@rpc("any_peer", "call_local", "reliable")
func _net_grant() -> void:
	is_unlocked = true
	access_granted.emit()


func _refresh_display() -> void:
	if is_unlocked:
		return
	_display.add_theme_color_override("font_color", Color(0.45, 1.0, 0.6))
	if _entered.is_empty():
		_display.text = "–"
	else:
		var dots := ""
		for i in _entered.length():
			dots += "●"
		_display.text = dots


# --- Construction ----------------------------------------------------------


## Wall plate + textured face quad (starts dark, lights up with power).
func _build_face() -> void:
	_face_mat = StandardMaterial3D.new()
	_face_mat.roughness = 0.6
	if ResourceLoader.exists(FACE_OFF_PATH):
		_face_mat.albedo_texture = load(FACE_OFF_PATH)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.42, 0.55)
	quad.material = _face_mat
	_face = MeshInstance3D.new()
	_face.mesh = quad
	_face.position = Vector3(0, 0, 0.035)
	add_child(_face)

	var backing := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.46, 0.6, 0.06)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.25, 0.26, 0.3)
	iron.metallic = 0.6
	iron.roughness = 0.5
	box.material = iron
	backing.mesh = box
	add_child(backing)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 0.64, 0.12)
	col.shape = shape
	add_child(col)


## Fullscreen hotspot UI over the KeypadOnline art.
func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 10
	_overlay.visible = false
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_overlay)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	# Explicit anchors + all four offsets: PRESET_CENTER with a minimum
	# size anchored the rect at screen center extending right/down,
	# which rendered the art zoomed and cut off.
	var board := Control.new()
	board.anchor_left = 0.5
	board.anchor_top = 0.5
	board.anchor_right = 0.5
	board.anchor_bottom = 0.5
	board.offset_left = -528
	board.offset_top = -288
	board.offset_right = 528
	board.offset_bottom = 288
	root.add_child(board)

	var backdrop := TextureRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(FACE_ON_PATH):
		backdrop.texture = load(FACE_ON_PATH)
	board.add_child(backdrop)

	_display = Label.new()
	_display.position = Vector2(529 - 152, 148 - 40)
	_display.size = Vector2(304, 80)
	_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_display.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_display.add_theme_font_size_override("font_size", 44)
	_display.add_theme_color_override("font_color", Color(0.45, 1.0, 0.6))
	board.add_child(_display)

	for key_def in KEYS:
		var b := Button.new()
		var size := Vector2(58, 54) if key_def[0] != "ENTER" and key_def[0] != "X" else Vector2(66, 90)
		b.position = (key_def[1] as Vector2) - size / 2.0
		b.size = size
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		var hover := StyleBoxFlat.new()
		hover.bg_color = Color(1, 1, 1, 0.14)
		hover.set_corner_radius_all(10)
		var empty := StyleBoxEmpty.new()
		b.add_theme_stylebox_override("normal", empty)
		b.add_theme_stylebox_override("focus", empty)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", hover)
		b.pressed.connect(_on_key.bind(key_def[0]))
		board.add_child(b)

	var close := Button.new()
	close.text = "✕"
	close.position = Vector2(980, 10)
	close.size = Vector2(66, 34)
	close.pressed.connect(_close_ui)
	board.add_child(close)
