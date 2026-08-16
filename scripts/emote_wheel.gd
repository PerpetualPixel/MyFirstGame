class_name EmoteWheel
extends CanvasLayer

## Radial emote picker. Hold the emote key ([B] by default) to open the
## wheel at screen center; the mouse (or the movement keys) points at a
## wedge, releasing the key plays it. [ESC] or clicking the middle
## cancels. Never pauses the game — emotes are for standing around in
## co-op, and the partner sees the dance through the player's RPC.

const RADIUS := 150.0
const HUB := 46.0

var is_open := false

var _entries: Array = []
var _selected := -1
var _wheel: Control
var _label: Label
var _player: Node


func _ready() -> void:
	layer = 15
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)
	_wheel = Control.new()
	_wheel.set_anchors_preset(Control.PRESET_CENTER)
	_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheel.draw.connect(_draw_wheel)
	overlay.add_child(_wheel)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_label.offset_top = -140.0
	_label.offset_bottom = -104.0
	_label.offset_left = -300.0
	_label.offset_right = 300.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_label.add_theme_constant_override("outline_size", 6)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_label)


func open(player: Node) -> void:
	if is_open or player == null:
		return
	_player = player
	_entries = player.available_emotes()
	if _entries.is_empty():
		return
	is_open = true
	visible = true
	_selected = -1
	add_to_group("modal_ui")
	_update_selection()


## Close the wheel; `play` fires the highlighted emote (key release).
func close(play: bool) -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	remove_from_group("modal_ui")
	if play and _selected >= 0 and _selected < _entries.size() and is_instance_valid(_player):
		_player.request_emote(_entries[_selected][0])
		AudioSynthesizer.play_ui("tick", -12.0, 1.3)
	_player = null


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_update_selection()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close(false)


func _process(_delta: float) -> void:
	if is_open:
		_update_selection()


## The wedge under the mouse (center dead zone = no selection).
func _update_selection() -> void:
	var center := Vector2(get_viewport().get_visible_rect().size) * 0.5
	var to_mouse := _wheel.get_global_mouse_position() - center
	var previous := _selected
	if to_mouse.length() < HUB:
		_selected = -1
	else:
		var wedge := TAU / float(_entries.size())
		# Screen angle, measured clockwise from straight up.
		var angle := fposmod(atan2(to_mouse.x, -to_mouse.y), TAU)
		_selected = int(floor((angle + wedge * 0.5) / wedge)) % _entries.size()
	if _selected != previous:
		if _selected >= 0:
			AudioSynthesizer.play_ui("tick", -20.0, 1.5)
		_label.text = _entries[_selected][1] if _selected >= 0 else "Release to cancel"
		_label.modulate = Color(1.0, 0.85, 0.45) if _selected >= 0 else Color(0.7, 0.65, 0.55)
		_wheel.queue_redraw()


func _draw_wheel() -> void:
	var center := Vector2(get_viewport().get_visible_rect().size) * 0.5 - _wheel.global_position
	var count := _entries.size()
	var wedge := TAU / float(count)
	for i in count:
		# Screen space: 0 rad points up, angles run clockwise.
		var mid := -PI / 2.0 + wedge * i
		var start := mid - wedge * 0.5
		var points := PackedVector2Array()
		points.append(center + Vector2(cos(mid), sin(mid)) * HUB)
		for s in 13:
			var a := start + wedge * (float(s) / 12.0)
			points.append(center + Vector2(cos(a), sin(a)) * RADIUS)
		var fill := Color(0.9, 0.72, 0.3, 0.85) if i == _selected else Color(0.1, 0.09, 0.08, 0.8)
		_wheel.draw_colored_polygon(points, fill)
		_wheel.draw_polyline(points, Color(0.55, 0.42, 0.18, 0.9), 2.0, true)
		var text_at := center + Vector2(cos(mid), sin(mid)) * (RADIUS * 0.66)
		var font := ThemeDB.fallback_font
		var label: String = _entries[i][1]
		var text_color := Color(0.1, 0.08, 0.05) if i == _selected else Color(0.9, 0.85, 0.7)
		_wheel.draw_string(font, text_at + Vector2(-60, 6), label,
			HORIZONTAL_ALIGNMENT_CENTER, 120, 17, text_color)
	_wheel.draw_circle(center, HUB, Color(0.06, 0.05, 0.04, 0.9))
	_wheel.draw_arc(center, HUB, 0, TAU, 32, Color(0.55, 0.42, 0.18, 0.9), 2.0)
