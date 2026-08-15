class_name PressurePanel
extends CanvasLayer

## Fullscreen first-person control face for the hydraulic press — the
## same modal contract as the breaker's FusePanel: [E] on the press opens
## it (local machine only), solo pauses the tree, co-op locks just this
## player's input, [ESC] or ✕ steps away. Everything is manipulated by
## clicking: hex fittings (wrench-gated, sequenced) and five valve wheels
## feeding the big PSI dial. Clicks route through the press manager's
## replicated request_* calls, so co-op peers see identical state; this
## overlay is purely the local view + feedback layer.

signal closed

const COLOR_LOOSE := Color(1.0, 0.72, 0.25)
const COLOR_TIGHT := Color(0.45, 0.85, 0.5)
const COLOR_SEALED := Color(0.45, 0.45, 0.5)
const COLOR_ON := Color(0.3, 1.0, 0.75)
const COLOR_OFF := Color(0.5, 0.38, 0.22)

var is_open := false

## PressurePuzzleManager (duck-typed to avoid a scene<->script preload cycle).
var _machine: Node

var _gauge: Control
var _small_buttons: Array[Button] = []
var _big_buttons: Array[Button] = []
var _valve_wheels: Array[Button] = []
var _valve_lamps: Array[ColorRect] = []
## Animated wheel angles ease toward 0 / TAU as valves shut / open.
var _valve_spin: Array[float] = []
var _shown_psi := 0.0
var _pulse_time := 0.0
var _hint_flash := 0.0

@onready var _board: Control = $Overlay/Board
@onready var _hint: Label = $Overlay/Hint


func _ready() -> void:
	visible = false
	$Overlay/Board/CloseButton.pressed.connect(close)


## Called by the press manager right after instancing; builds the face.
func setup(machine: Node) -> void:
	_machine = machine
	_shown_psi = float(machine.base_psi)
	for i in machine.valve_pressures.size():
		_valve_spin.append(0.0)
	_build_face()
	machine.state_changed.connect(_refresh)
	machine.phase_changed.connect(func(_p: int) -> void: _refresh())
	machine.puzzle_solved.connect(_on_solved)
	_refresh()


func _process(delta: float) -> void:
	if not is_open:
		return
	_pulse_time += delta
	_hint_flash = maxf(0.0, _hint_flash - delta * 2.0)
	_hint.modulate = Color.WHITE.lerp(Color(1.0, 0.4, 0.35), _hint_flash)
	# Loose fittings breathe so the current chore reads at a glance.
	for i in _small_buttons.size():
		_pulse_fitting(_small_buttons[i], not _machine.small_tight[i],
			_machine.phase == _machine.Phase.SMALL_FITTINGS)
	for i in _big_buttons.size():
		_pulse_fitting(_big_buttons[i], not _machine.big_tight[i],
			_machine.phase == _machine.Phase.BIG_FITTINGS)
	# Wheels ease toward their toggled orientation; the dial needle chases
	# the live PSI.
	for i in _valve_wheels.size():
		var target := TAU if _machine.valve_on[i] else 0.0
		if absf(_valve_spin[i] - target) > 0.001:
			_valve_spin[i] = lerpf(_valve_spin[i], target, 1.0 - exp(-9.0 * delta))
			_valve_wheels[i].queue_redraw()
	var psi_target := float(_machine.current_psi)
	if absf(_shown_psi - psi_target) > 0.01:
		_shown_psi = lerpf(_shown_psi, psi_target, 1.0 - exp(-8.0 * delta))
		_gauge.queue_redraw()


func _pulse_fitting(btn: Button, loose: bool, active_phase: bool) -> void:
	if loose and active_phase:
		btn.modulate.a = 0.65 + 0.35 * (0.5 + 0.5 * sin(_pulse_time * 3.0))
	else:
		btn.modulate.a = 1.0


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


func _on_fitting_clicked(big: bool, index: int) -> void:
	var local := _local_player()
	if local == null:
		return
	var tight: bool = _machine.big_tight[index] if big else _machine.small_tight[index]
	if tight or _machine.solved:
		return
	var phase_ok: bool = (_machine.phase == _machine.Phase.BIG_FITTINGS) if big \
		else (_machine.phase == _machine.Phase.SMALL_FITTINGS)
	if not phase_ok:
		_error_hint("Sealed — tighten the small fittings first." if big
			else "That fitting is already handled.")
		AudioSynthesizer.play_ui("tick", -14.0, 0.55)
		return
	var group := "big_wrenches" if big else "small_wrenches"
	if local.inventory_find(group) == null:
		var wrench_name := "Brass Wrench" if big else "Small Wrench"
		if local.inventory_find("wrenches") != null:
			_error_hint("Wrong wrench — this fitting wants the %s." % wrench_name)
			AudioSynthesizer.play_ui("zap", -16.0, 0.8)
		else:
			_error_hint("You need the %s in your pack." % wrench_name)
			AudioSynthesizer.play_ui("tick", -14.0, 0.8)
		# Still route the attempt: the manager owns the authoritative
		# validation and the wrong_item_used event.
		_machine.request_tighten(local, big, index)
		return
	AudioSynthesizer.play_ui("ratchet", -6.0)
	_machine.request_tighten(local, big, index)


func _on_valve_clicked(index: int) -> void:
	var local := _local_player()
	if local == null:
		return
	if _machine.solved:
		return
	if _machine.phase != _machine.Phase.VALVES:
		_error_hint("The manifold is sealed until every fitting is torqued.")
		AudioSynthesizer.play_ui("tick", -14.0, 0.55)
		return
	AudioSynthesizer.play_ui("ratchet", -8.0)
	_machine.request_toggle_valve(local, index)


func _error_hint(text: String) -> void:
	_hint.text = text + "  [ESC] steps away."
	_hint_flash = 1.0


# --- State -> visuals ----------------------------------------------------


func _refresh() -> void:
	for i in _small_buttons.size():
		_small_buttons[i].queue_redraw()
	for i in _big_buttons.size():
		_big_buttons[i].queue_redraw()
	for i in _valve_wheels.size():
		var on: bool = _machine.valve_on[i]
		_valve_lamps[i].color = COLOR_ON if on else COLOR_OFF
		_valve_wheels[i].queue_redraw()
	_gauge.queue_redraw()
	if _machine.solved:
		_hint.text = "PRESSURE BALANCED — the vault gate vents open!"
		_hint.modulate = Color(0.55, 1.0, 0.65)
		return
	var ph: int = _machine.phase
	if ph == _machine.Phase.SMALL_FITTINGS:
		_hint.text = "Leaks everywhere: tighten the SMALL fittings (Small Wrench).  [ESC] steps away."
	elif ph == _machine.Phase.BIG_FITTINGS:
		_hint.text = "Now torque the MAIN fittings (Brass Wrench).  [ESC] steps away."
	elif ph == _machine.Phase.VALVES:
		_hint.text = "Open valves so the dial lands exactly on the red target mark.  [ESC] steps away."


func _on_solved() -> void:
	_refresh()
	if not is_open:
		return
	AudioSynthesizer.play_ui("chime", -8.0)
	# Let the green dial sink in, then step the player back into the world
	# (the timer ticks through the solo pause).
	await get_tree().create_timer(1.6, true).timeout
	close()


# --- Face construction ---------------------------------------------------


func _build_face() -> void:
	# Steel face plate behind everything.
	var plate := Panel.new()
	var plate_style := StyleBoxFlat.new()
	plate_style.bg_color = Color(0.14, 0.15, 0.18)
	plate_style.border_color = Color(0.5, 0.42, 0.28)
	plate_style.set_border_width_all(3)
	plate_style.set_corner_radius_all(10)
	plate.add_theme_stylebox_override("panel", plate_style)
	plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(plate)
	_board.move_child(plate, 0)

	var title := Label.new()
	title.text = "HYDRAULIC PRESS — PRESSURE CONTROL"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.78, 0.5))
	title.position = Vector2(0, 14)
	title.size = Vector2(900, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_board.add_child(title)

	_gauge = Control.new()
	_gauge.position = Vector2(300, 44)
	_gauge.size = Vector2(300, 176)
	_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge.draw.connect(_draw_gauge)
	_board.add_child(_gauge)

	# Five valve columns under the dial.
	var pressures: Array = _machine.valve_pressures
	for i in pressures.size():
		var col_x := 150.0 + 120.0 * i
		var value := Label.new()
		value.text = "%+d" % pressures[i]
		value.add_theme_font_size_override("font_size", 20)
		value.add_theme_color_override("font_color",
			Color(0.4, 0.9, 1.0) if int(pressures[i]) >= 0 else Color(1.0, 0.5, 0.4))
		value.position = Vector2(col_x, 232)
		value.size = Vector2(120, 24)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_board.add_child(value)

		var wheel := _flat_button(Vector2(col_x + 23, 260), Vector2(74, 74))
		wheel.draw.connect(_draw_wheel.bind(wheel, i))
		wheel.pressed.connect(_on_valve_clicked.bind(i))
		_board.add_child(wheel)
		_valve_wheels.append(wheel)

		var lamp := ColorRect.new()
		lamp.color = COLOR_OFF
		lamp.position = Vector2(col_x + 52, 344)
		lamp.size = Vector2(16, 10)
		lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_board.add_child(lamp)
		_valve_lamps.append(lamp)

	# Fitting groups along the bottom: small feed line left, mains right.
	_add_group_label("FEED FITTINGS — SMALL WRENCH", Vector2(60, 386), 340)
	var small_count: int = _machine.small_tight.size()
	for i in small_count:
		var btn := _flat_button(Vector2(110.0 + 90.0 * i, 414), Vector2(64, 64))
		btn.draw.connect(_draw_fitting.bind(btn, false, i))
		btn.pressed.connect(_on_fitting_clicked.bind(false, i))
		_board.add_child(btn)
		_small_buttons.append(btn)

	_add_group_label("MAIN FITTINGS — BRASS WRENCH", Vector2(500, 386), 340)
	var big_count: int = _machine.big_tight.size()
	for i in big_count:
		var btn := _flat_button(Vector2(560.0 + 110.0 * i, 406), Vector2(80, 80))
		btn.draw.connect(_draw_fitting.bind(btn, true, i))
		btn.pressed.connect(_on_fitting_clicked.bind(true, i))
		_board.add_child(btn)
		_big_buttons.append(btn)


func _add_group_label(text: String, at: Vector2, width: float) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5))
	label.position = at
	label.size = Vector2(width, 20)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_board.add_child(label)


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


func _draw_gauge() -> void:
	var c := Vector2(150, 128)
	var radius := 100.0
	var font := ThemeDB.fallback_font
	_gauge.draw_circle(c, radius + 14, Color(0.08, 0.09, 0.11))
	_gauge.draw_arc(c, radius + 13, 0, TAU, 64, Color(0.5, 0.42, 0.28), 2.5)
	var lo: int = _machine.gauge_min()
	var hi: int = _machine.gauge_max()
	# Dial sweep: 215 deg (left) over the top to -35 deg (right).
	_gauge.draw_arc(c, radius, deg_to_rad(-215.0), deg_to_rad(35.0), 48,
		Color(0.75, 0.7, 0.6), 2.0)
	for k in 11:
		var t := float(k) / 10.0
		var a := _dial_angle(t)
		var dir := Vector2(cos(a), sin(a))
		_gauge.draw_line(c + dir * (radius - 8), c + dir * radius, Color(0.75, 0.7, 0.6), 2.0)
	# Fixed red target tick + label.
	var target_t := _dial_t(float(_machine.target_psi), lo, hi)
	var ta := _dial_angle(target_t)
	var tdir := Vector2(cos(ta), sin(ta))
	_gauge.draw_line(c + tdir * (radius - 16), c + tdir * (radius + 8), Color(0.9, 0.15, 0.12), 4.0)
	# Needle chasing the live pressure.
	var na := _dial_angle(_dial_t(_shown_psi, lo, hi))
	var ndir := Vector2(cos(na), sin(na))
	var needle_color := Color(0.55, 1.0, 0.65) if _machine.solved else Color(0.92, 0.9, 0.85)
	_gauge.draw_line(c, c + ndir * (radius - 14), needle_color, 3.5)
	_gauge.draw_circle(c, 6.0, Color(0.5, 0.42, 0.28))
	# Readout.
	var psi_text := "%+d PSI" % _machine.current_psi
	_gauge.draw_string(font, c + Vector2(-70, 44), psi_text,
		HORIZONTAL_ALIGNMENT_CENTER, 140, 24, needle_color)
	_gauge.draw_string(font, c + Vector2(-70, 64), "TARGET %+d" % _machine.target_psi,
		HORIZONTAL_ALIGNMENT_CENTER, 140, 15, Color(1.0, 0.45, 0.4))
	_gauge.draw_string(font, c + Vector2(-70, -30), "%d" % lo,
		HORIZONTAL_ALIGNMENT_LEFT, 140, 12, Color(0.6, 0.58, 0.52))
	_gauge.draw_string(font, c + Vector2(10, -30), "%d" % hi,
		HORIZONTAL_ALIGNMENT_RIGHT, 60, 12, Color(0.6, 0.58, 0.52))


func _dial_t(psi: float, lo: int, hi: int) -> float:
	if hi <= lo:
		return 0.5
	return clampf(inverse_lerp(float(lo), float(hi), psi), 0.0, 1.0)


func _dial_angle(t: float) -> float:
	return deg_to_rad(lerpf(-215.0, 35.0, t))


func _draw_wheel(btn: Button, index: int) -> void:
	var c := btn.size / 2.0
	var r := 32.0
	var on: bool = _machine.valve_on[index]
	var live: bool = _machine.phase == _machine.Phase.VALVES and not _machine.solved
	var rim := (COLOR_ON if on else Color(0.72, 0.55, 0.25)) if live else COLOR_SEALED
	btn.draw_arc(c, r, 0, TAU, 40, rim, 5.0)
	var spin: float = _valve_spin[index] * 0.5  # half-turn reads clearly
	for k in 4:
		var a := spin + TAU * float(k) / 4.0
		btn.draw_line(c, c + Vector2(cos(a), sin(a)) * (r - 3.0), rim, 3.0)
	btn.draw_circle(c, 7.0, rim)


func _draw_fitting(btn: Button, big: bool, index: int) -> void:
	var tight: bool = _machine.big_tight[index] if big else _machine.small_tight[index]
	var active: bool = (_machine.phase == _machine.Phase.BIG_FITTINGS) if big \
		else (_machine.phase == _machine.Phase.SMALL_FITTINGS)
	var c := btn.size / 2.0
	var r: float = 26.0 if big else 21.0
	var color := COLOR_TIGHT if tight else (COLOR_LOOSE if active else COLOR_SEALED)
	# Hex nut, rotated 30 degrees once seated so the change reads visually.
	var points := PackedVector2Array()
	var rot := PI / 6.0 if tight else 0.0
	for k in 6:
		var a := rot + TAU * float(k) / 6.0
		points.append(c + Vector2(cos(a), sin(a)) * r)
	btn.draw_colored_polygon(points, Color(color.r, color.g, color.b, 0.25))
	for k in 6:
		btn.draw_line(points[k], points[(k + 1) % 6], color, 3.0)
	btn.draw_circle(c, r * 0.32, color)
	if not tight and active:
		# Fluid weep: little drops under the loose nut.
		var drop_y := fmod(_pulse_time * 26.0 + index * 11.0, 16.0)
		btn.draw_circle(c + Vector2(r * 0.5, r + 2.0 + drop_y), 2.5, Color(0.85, 0.6, 0.2, 0.7))
