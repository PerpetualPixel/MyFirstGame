class_name PuzzleBox
extends Interactable

## Antique astronomical puzzle box against a room wall: an arched dial
## window (sun/moon/star motif) over a lever and three reel windows,
## styled after a mechanical combination lock. Replaces the old
## grandfather clock as the Brass Wrench's hiding place.
##
## The control logic mirrors a real dial-and-lever combination lock:
## click one of four symbol tiles to guess the CURRENT slot, then pull
## the lever to commit it and advance the mechanism. Every click is
## validated immediately against the secret sequence (engraved on the
## case, shuffled per run) — a wrong symbol, or touching the dial while
## the mechanism is still advancing from the last pull, resets the
## whole attempt back to the first slot. No permanent penalty: is_locked
## stays true until solved, so a player can retry forever.
##
## Signal names and the register_*/validate state machine follow the
## brief exactly (PuzzleBoxController): dial input and advance input
## each append to a single buffer and are validated per-step; a cadence
## timer gates input right after every lever pull.

signal input_registered(symbol_name: String)
signal advance_clicked
signal sequence_failed
signal puzzle_unlocked

## Four faces on the dial; the target sequence draws from these.
const SYMBOLS := ["sun", "moon", "star", "sparkle"]
const ADVANCE_SYMBOL := "ADVANCE"
const SYMBOL_LABELS := {"sun": "Sun", "moon": "Moon", "star": "Star", "sparkle": "Sparkle"}
## Distinct symbol glyphs (☉ ☾ ✦ ✧-style), one Roman-numeral-equivalent
## the case engraves so the sequence can be read, not guessed blind.
const SYMBOL_GLYPHS := {"sun": "☉", "moon": "☾", "star": "★", "sparkle": "✦"}

@export var sequence_length: int = 3
## Mechanical advance delay: touching the dial before the gears finish
## settling from the last lever pull fails the whole attempt.
@export var cadence_window_sec: float = 0.7

## Built at _ready(): [s0, ADVANCE, s1, ADVANCE, s2, ADVANCE].
var active_target_sequence: Array = []
var current_input_buffer: Array = []
var is_locked := true
var is_waiting_for_cadence := false

var minigame: CanvasLayer

var _stashed: Node3D
var _cadence_timer: Timer
var _lever_pivot: Node3D
var _compartment: Node3D
var _reel_labels: Array[Label3D] = []


func _ready() -> void:
	add_to_group("puzzle_boxes")
	# The panel's own ESC handler lives on THIS node (see _input below);
	# solo pauses the whole tree, so this node needs to keep receiving
	# input while paused or its own close button becomes the only way out.
	process_mode = Node.PROCESS_MODE_ALWAYS
	display_name = "Puzzle Box"
	prompt_action = "Inspect Puzzle Box"
	prompt_height = 2.1
	_initialize_combination()
	_cadence_timer = Timer.new()
	_cadence_timer.one_shot = true
	_cadence_timer.timeout.connect(_on_cadence_timer_timeout)
	add_child(_cadence_timer)
	_build_case()
	_build_panel()


## RE-style: [E] always inspects; the dial and lever are worked from
## inside the overlay. It only opens on the interacting machine.
func interact(by: Node3D) -> void:
	if by == null or not by.has_method("is_local_player") or by.is_local_player():
		_open_panel()
	super.interact(by)


## Park an item (frozen, collision off) inside the lower cabinet until
## the box unlocks. Call before the item is added anywhere else.
func stash_item(item: Node3D) -> void:
	_stashed = item
	item.set("freeze", true)
	item.set("collision_layer", 0)
	item.set("collision_mask", 0)
	add_child(item)
	item.position = Vector3(0, 0.55, 0.1)


func _initialize_combination() -> void:
	var pool := SYMBOLS.duplicate()
	for i in range(pool.size() - 1, 0, -1):
		var j := randi() % (i + 1)
		var tmp: String = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	active_target_sequence.clear()
	for i in sequence_length:
		active_target_sequence.append(pool[i])
		active_target_sequence.append(ADVANCE_SYMBOL)


# --- Controller state machine (mirrors the provided brief) ---------------


func register_dial_input(symbol: String) -> void:
	if not is_locked:
		return
	if is_waiting_for_cadence:
		# Touching the dial during the mechanical advance pause fails it.
		_trigger_failure()
		return
	current_input_buffer.append(symbol)
	input_registered.emit(symbol)
	_validate_current_step()


func register_advance_input() -> void:
	if not is_locked or is_waiting_for_cadence:
		return
	current_input_buffer.append(ADVANCE_SYMBOL)
	advance_clicked.emit()
	is_waiting_for_cadence = true
	_cadence_timer.start(cadence_window_sec)
	AudioSynthesizer.play_at("ratchet", global_position, -4.0, 0.7)
	_validate_current_step()


func _validate_current_step() -> void:
	var current_index := current_input_buffer.size() - 1
	if current_index >= active_target_sequence.size() \
			or current_input_buffer[current_index] != active_target_sequence[current_index]:
		_trigger_failure()
		return
	if current_input_buffer.size() == active_target_sequence.size():
		_unlock()


func _on_cadence_timer_timeout() -> void:
	is_waiting_for_cadence = false


func _unlock() -> void:
	is_locked = false
	puzzle_unlocked.emit()
	_play_unlock()


func _trigger_failure() -> void:
	current_input_buffer.clear()
	is_waiting_for_cadence = false
	_cadence_timer.stop()
	sequence_failed.emit()
	_play_failure()


func reset_puzzle() -> void:
	current_input_buffer.clear()
	is_waiting_for_cadence = false
	is_locked = true


# --- Replicated entry points (called by the panel overlay) ---------------


func request_dial_input(by: Node3D, symbol: String) -> void:
	if NetworkSession.multiplayer_active:
		_net_dial_input.rpc(symbol)
	else:
		register_dial_input(symbol)


@rpc("any_peer", "call_local", "reliable")
func _net_dial_input(symbol: String) -> void:
	register_dial_input(symbol)


func request_advance_input(by: Node3D) -> void:
	if NetworkSession.multiplayer_active:
		_net_advance_input.rpc()
	else:
		register_advance_input()


@rpc("any_peer", "call_local", "reliable")
func _net_advance_input() -> void:
	register_advance_input()


# --- World model + physical feedback --------------------------------------


func _play_failure() -> void:
	AudioSynthesizer.play_at("zap", global_position, -10.0, 1.1)
	Player.shake(0.15, global_position)
	var tween := create_tween()
	for i in 3:
		tween.tween_property(self, "rotation:z", deg_to_rad(2.5), 0.04)
		tween.tween_property(self, "rotation:z", deg_to_rad(-2.5), 0.08)
	tween.tween_property(self, "rotation:z", 0.0, 0.04)
	for label in _reel_labels:
		label.text = "·"


func _play_unlock() -> void:
	AudioSynthesizer.play_at("chime", global_position, -2.0, 1.0)
	var tween := create_tween()
	if _lever_pivot:
		tween.tween_property(_lever_pivot, "rotation:x", deg_to_rad(-35.0), 0.4)
	tween.tween_property(_compartment, "position:y", _compartment.position.y - 0.4, 0.7).set_delay(0.3)
	tween.tween_callback(_release_stash)


func _release_stash() -> void:
	if _stashed == null:
		return
	var item := _stashed
	_stashed = null
	item.reparent(get_parent())
	# Out the FRONT of the case, onto the floor before the box — the case
	# stands against a wall, so the rear is solid masonry.
	item.global_position = global_position + global_transform.basis.z * 0.9 + Vector3(0, 0.5, 0)
	item.set("freeze", false)
	item.set("collision_layer", 1)
	item.set("collision_mask", 1)


## Live reel readout: called by the panel whenever the buffer changes, so
## the case's own windows track the confirmed slots too.
func refresh_reels() -> void:
	var confirmed := current_input_buffer.size() / 2  # completed [symbol,ADVANCE] pairs
	for i in _reel_labels.size():
		if i < confirmed:
			var sym: String = active_target_sequence[i * 2]
			_reel_labels[i].text = SYMBOL_GLYPHS[sym]
		else:
			_reel_labels[i].text = "·"


func _build_case() -> void:
	var wood := _mat(Color(0.32, 0.18, 0.1), 0.0, 0.6)
	var wood_dark := _mat(Color(0.16, 0.09, 0.05), 0.0, 0.7)
	var brass := _mat(Color(0.72, 0.55, 0.25), 0.75, 0.35)
	var navy := _mat(Color(0.08, 0.1, 0.2), 0.1, 0.5)
	var gold_glow := _glow_mat(Color(0.95, 0.8, 0.4), 1.2)

	# Plinth and body.
	_box(Vector3(0, 0.15, 0), Vector3(1.3, 0.3, 0.55), wood_dark)
	_box(Vector3(0, 1.0, 0), Vector3(1.15, 1.5, 0.5), wood)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.3, 2.1, 0.55)
	col.shape = shape
	col.position = Vector3(0, 1.1, 0)
	add_child(col)

	# Arched astronomy window: navy backdrop behind a brass arch frame.
	var arch_center := Vector3(0, 2.15, 0.27)
	_box(arch_center, Vector3(1.05, 0.55, 0.06), navy)
	var arch_top := MeshInstance3D.new()
	var arch_mesh := CylinderMesh.new()
	arch_mesh.top_radius = 0.0
	arch_mesh.bottom_radius = 0.52
	arch_mesh.height = 0.06
	arch_mesh.radial_segments = 24
	arch_mesh.material = navy
	arch_top.mesh = arch_mesh
	arch_top.rotation.x = -PI / 2.0
	arch_top.position = arch_center + Vector3(0, 0.275, 0)
	arch_top.scale = Vector3(1, 1, 0.5)
	add_child(arch_top)
	# Tiny brass star flecks and a crescent scattered on the backdrop.
	for pt in [Vector2(-0.32, 0.1), Vector2(-0.1, 0.22), Vector2(0.28, 0.15), Vector2(0.12, -0.05)]:
		var star := MeshInstance3D.new()
		var star_mesh := SphereMesh.new()
		star_mesh.radius = 0.015
		star_mesh.height = 0.03
		star_mesh.material = gold_glow
		star.mesh = star_mesh
		star.position = arch_center + Vector3(pt.x, pt.y, -0.01)
		add_child(star)
	var crescent := MeshInstance3D.new()
	var crescent_mesh := TorusMesh.new()
	crescent_mesh.inner_radius = 0.09
	crescent_mesh.outer_radius = 0.13
	crescent_mesh.material = gold_glow
	crescent.mesh = crescent_mesh
	crescent.rotation.x = PI / 2.0
	crescent.position = arch_center + Vector3(-0.02, -0.05, -0.01)
	add_child(crescent)
	# Arch frame trim.
	_box(arch_center + Vector3(0, -0.28, 0.005), Vector3(1.1, 0.05, 0.07), brass)
	_box(arch_center + Vector3(-0.53, 0, 0.005), Vector3(0.05, 0.55, 0.07), brass)
	_box(arch_center + Vector3(0.53, 0, 0.005), Vector3(0.05, 0.55, 0.07), brass)

	# Fascia strip below the window: 4 decorative symbol tiles (matches
	# the panel's interactive set, purely cosmetic on the case itself).
	var fascia_y := 1.62
	_box(Vector3(0, fascia_y, 0.27), Vector3(1.1, 0.34, 0.05), brass)
	for i in 4:
		var tx := -0.4 + i * 0.267
		_box(Vector3(tx, fascia_y, 0.31), Vector3(0.2, 0.2, 0.02), wood_dark)
	# Large decorative lever on the case's left side.
	_lever_pivot = Node3D.new()
	_lever_pivot.position = Vector3(-0.68, 1.55, 0.15)
	add_child(_lever_pivot)
	_cyl(_lever_pivot, Vector3(0, -0.28, 0), 0.03, 0.5, brass)
	var knob := MeshInstance3D.new()
	var knob_mesh := SphereMesh.new()
	knob_mesh.radius = 0.07
	knob_mesh.height = 0.14
	knob_mesh.material = brass
	knob.mesh = knob_mesh
	knob.position = Vector3(0, -0.54, 0)
	_lever_pivot.add_child(knob)

	# Lower cabinet: 3 reel windows (readout of confirmed slots) and the
	# wrench compartment behind a sliding rosette door.
	_box(Vector3(0, 0.85, 0.27), Vector3(0.85, 0.22, 0.03), wood_dark)
	for i in sequence_length:
		var rx := -0.26 + i * 0.26
		var window_bg := MeshInstance3D.new()
		var window_mesh := BoxMesh.new()
		window_mesh.size = Vector3(0.18, 0.18, 0.02)
		window_mesh.material = wood_dark
		window_bg.mesh = window_mesh
		window_bg.position = Vector3(rx, 0.85, 0.29)
		add_child(window_bg)
		var label := Label3D.new()
		label.text = "·"
		label.font_size = 44
		label.pixel_size = 0.004
		label.modulate = Color(0.85, 0.68, 0.3)
		label.position = Vector3(rx, 0.85, 0.31)
		add_child(label)
		_reel_labels.append(label)

	_compartment = Node3D.new()
	_compartment.position = Vector3(0, 0.5, 0.27)
	add_child(_compartment)
	var door := MeshInstance3D.new()
	var door_mesh := BoxMesh.new()
	door_mesh.size = Vector3(0.5, 0.4, 0.04)
	door_mesh.material = wood_dark
	door.mesh = door_mesh
	_compartment.add_child(door)
	var rosette := MeshInstance3D.new()
	var rosette_mesh := CylinderMesh.new()
	rosette_mesh.top_radius = 0.13
	rosette_mesh.bottom_radius = 0.13
	rosette_mesh.height = 0.02
	rosette_mesh.material = brass
	rosette.mesh = rosette_mesh
	rosette.rotation.x = PI / 2.0
	rosette.position = Vector3(0, 0, 0.03)
	_compartment.add_child(rosette)

	var plaque := Label3D.new()
	plaque.text = "%s  %s  %s" % [
		SYMBOL_GLYPHS[active_target_sequence[0]], SYMBOL_GLYPHS[active_target_sequence[2]],
		SYMBOL_GLYPHS[active_target_sequence[4]]]
	plaque.font_size = 40
	plaque.pixel_size = 0.005
	plaque.modulate = Color(0.9, 0.78, 0.5)
	plaque.position = Vector3(0, 1.42, 0.28)
	add_child(plaque)


func _mat(color: Color, metallic := 0.0, roughness := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


func _glow_mat(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _box(at: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mesh.mesh = box
	mesh.position = at
	add_child(mesh)


func _cyl(parent: Node3D, at: Vector3, radius: float, height: float, mat: StandardMaterial3D) -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.material = mat
	mesh.mesh = cyl
	mesh.position = at
	parent.add_child(mesh)


# --- Fullscreen panel ------------------------------------------------------
# Same modal contract as every other minigame in the mansion: [E] opens
# it (local machine only), solo pauses the tree, co-op locks just this
# player's input, [ESC] or the close button steps away.


var _panel_open := false
var _tile_buttons: Array[Button] = []
var _lever_button: Button
var _reel_buttons: Array[Button] = []
var _panel_hint: Label
var _panel_engraving: Label
var _shake_time := 0.0


func _build_panel() -> void:
	minigame = CanvasLayer.new()
	minigame.layer = 10
	minigame.process_mode = Node.PROCESS_MODE_ALWAYS
	minigame.visible = false
	add_child(minigame)

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	minigame.add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var board := Control.new()
	board.set_anchors_preset(Control.PRESET_CENTER)
	board.offset_left = -360
	board.offset_right = 360
	board.offset_top = -260
	board.offset_bottom = 260
	overlay.add_child(board)

	var plate := Panel.new()
	var plate_style := StyleBoxFlat.new()
	plate_style.bg_color = Color(0.1, 0.06, 0.04)
	plate_style.border_color = Color(0.72, 0.55, 0.25)
	plate_style.set_border_width_all(3)
	plate_style.set_corner_radius_all(10)
	plate.add_theme_stylebox_override("panel", plate_style)
	plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(plate)

	var title := Label.new()
	title.text = "PUZZLE BOX — ASTRONOMICAL LOCK"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.78, 0.5))
	title.position = Vector2(0, 14)
	title.size = Vector2(720, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	board.add_child(title)

	_panel_engraving = Label.new()
	_panel_engraving.text = "Engraved on the case: %s" % _engraving_text()
	_panel_engraving.add_theme_font_size_override("font_size", 20)
	_panel_engraving.add_theme_color_override("font_color", Color(0.85, 0.68, 0.3))
	_panel_engraving.position = Vector2(0, 48)
	_panel_engraving.size = Vector2(720, 26)
	_panel_engraving.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	board.add_child(_panel_engraving)

	# Four dial tiles across the top.
	for i in SYMBOLS.size():
		var sym: String = SYMBOLS[i]
		var btn := _flat_button(Vector2(150.0 + 110.0 * i, 100), Vector2(90, 90))
		btn.draw.connect(_draw_symbol_tile.bind(btn, sym))
		btn.pressed.connect(_on_tile_pressed.bind(sym))
		board.add_child(btn)
		_tile_buttons.append(btn)

	# Lever button beside the dial.
	_lever_button = _flat_button(Vector2(605, 100), Vector2(90, 90))
	_lever_button.draw.connect(_draw_lever.bind(_lever_button))
	_lever_button.pressed.connect(_on_lever_pressed)
	board.add_child(_lever_button)
	var lever_label := Label.new()
	lever_label.text = "PULL"
	lever_label.add_theme_font_size_override("font_size", 13)
	lever_label.add_theme_color_override("font_color", Color(0.75, 0.68, 0.55))
	lever_label.position = Vector2(605, 192)
	lever_label.size = Vector2(90, 18)
	lever_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	board.add_child(lever_label)

	# Reel windows: readout of confirmed slots.
	var reel_label := Label.new()
	reel_label.text = "CONFIRMED SEQUENCE"
	reel_label.add_theme_font_size_override("font_size", 14)
	reel_label.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5))
	reel_label.position = Vector2(0, 260)
	reel_label.size = Vector2(720, 20)
	reel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	board.add_child(reel_label)
	for i in sequence_length:
		var reel := _flat_button(Vector2(300.0 + 60.0 * i, 288), Vector2(50, 50))
		reel.disabled = true
		reel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		reel.draw.connect(_draw_reel.bind(reel, i))
		board.add_child(reel)
		_reel_buttons.append(reel)

	_panel_hint = Label.new()
	_panel_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel_hint.offset_top = -46
	_panel_hint.offset_bottom = -10
	_panel_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel_hint.add_theme_font_size_override("font_size", 16)
	board.add_child(_panel_hint)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.position = Vector2(688, 10)
	close_btn.size = Vector2(32, 32)
	close_btn.pressed.connect(func() -> void: _close_panel())
	board.add_child(close_btn)

	input_registered.connect(func(_s: String) -> void: _refresh_panel())
	advance_clicked.connect(func() -> void: _refresh_panel())
	sequence_failed.connect(_on_panel_failed)
	puzzle_unlocked.connect(_on_panel_unlocked)


func _engraving_text() -> String:
	var parts: Array[String] = []
	for i in sequence_length:
		parts.append(SYMBOL_GLYPHS[active_target_sequence[i * 2]])
	return "  ".join(parts)


func _flat_button(at: Vector2, size: Vector2) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.position = at
	btn.size = size
	var empty := StyleBoxEmpty.new()
	for style in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(style, empty)
	return btn


func _open_panel() -> void:
	if _panel_open:
		return
	_panel_open = true
	minigame.visible = true
	minigame.add_to_group("modal_ui")
	if NetworkSession.multiplayer_active:
		_set_local_lock(true)
	else:
		get_tree().paused = true
	_refresh_panel()


func _close_panel() -> void:
	if not _panel_open:
		return
	_panel_open = false
	minigame.visible = false
	minigame.remove_from_group("modal_ui")
	if NetworkSession.multiplayer_active:
		_set_local_lock(false)
	else:
		get_tree().paused = false


func _set_local_lock(locked: bool) -> void:
	for player in get_tree().get_nodes_in_group("players"):
		if player.is_local_player():
			player.ui_locked = locked


func _local_player() -> Node:
	for player in get_tree().get_nodes_in_group("players"):
		if player.is_local_player():
			return player
	return null


func _on_tile_pressed(symbol: String) -> void:
	var local := _local_player()
	if local == null or not is_locked:
		return
	AudioSynthesizer.play_ui("tick", -12.0, 1.2)
	request_dial_input(local, symbol)


func _on_lever_pressed() -> void:
	var local := _local_player()
	if local == null or not is_locked:
		return
	request_advance_input(local)


func _on_panel_failed() -> void:
	_shake_time = 0.35
	AudioSynthesizer.play_ui("zap", -12.0, 1.1)
	_refresh_panel()


func _on_panel_unlocked() -> void:
	_refresh_panel()
	if not _panel_open:
		return
	AudioSynthesizer.play_ui("chime", -6.0)
	await get_tree().create_timer(1.6, true).timeout
	_close_panel()


func _refresh_panel() -> void:
	refresh_reels()
	for btn in _tile_buttons:
		btn.queue_redraw()
	_lever_button.queue_redraw()
	for reel in _reel_buttons:
		reel.queue_redraw()
	if not is_locked:
		_panel_hint.text = "The mechanism gives — the lock releases!"
		_panel_hint.modulate = Color(0.55, 1.0, 0.65)
	elif is_waiting_for_cadence:
		_panel_hint.text = "Gears settling — wait before touching the dial.  [ESC] steps away."
		_panel_hint.modulate = Color(1.0, 0.8, 0.4)
	elif current_input_buffer.size() % 2 == 1:
		_panel_hint.text = "Symbol accepted — pull the lever to advance.  [ESC] steps away."
		_panel_hint.modulate = Color(0.55, 1.0, 0.65)
	else:
		_panel_hint.text = "Match the engraving: click a symbol, then pull the lever.  [ESC] steps away."
		_panel_hint.modulate = Color.WHITE


func _input(event: InputEvent) -> void:
	if not _panel_open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close_panel()


func _process(delta: float) -> void:
	if _shake_time > 0.0:
		_shake_time -= delta


# --- Custom drawing --------------------------------------------------------


func _draw_symbol_tile(btn: Button, symbol: String) -> void:
	var c := btn.size / 2.0
	var active: bool = is_locked and not is_waiting_for_cadence
	var color := Color(0.9, 0.78, 0.5) if active else Color(0.4, 0.38, 0.35)
	btn.draw_arc(c, 38.0, 0, TAU, 32, color, 2.5)
	_draw_glyph(btn, c, symbol, 26.0, color)


func _draw_lever(btn: Button) -> void:
	var c := btn.size / 2.0
	var awaiting: bool = is_locked and current_input_buffer.size() % 2 == 1 and not is_waiting_for_cadence
	var color := Color(1.0, 0.85, 0.4) if awaiting else Color(0.75, 0.68, 0.55)
	btn.draw_circle(c, 34.0, Color(color.r, color.g, color.b, 0.15))
	btn.draw_arc(c, 34.0, 0, TAU, 32, color, 3.0)
	btn.draw_line(c, c + Vector2(0, -26), color, 5.0)
	btn.draw_circle(c + Vector2(0, -26), 7.0, color)


func _draw_reel(btn: Button, index: int) -> void:
	var c := btn.size / 2.0
	var confirmed := current_input_buffer.size() / 2
	btn.draw_rect(Rect2(Vector2.ZERO, btn.size), Color(0.05, 0.04, 0.03), true)
	btn.draw_rect(Rect2(Vector2.ZERO, btn.size), Color(0.72, 0.55, 0.25), false, 2.0)
	if index < confirmed:
		var sym: String = active_target_sequence[index * 2]
		_draw_glyph(btn, c, sym, 16.0, Color(0.55, 1.0, 0.65))


## Simple engine-drawn glyphs so no external icon assets are needed.
func _draw_glyph(item: CanvasItem, c: Vector2, symbol: String, r: float, color: Color) -> void:
	match symbol:
		"sun":
			item.draw_circle(c, r * 0.42, color)
			for k in 8:
				var a := TAU * float(k) / 8.0
				var dir := Vector2(cos(a), sin(a))
				item.draw_line(c + dir * r * 0.55, c + dir * r * 0.95, color, 2.5)
		"moon":
			item.draw_circle(c, r * 0.6, color)
			item.draw_circle(c + Vector2(r * 0.28, 0), r * 0.52, Color(0.1, 0.06, 0.04))
		"star":
			var pts := PackedVector2Array()
			for k in 10:
				var a := -PI / 2.0 + TAU * float(k) / 10.0
				var rad := r if k % 2 == 0 else r * 0.42
				pts.append(c + Vector2(cos(a), sin(a)) * rad)
			item.draw_colored_polygon(pts, color)
		"sparkle":
			for a in [0.0, PI / 2.0, PI, 3.0 * PI / 2.0]:
				var dir := Vector2(cos(a), sin(a))
				var perp := Vector2(-dir.y, dir.x) * 0.12
				item.draw_colored_polygon(PackedVector2Array([
					c, c + dir * r + perp * r, c + dir * r * 1.25, c + dir * r - perp * r]), color)
			item.draw_circle(c, r * 0.18, color)
