class_name ClockPanel
extends CanvasLayer

## Fullscreen first-person view into the grandfather clock's gear train —
## the same modal contract as the fuse and pressure panels: [E] on the
## clock case opens it (local machine only), solo pauses the tree, co-op
## locks just this player's input, [ESC] or ✕ steps away.
## Select-and-place: click one of your carried gears (bottom tray), then
## click a socket to seat it; click a seated gear to take it back. The
## engraved ratio names each socket's tooth count — wrong gears seat but
## never mesh, so the pendulum stays dead until the arrangement is right.
## Seats/removals route through the sockets' replicated request_* calls.

signal closed

const COLOR_BRASS := Color(0.85, 0.66, 0.28)
const COLOR_EMPTY := Color(1.0, 0.72, 0.25)
const COLOR_RUNNING := Color(0.45, 0.85, 0.5)
const COLOR_SEALED := Color(0.45, 0.45, 0.5)
const COLOR_SELECT := Color(0.4, 0.9, 1.0)

## Board-space centers of the three socket slots (matches the clock's
## physical layout: two low, one high).
const SOCKET_POS := [Vector2(320, 268), Vector2(580, 268), Vector2(450, 152)]

var is_open := false

## ClockworkMechanism (duck-typed to avoid a scene<->script preload cycle).
var _clock: Node
var _socket_buttons: Array[Button] = []
## Engraved numerals over each socket. Refreshed LIVE from the 3D
## sockets, never cached: the generator shuffles the requirements (and
## re-engraves the case) AFTER the clock enters the tree, i.e. after this
## panel is built.
var _numeral_labels: Array[Label] = []
var _gear_tray: Control
var _gear_buttons: Array[Button] = []
var _tray_gears: Array = []
var _selected_gear: Node = null
var _pulse_time := 0.0

@onready var _board: Control = $Overlay/Board
@onready var _hint: Label = $Overlay/Hint


func _ready() -> void:
	visible = false
	$Overlay/Board/CloseButton.pressed.connect(close)


## Called by the clock right after instancing; builds the case interior.
func setup(clock: Node) -> void:
	_clock = clock
	_build_face()
	for socket in _clock._sockets:
		socket.gear_changed.connect(_refresh)
	_clock.clock_completed.connect(_on_completed)


func _process(delta: float) -> void:
	if not is_open:
		return
	_pulse_time += delta
	for i in _socket_buttons.size():
		var socket: Node = _clock._sockets[i]
		if socket.gear == null and not _clock.is_running:
			_socket_buttons[i].modulate.a = 0.6 + 0.4 * (0.5 + 0.5 * sin(_pulse_time * 3.0))
		else:
			_socket_buttons[i].modulate.a = 1.0


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func open() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	add_to_group("modal_ui")
	# Solo pauses the whole tree; in co-op the world keeps running for the
	# partner, so only this machine's player input locks (FusePanel rules).
	if NetworkSession.multiplayer_active:
		_set_local_lock(true)
	else:
		get_tree().paused = true
	_selected_gear = null
	_refresh()


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	remove_from_group("modal_ui")
	if NetworkSession.multiplayer_active:
		_set_local_lock(false)
	else:
		get_tree().paused = false
	closed.emit()


func _set_local_lock(locked: bool) -> void:
	for player in get_tree().get_nodes_in_group("players"):
		if player.is_local_player():
			player.ui_locked = locked


func _local_player() -> Node:
	for player in get_tree().get_nodes_in_group("players"):
		if player.is_local_player():
			return player
	return null


# --- Click handlers ------------------------------------------------------


func _on_socket_clicked(index: int) -> void:
	var local := _local_player()
	if local == null or _clock.is_running:
		return
	var socket: Node = _clock._sockets[index]
	if socket.gear != null:
		# Take the seated gear back into the pack.
		AudioSynthesizer.play_ui("ratchet", -10.0)
		socket.request_remove(local)
		_selected_gear = null
		_refresh()
		return
	var gears := _carried_gears(local)
	if gears.is_empty():
		_hint.text = "No gears in your pack — search the estate's side rooms.  [ESC] steps away."
		AudioSynthesizer.play_ui("tick", -14.0, 0.8)
		return
	var chosen: Node = _selected_gear
	if chosen == null and gears.size() == 1:
		chosen = gears[0]
	if chosen == null:
		_hint.text = "Several gears in the pack — click one in the tray first."
		AudioSynthesizer.play_ui("tick", -14.0, 0.8)
		return
	AudioSynthesizer.play_ui("ratchet", -8.0)
	socket.request_seat(local, chosen)
	_selected_gear = null
	_refresh()


func _on_gear_clicked(index: int) -> void:
	if index >= _tray_gears.size():
		return
	var gear: Node = _tray_gears[index]
	_selected_gear = null if _selected_gear == gear else gear
	AudioSynthesizer.play_ui("tick", -12.0, 1.1)
	_refresh()


func _carried_gears(local: Node) -> Array:
	var gears: Array = []
	if local.get("inventory") != null:
		for item in local.inventory:
			if is_instance_valid(item) and item.is_in_group("clock_gears"):
				gears.append(item)
	return gears


# --- State -> visuals ----------------------------------------------------


func _refresh() -> void:
	# Rebuild the tray (the pack changes as gears seat/unseat).
	for btn in _gear_buttons:
		btn.queue_free()
	_gear_buttons.clear()
	_tray_gears.clear()
	var local := _local_player()
	if local != null:
		_tray_gears = _carried_gears(local)
	for i in _tray_gears.size():
		var gear: Node = _tray_gears[i]
		var btn := _flat_button(Vector2(330.0 + 90.0 * i, 402), Vector2(80, 80))
		btn.draw.connect(_draw_tray_gear.bind(btn, i))
		btn.pressed.connect(_on_gear_clicked.bind(i))
		_gear_tray.add_child(btn)
		_gear_buttons.append(btn)
	# Mirror the case's live engravings (they are shuffled per run).
	for i in _numeral_labels.size():
		_numeral_labels[i].text = str(_clock._sockets[i].get_node("Numeral").text)
	for btn in _socket_buttons:
		btn.queue_redraw()
	var seated := 0
	for socket in _clock._sockets:
		if socket.gear != null:
			seated += 1
	if _clock.is_running:
		_hint.text = "The gear train meshes — the clock lives again!"
		_hint.modulate = Color(0.55, 1.0, 0.65)
	elif seated == _clock._sockets.size():
		# Every socket filled yet nothing turns: the arrangement is wrong.
		_hint.text = "The train binds — a gear sits in the wrong socket. Match each numeral to its tooth count.  [ESC] steps away."
		_hint.modulate = Color(1.0, 0.6, 0.5)
	elif _selected_gear != null:
		_hint.text = "%s selected — click a socket to seat it.  [ESC] steps away." % _selected_gear.display_name
		_hint.modulate = Color.WHITE
	else:
		_hint.text = "Match the engraved ratio: click a gear, then a socket. Click a seated gear to take it back.  [ESC] steps away."
		_hint.modulate = Color.WHITE


func _on_completed() -> void:
	_refresh()
	if not is_open:
		return
	AudioSynthesizer.play_ui("chime", -8.0)
	# Let the ticking sink in, then step back into the world (the timer
	# runs through the solo pause).
	await get_tree().create_timer(1.6, true).timeout
	close()


# --- Face construction ---------------------------------------------------


func _build_face() -> void:
	# Dark walnut case interior behind everything.
	var plate := Panel.new()
	var plate_style := StyleBoxFlat.new()
	plate_style.bg_color = Color(0.12, 0.08, 0.05)
	plate_style.border_color = COLOR_BRASS
	plate_style.set_border_width_all(3)
	plate_style.set_corner_radius_all(10)
	plate.add_theme_stylebox_override("panel", plate_style)
	plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(plate)
	_board.move_child(plate, 0)

	var title := Label.new()
	title.text = "GRANDFATHER CLOCK — GEAR TRAIN"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.78, 0.5))
	title.position = Vector2(0, 14)
	title.size = Vector2(900, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_board.add_child(title)

	# The engraved hint, copied straight off the case.
	var engraving := Label.new()
	engraving.text = str(_clock.get_node("Engraving").text)
	engraving.add_theme_font_size_override("font_size", 18)
	engraving.add_theme_color_override("font_color", COLOR_BRASS)
	engraving.position = Vector2(0, 46)
	engraving.size = Vector2(900, 24)
	engraving.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_board.add_child(engraving)

	for i in _clock._sockets.size():
		var socket: Node = _clock._sockets[i]
		var pos: Vector2 = SOCKET_POS[i]
		var numeral := Label.new()
		numeral.text = str(socket.get_node("Numeral").text)
		numeral.add_theme_font_size_override("font_size", 20)
		numeral.add_theme_color_override("font_color", COLOR_BRASS)
		numeral.position = pos + Vector2(-60, -92)
		numeral.size = Vector2(120, 24)
		numeral.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_board.add_child(numeral)
		_numeral_labels.append(numeral)

		var btn := _flat_button(pos - Vector2(60, 60), Vector2(120, 120))
		btn.draw.connect(_draw_socket.bind(btn, i))
		btn.pressed.connect(_on_socket_clicked.bind(i))
		_board.add_child(btn)
		_socket_buttons.append(btn)

	var tray_label := Label.new()
	tray_label.text = "YOUR PACK — BRASS GEARS"
	tray_label.add_theme_font_size_override("font_size", 14)
	tray_label.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5))
	tray_label.position = Vector2(0, 378)
	tray_label.size = Vector2(900, 20)
	tray_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_board.add_child(tray_label)

	_gear_tray = Control.new()
	_gear_tray.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gear_tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(_gear_tray)


## Invisible-styled button: the draw callbacks paint the actual widget.
func _flat_button(at: Vector2, size: Vector2) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.position = at
	btn.size = size
	var empty := StyleBoxEmpty.new()
	for style in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(style, empty)
	return btn


# --- Custom drawing ------------------------------------------------------


func _draw_socket(btn: Button, index: int) -> void:
	var socket: Node = _clock._sockets[index]
	var c := btn.size / 2.0
	if socket.gear != null:
		var teeth := int(socket.gear.get_meta("teeth", 8))
		var color := COLOR_RUNNING if _clock.is_running else COLOR_BRASS
		_draw_gear(btn, c, teeth, color)
	else:
		# Empty mounting ring with the axle post.
		btn.draw_arc(c, 42.0, 0, TAU, 40, COLOR_EMPTY, 3.0)
		btn.draw_circle(c, 6.0, COLOR_EMPTY)


func _draw_tray_gear(btn: Button, index: int) -> void:
	if index >= _tray_gears.size():
		return
	var gear: Node = _tray_gears[index]
	var teeth := int(gear.get_meta("teeth", 8))
	var c := btn.size / 2.0
	var selected := gear == _selected_gear
	_draw_gear(btn, c, teeth, COLOR_SELECT if selected else COLOR_BRASS)
	if selected:
		btn.draw_arc(c, 38.0, 0, TAU, 40, COLOR_SELECT, 2.0)
	var font := ThemeDB.fallback_font
	btn.draw_string(font, Vector2(0, btn.size.y - 2.0), "%d" % teeth,
		HORIZONTAL_ALIGNMENT_CENTER, btn.size.x, 13, Color(0.8, 0.75, 0.65))


## A brass gear: rim, hub, and one tick per tooth — so tooth counts can
## be compared at a glance against the engraved ratio.
func _draw_gear(item: CanvasItem, c: Vector2, teeth: int, color: Color) -> void:
	var r := 14.0 + float(teeth)
	item.draw_arc(c, r, 0, TAU, 48, color, 3.0)
	for k in teeth:
		var a := TAU * float(k) / float(teeth)
		var dir := Vector2(cos(a), sin(a))
		item.draw_line(c + dir * r, c + dir * (r + 5.0), color, 3.0)
	item.draw_circle(c, r * 0.28, color)
	item.draw_arc(c, r * 0.55, 0, TAU, 24, Color(color.r, color.g, color.b, 0.45), 1.5)
