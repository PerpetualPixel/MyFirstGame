class_name WiringMinigame
extends CanvasLayer

## Tactile 8-wire fuse panel over painted breaker-box art. The sticky note
## in the art ("The Testament") dictates a STRICT sequence: wires must be
## connected in its riddle order, each to its riddled port. Any wrong wire
## or wrong port shorts the panel — zap SFX, all connections burn away,
## progress resets to step 0. Connections render as sagging bezier Line2D
## cables dragged (or click-click placed) from crimp lead to port screw.
## [ESC] steps away (consumed in _input so the pause menu never sees it).
## Solving powers the mansion via `solved`.

signal solved
signal closed

const BACKDROP_PATH := "res://assets/puzzles/BreakerBox.jpg"

## name, main color, stripe color (null = solid) — left-to-right in the art.
const WIRES := [
	["Red", Color(0.88, 0.22, 0.18), null],
	["Red/White", Color(0.88, 0.22, 0.18), Color(0.95, 0.95, 0.95)],
	["Blue", Color(0.25, 0.5, 0.95), null],
	["Blue/Gold", Color(0.25, 0.5, 0.95), Color(0.9, 0.75, 0.3)],
	["Yellow", Color(0.95, 0.85, 0.25), null],
	["Green", Color(0.3, 0.85, 0.4), null],
	["Black", Color(0.22, 0.22, 0.26), null],
	["Copper", Color(0.78, 0.52, 0.3), null],
]

## The Testament's strict order: [wire name, port index (0-based)].
## 1. "Reflective mirrors."            Green     -> Port 3
## 2. "Vault door brass knobs."        Blue/Gold -> Port 7
## 3. "Inventor's lucky number."       Blue      -> Port 8
## 4. "Follow the grand chimes."       Red/White -> Port 1
## 5. "Moonlight on crystals."         Red       -> Port 2
## 6. "AVOID the deep gears."          Yellow    -> Port 5 (not 6)
## 7. "Black: beware the leather spines." Black  -> Port 6 (not 4)
## 8. "The last, not where the first." Copper    -> Port 4, wired last
const SEQUENCE := [
	["Green", 2],
	["Blue/Gold", 6],
	["Blue", 7],
	["Red/White", 0],
	["Red", 1],
	["Yellow", 4],
	["Black", 5],
	["Copper", 3],
]

## Board-space (1024x576) centers of the 8 crimp leads, left-to-right,
## matching WIRES order. Measured off the painted art.
const TERMINAL_POS := [
	Vector2(152, 390), Vector2(190, 390), Vector2(228, 390), Vector2(266, 390),
	Vector2(304, 390), Vector2(342, 390), Vector2(380, 390), Vector2(418, 390),
]

## Board-space centers of port screws 1-8 on the right terminal block:
## two rows of four (1-4 top, 5-8 bottom).
const PORT_POS := [
	Vector2(685, 325), Vector2(745, 325), Vector2(805, 325), Vector2(865, 325),
	Vector2(685, 402), Vector2(745, 402), Vector2(805, 402), Vector2(865, 402),
]

var is_open := false
var is_solved := false

## Ground truth: wire name -> port index (0-based). Fixed by the Testament;
## insertion order IS the required connection order.
var _mapping := {}
## Testament clues in riddle form; every clue holds under _mapping.
var _clues: Array = []
var _connections := {}
var _step := 0
var _selected := ""
var _dragging := ""
var _drag_pos := Vector2.ZERO
var _terminal_buttons := {}
var _port_buttons: Array[Button] = []
var _wire_nodes := {}
var _drag_node: Node2D

@onready var _board: Control = $Overlay/Board
@onready var _backdrop: TextureRect = $Overlay/Board/Backdrop
@onready var _fallback_panel: ColorRect = $Overlay/Board/FallbackPanel
@onready var _fallback_note: Label = $Overlay/Board/FallbackNote
@onready var _hotspots: Control = $Overlay/Board/Hotspots
@onready var _hint: Label = $Overlay/Hint
@onready var _wire_layer: Control = $Overlay/WireLayer
@onready var _sparks: CPUParticles2D = $Overlay/Sparks


func _ready() -> void:
	visible = false
	_build_board_data()
	_build_hotspots()
	$Overlay/Board/CloseButton.pressed.connect(close)
	if ResourceLoader.exists(BACKDROP_PATH):
		_backdrop.texture = load(BACKDROP_PATH)
	else:
		# Art not imported yet: readable stand-in so the puzzle stays playable.
		_fallback_panel.visible = true
		_fallback_note.visible = true


## Kept for the breaker's call contract. The Testament is baked into the
## art, so the board is fixed — identical on every peer with no seed.
func setup(_seed_value: int) -> void:
	pass


func _build_board_data() -> void:
	# Insertion order of _mapping mirrors SEQUENCE — callers iterating
	# keys() in order (tests, co-op sync) connect in the legal order.
	for entry in SEQUENCE:
		_mapping[entry[0]] = entry[1]
	_clues.clear()
	var texts := [
		"Reflective mirrors.",
		"Vault door brass knobs.",
		"Inventor's lucky number.",
		"Follow the grand chimes.",
		"Moonlight on crystals.",
		"AVOID the deep gears.",
		"Black: beware the leather spines.",
		"The last, not where the first.",
	]
	for i in SEQUENCE.size():
		_clues.append({
			"type": "placement",
			"wire": SEQUENCE[i][0],
			"port": SEQUENCE[i][1],
			"text": texts[i],
		})


## True when `clue` is consistent with `mapping` — the regression tests run
## every Testament clue through this against the ground truth.
static func clue_holds(clue: Dictionary, mapping: Dictionary) -> bool:
	match clue["type"]:
		"placement":
			return mapping[clue["wire"]] == clue["port"]
		"not":
			return mapping[clue["a"]] != clue["p"]
	return false


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if not is_solved and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
		return
	if event is InputEventMouseMotion and _dragging != "":
		_drag_pos = event.position
		_update_drag_preview()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and not event.pressed and _dragging != "":
		var port := _port_at(event.position)
		var wire := _dragging
		_dragging = ""
		_clear_drag_preview()
		if port >= 0:
			connect_wire(wire, port)


func open() -> void:
	if is_open or is_solved:
		return
	is_open = true
	visible = true
	_selected = ""
	_set_hint()
	add_to_group("modal_ui")
	# Solo pauses the whole tree; in co-op the world must keep running for
	# the partner, so only lock this machine's player input.
	if NetworkSession.multiplayer_active:
		_set_local_lock(true)
	else:
		get_tree().paused = true


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	remove_from_group("modal_ui")
	if not is_solved:
		if NetworkSession.multiplayer_active:
			_set_local_lock(false)
		else:
			get_tree().paused = false
	closed.emit()


func _set_local_lock(locked: bool) -> void:
	for player in get_tree().get_nodes_in_group("players"):
		if player.is_local_player():
			player.ui_locked = locked


## Attempt the next connection. Strict Testament rules: `wire_name` must be
## the sequence's current wire AND `port` its riddled port, otherwise the
## panel shorts and every connection resets. Shared by drags/clicks/tests.
func connect_wire(wire_name: String, port: int) -> void:
	if is_solved or not _mapping.has(wire_name) or port < 0 or port >= WIRES.size():
		return
	if _connections.has(wire_name):
		return  # already locked in place
	var expected: Array = SEQUENCE[_step]
	if wire_name != expected[0] or port != expected[1]:
		_short_circuit(port)
		return
	_connections[wire_name] = port
	_step += 1
	AudioSynthesizer.play_ui("plug", -4.0)
	_spark_at(_port_buttons[port].get_global_rect().get_center())
	_redraw_wires()
	_set_hint()
	if _step >= SEQUENCE.size():
		_complete()


## Wrong wire or wrong port: zap, burn away every cable, back to step 0.
func _short_circuit(port: int) -> void:
	AudioSynthesizer.play_ui("zap", -6.0)
	if port >= 0 and port < _port_buttons.size():
		_spark_at(_port_buttons[port].get_global_rect().get_center())
	for wire_name in _wire_nodes:
		var holder: Node2D = _wire_nodes[wire_name]
		var tween := create_tween()
		tween.tween_property(holder, "modulate:a", 0.0, 0.35)
		tween.tween_callback(holder.queue_free)
	_wire_nodes.clear()
	_connections.clear()
	_step = 0
	_selected = ""
	_set_hint()


func _spark_at(pos: Vector2) -> void:
	_sparks.position = pos
	_sparks.restart()


func _build_hotspots() -> void:
	for i in WIRES.size():
		var wire: Array = WIRES[i]
		var b := _make_hotspot(TERMINAL_POS[i], Vector2(34, 56), wire[1])
		b.tooltip_text = wire[0]
		b.pressed.connect(_on_terminal_pressed.bind(wire[0]))
		b.button_down.connect(_on_terminal_drag_start.bind(wire[0]))
		_hotspots.add_child(b)
		_terminal_buttons[wire[0]] = b
	for i in PORT_POS.size():
		var p := _make_hotspot(PORT_POS[i], Vector2(46, 40), Color(0.85, 0.7, 0.3))
		p.tooltip_text = "Port %d" % (i + 1)
		p.pressed.connect(_on_port_pressed.bind(i))
		var badge := Label.new()
		badge.text = str(i + 1)
		badge.set_anchors_preset(Control.PRESET_FULL_RECT)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 13)
		badge.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
		badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		badge.add_theme_constant_override("outline_size", 4)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(badge)
		_hotspots.add_child(p)
		_port_buttons.append(p)


## Translucent rounded hotspot over the art; border brightens on hover.
func _make_hotspot(center: Vector2, size: Vector2, tint: Color) -> Button:
	var b := Button.new()
	b.position = center - size / 2.0
	b.size = size
	b.focus_mode = Control.FOCUS_NONE
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(tint.r, tint.g, tint.b, 0.10)
	normal.border_color = Color(tint.r, tint.g, tint.b, 0.55)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(tint.r, tint.g, tint.b, 0.25)
	hover.border_color = Color(tint.r, tint.g, tint.b, 1.0)
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(tint.r, tint.g, tint.b, 0.4)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", normal)
	return b


func _on_terminal_drag_start(wire_name: String) -> void:
	if _connections.has(wire_name):
		return  # locked in — the Testament brooks no second thoughts
	_dragging = wire_name
	_selected = wire_name
	_set_hint()


func _on_terminal_pressed(wire_name: String) -> void:
	if _connections.has(wire_name):
		return
	_selected = wire_name
	_set_hint()


func _on_port_pressed(port: int) -> void:
	if _selected.is_empty():
		return
	var wire_name := _selected
	_selected = ""
	connect_wire(wire_name, port)
	_set_hint()


func _port_at(pos: Vector2) -> int:
	for i in _port_buttons.size():
		if _port_buttons[i].get_global_rect().grow(6.0).has_point(pos):
			return i
	return -1


func _set_hint() -> void:
	if is_solved:
		return
	var progress := "%d/%d live" % [_step, SEQUENCE.size()]
	if _selected.is_empty():
		_hint.text = "Follow the Testament's order — one wrong touch shorts the panel. (%s)  [ESC] steps away." % progress
	else:
		_hint.text = "%s lead in hand — drop it on a port. (%s)  [ESC] steps away." % [_selected, progress]


func _wire_color(wire_name: String) -> Array:
	for wire in WIRES:
		if wire[0] == wire_name:
			return [wire[1], wire[2]]
	return [Color.WHITE, null]


## Insulated cable look: dark sheath under the color core (and stripe).
func _make_wire_node(from: Vector2, to: Vector2, wire_name: String) -> Node2D:
	var holder := Node2D.new()
	var pts := _bezier(from, to)
	var colors := _wire_color(wire_name)
	var sheath := Line2D.new()
	sheath.width = 10.0
	sheath.default_color = Color(0.08, 0.07, 0.06)
	sheath.points = pts
	sheath.begin_cap_mode = Line2D.LINE_CAP_ROUND
	sheath.end_cap_mode = Line2D.LINE_CAP_ROUND
	holder.add_child(sheath)
	var line := Line2D.new()
	line.width = 6.5
	line.default_color = colors[0]
	line.points = pts
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	holder.add_child(line)
	if colors[1] != null:
		var stripe := Line2D.new()
		stripe.width = 2.2
		stripe.default_color = colors[1]
		stripe.points = pts
		holder.add_child(stripe)
	return holder


## Sagging quadratic bezier: wires flex like real cable.
func _bezier(a: Vector2, b: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var sag := 28.0 + a.distance_to(b) * 0.18
	var ctrl := (a + b) * 0.5 + Vector2(0, sag)
	for i in 25:
		var t := float(i) / 24.0
		pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	return pts


func _redraw_wires() -> void:
	for wire_name in _wire_nodes:
		_wire_nodes[wire_name].queue_free()
	_wire_nodes.clear()
	for wire_name in _connections:
		var from: Vector2 = _terminal_buttons[wire_name].get_global_rect().get_center()
		var to: Vector2 = _port_buttons[_connections[wire_name]].get_global_rect().get_center()
		var node := _make_wire_node(from, to, wire_name)
		_wire_layer.add_child(node)
		_wire_nodes[wire_name] = node


func _update_drag_preview() -> void:
	if _dragging.is_empty():
		_clear_drag_preview()
		return
	var from: Vector2 = _terminal_buttons[_dragging].get_global_rect().get_center()
	# Reuse the preview node across mouse-motion events (they arrive at
	# hundreds per second while dragging) — only the points change.
	if _drag_node == null:
		_drag_node = _make_wire_node(from, _drag_pos, _dragging)
		_wire_layer.add_child(_drag_node)
	else:
		var pts := _bezier(from, _drag_pos)
		for child in _drag_node.get_children():
			(child as Line2D).points = pts


func _clear_drag_preview() -> void:
	if _drag_node:
		_drag_node.queue_free()
		_drag_node = null


func _complete() -> void:
	is_solved = true
	_hint.text = "Circuit complete — the mansion hums back to life!"
	_spark_at(_board.get_global_rect().get_center())
	AudioSynthesizer.play_ui("power_up", -6.0)
	var timer := get_tree().create_timer(0.9, true)
	timer.timeout.connect(func() -> void:
		if NetworkSession.multiplayer_active:
			_set_local_lock(false)
		else:
			get_tree().paused = false
		close()
		solved.emit())
