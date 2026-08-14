class_name WiringMinigame
extends CanvasLayer

## Tactile 8-wire fuse panel. Wires (solid and striped variants) plug into
## 8 brass prongs; connections render as sagging bezier curves that can be
## dragged from terminal to prong or placed click-to-click. Instead of a
## 1:1 legend, a charred journal scrap gives logic constraints; the last
## ambiguous wires are deduced from live-current feedback ("(live)" on a
## correctly-wired prong, with a spark). [ESC] steps away (consumed in
## _input so the pause menu never sees it). Solving powers the mansion.

signal solved
signal closed

## name, main color, stripe color (null = solid)
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

var is_open := false
var is_solved := false

## Ground truth: wire name -> port index (0-based). Randomized once.
var _mapping := {}
## Generated deduction clues; every clue must hold under _mapping.
var _clues: Array = []
var _connections := {}
var _selected := ""
var _dragging := ""
var _drag_pos := Vector2.ZERO
var _terminal_buttons := {}
var _port_buttons: Array[Button] = []
var _wire_nodes := {}
var _drag_node: Node2D

@onready var _terminals_box: VBoxContainer = $Overlay/PanelBg/Terminals
@onready var _ports_box: VBoxContainer = $Overlay/PanelBg/Ports
@onready var _schematic: Label = $Overlay/PanelBg/SchematicCard/Schematic
@onready var _hint: Label = $Overlay/PanelBg/Hint
@onready var _wire_layer: Control = $Overlay/WireLayer
@onready var _sparks: CPUParticles2D = $Overlay/Sparks
@onready var _panel: Control = $Overlay/PanelBg


func _ready() -> void:
	visible = false
	_build_buttons()


## Build the board from a seed (0 = random). Called by the owning breaker;
## in co-op the seed derives from the shared run seed on every peer.
func setup(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	_randomize_board(rng)


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


## Wire a color to a port (0-based). Shared by drags, clicks, and tests.
func connect_wire(wire_name: String, port: int) -> void:
	if is_solved or not _mapping.has(wire_name) or port < 0 or port >= WIRES.size():
		return
	for other in _connections.keys():
		if other != wire_name and _connections[other] == port:
			_connections.erase(other)
	_connections[wire_name] = port
	AudioSynthesizer.play_ui("plug", -4.0)
	if _port_buttons.size() > port:
		_sparks.position = _port_buttons[port].get_global_rect().get_center()
		_sparks.restart()
	_redraw_wires()
	_check_solved()


## True when `clue` is consistent with `mapping` — the regression tests run
## every generated clue through this against the ground truth.
static func clue_holds(clue: Dictionary, mapping: Dictionary) -> bool:
	match clue["type"]:
		"direct":
			return mapping[clue["a"]] == clue["p"]
		"parity":
			return (int(mapping[clue["a"]] + 1) % 2 == 0) == clue["even"]
		"above":
			return mapping[clue["b"]] - mapping[clue["a"]] == clue["k"]
		"not":
			return mapping[clue["a"]] != clue["p"]
	return false


func _randomize_board(rng: RandomNumberGenerator) -> void:
	var ports := range(WIRES.size())
	for i in range(ports.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: int = ports[i]
		ports[i] = ports[j]
		ports[j] = tmp
	for i in WIRES.size():
		_mapping[WIRES[i][0]] = ports[i]
	_generate_clues(rng)


## Constraint clues covering six wires; the last two only get negative
## hints, leaving genuine deduction plus live-spark trial for the finish.
func _generate_clues(rng: RandomNumberGenerator) -> void:
	_clues.clear()
	var names: Array = _mapping.keys()
	for i in range(names.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = names[i]
		names[i] = names[j]
		names[j] = tmp

	_clues.append({"type": "direct", "a": names[0], "p": _mapping[names[0]],
		"text": "...the %s lead is soldered fast to prong %d..." % [names[0], _mapping[names[0]] + 1]})
	for i in [1, 2]:
		var even := int(_mapping[names[i]] + 1) % 2 == 0
		_clues.append({"type": "parity", "a": names[i], "even": even,
			"text": "...%s must ground to an %s prong..." % [names[i], "EVEN" if even else "ODD"]})
	for pair in [[names[3], names[0]], [names[4], names[1]], [names[5], names[3]]]:
		var a: String = pair[0]
		var b: String = pair[1]
		if _mapping[a] > _mapping[b]:
			var swap := a
			a = b
			b = swap
		_clues.append({"type": "above", "a": a, "b": b, "k": _mapping[b] - _mapping[a],
			"text": "...%s runs exactly %d pin%s above %s..." % [a, _mapping[b] - _mapping[a],
				"" if _mapping[b] - _mapping[a] == 1 else "s", b]})
	for i in [6, 7]:
		var wrong: int = (_mapping[names[i]] + 2 + rng.randi_range(0, 3)) % WIRES.size()
		_clues.append({"type": "not", "a": names[i], "p": wrong,
			"text": "...never bridge %s to prong %d — it arcs..." % [names[i], wrong + 1]})

	var lines: Array[String] = ["~ charred journal scrap ~", ""]
	for clue in _clues:
		lines.append(clue["text"])
	lines.append("")
	lines.append("...the rest burned away.")
	lines.append("Trust the live sparks.")
	_schematic.text = "\n".join(lines)


func _build_buttons() -> void:
	for wire in WIRES:
		var b := Button.new()
		b.text = wire[0]
		b.custom_minimum_size = Vector2(140, 40)
		b.modulate = wire[1]
		b.pressed.connect(_on_terminal_pressed.bind(wire[0]))
		b.button_down.connect(_on_terminal_drag_start.bind(wire[0]))
		_terminals_box.add_child(b)
		_terminal_buttons[wire[0]] = b
	for i in WIRES.size():
		var p := Button.new()
		p.text = "Port %d" % (i + 1)
		p.custom_minimum_size = Vector2(140, 40)
		p.pressed.connect(_on_port_pressed.bind(i))
		_ports_box.add_child(p)
		_port_buttons.append(p)


func _on_terminal_drag_start(wire_name: String) -> void:
	_dragging = wire_name
	_selected = wire_name
	if _connections.has(wire_name):
		_connections.erase(wire_name)
		_redraw_wires()
	_set_hint()


func _on_terminal_pressed(wire_name: String) -> void:
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
	if _selected.is_empty():
		_hint.text = "Drag a wire to a prong (or click wire, then prong). [ESC] steps away."
	else:
		_hint.text = "%s wire in hand — drop it on a prong. [ESC] steps away." % _selected


func _wire_color(wire_name: String) -> Array:
	for wire in WIRES:
		if wire[0] == wire_name:
			return [wire[1], wire[2]]
	return [Color.WHITE, null]


func _make_wire_node(from: Vector2, to: Vector2, wire_name: String) -> Node2D:
	var holder := Node2D.new()
	var pts := _bezier(from, to)
	var colors := _wire_color(wire_name)
	var line := Line2D.new()
	line.width = 7.0
	line.default_color = colors[0]
	line.points = pts
	holder.add_child(line)
	if colors[1] != null:
		var stripe := Line2D.new()
		stripe.width = 2.5
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
	# Live-current feedback: a correctly-fed prong hums.
	for i in _port_buttons.size():
		var live := false
		for wire_name in _connections:
			if _connections[wire_name] == i and _mapping[wire_name] == i:
				live = true
		_port_buttons[i].text = "Port %d%s" % [i + 1, "  (live)" if live else ""]


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


func _check_solved() -> void:
	if _connections.size() < WIRES.size():
		return
	for wire_name in _connections:
		if _connections[wire_name] != _mapping[wire_name]:
			return
	_complete()


func _complete() -> void:
	is_solved = true
	_hint.text = "Circuit complete — power restored!"
	_sparks.position = _panel.get_global_rect().get_center()
	_sparks.restart()
	AudioSynthesizer.play_ui("chime", -4.0)
	var timer := get_tree().create_timer(0.7, true)
	timer.timeout.connect(func() -> void:
		if NetworkSession.multiplayer_active:
			_set_local_lock(false)
		else:
			get_tree().paused = false
		close()
		solved.emit())
