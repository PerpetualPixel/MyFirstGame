class_name LaserSafe
extends Interactable

## Wall safe hanging beside the vault doorway: iron box, keyed door, no
## key. It is the laser puzzle's target. Focused light on its face for
## `required_time` blows the lock — the door swings open with sparks —
## and exposes a brass lever; [E] on the lever throws it and emits
## `puzzle_completed` (the vault gate listens). Before it is cracked, [E]
## opens a first-person close-up with the note taped to the door.
## Local frame: the box hangs on a wall behind it (-Z), face toward +Z.

signal puzzle_completed
signal cracked_changed

@export var required_time: float = 0.5

const COLOR_IDLE := Color(0.9, 0.45, 0.18)
const COLOR_LIT := Color(0.35, 1.0, 1.0)
const NOTE_TEXT := "I lost the keys sorry.\nOnly something as strong as a laser can crack this open."

var cracked := false
var lever_pulled := false
var is_solved := false  # alias kept for the vault gate / tests

var _powered_frame: int = -100
var _accum := 0.0
var _door: Node3D
var _lever: Node3D
var _lock_mat := StandardMaterial3D.new()
var _panel: CanvasLayer
var _panel_open := false


func _ready() -> void:
	add_to_group("laser_safes")
	display_name = "Wall Safe"
	prompt_action = "Inspect Safe"
	prompt_height = 1.9
	_build_box()
	_build_panel()


# --- Beam --------------------------------------------------------------


## Called by LaserBeam.dispatch() every physics frame the beam lands here.
func beam_hit() -> void:
	_powered_frame = Engine.get_physics_frames()


func _physics_process(delta: float) -> void:
	var powered := Engine.get_physics_frames() - _powered_frame <= 1
	if powered and not cracked:
		_accum += delta
		if _accum >= required_time:
			_crack()
	elif not powered:
		_accum = 0.0
	# The lock glows as the beam cooks it.
	var lit := powered or cracked
	var target := COLOR_LIT if lit else COLOR_IDLE
	var w := 1.0 - exp(-8.0 * delta)
	_lock_mat.emission = _lock_mat.emission.lerp(target, w)
	_lock_mat.albedo_color = _lock_mat.albedo_color.lerp(target, w)
	_lock_mat.emission_energy_multiplier = lerpf(_lock_mat.emission_energy_multiplier, 3.0 if lit else 0.6, w)


## The lock gives: door swings wide, sparks, the lever is exposed.
func _crack() -> void:
	if cracked:
		return
	cracked = true
	prompt_action = "Pull Lever"
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_door, "rotation:y", deg_to_rad(-115.0), 0.7)
	AudioSynthesizer.play_at("zap", global_position, -6.0, 0.7)
	AudioSynthesizer.play_at("drop_metal", global_position, -8.0, 0.8)
	Player.shake(0.3, global_position)
	Door._dust_puff(global_position + Vector3(0, -1.0, 0.4), 12)
	if _panel_open:
		_close_panel()
	cracked_changed.emit()


# --- Interaction ---------------------------------------------------------


func can_interact(_by: Node3D) -> bool:
	return not lever_pulled


func get_prompt(_by: Node3D = null) -> String:
	if lever_pulled:
		return ""
	if cracked:
		return "[E] Pull Lever"
	return "[E] Inspect Safe"


func interact(by: Node3D) -> void:
	if lever_pulled:
		return
	if cracked:
		_pull_lever()
	elif by == null or not by.has_method("is_local_player") or by.is_local_player():
		# The close-up only opens on the interacting machine.
		_open_panel()
	super.interact(by)


## Throw the lever: this replicates through the player's interact RPC.
func _pull_lever() -> void:
	if lever_pulled:
		return
	lever_pulled = true
	is_solved = true
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_lever, "rotation:x", deg_to_rad(70.0), 0.35)
	AudioSynthesizer.play_at("ratchet", global_position, -2.0, 0.6)
	AudioSynthesizer.play_at("rumble", global_position, -10.0, 1.4)
	puzzle_completed.emit()


# --- First-person close-up ---------------------------------------------


func _open_panel() -> void:
	if _panel_open:
		return
	_panel_open = true
	_panel.visible = true
	_panel.add_to_group("modal_ui")
	# Keep the note in the [Tab] pad so it can be re-read from anywhere.
	PlayerNotes.add("Wall safe — \"I lost the keys sorry. Only something as strong as a laser can crack this open.\"")
	if NetworkSession.multiplayer_active:
		_set_local_lock(true)
	else:
		get_tree().paused = true
	AudioSynthesizer.play_ui("tick", -14.0, 0.9)


func _close_panel() -> void:
	if not _panel_open:
		return
	_panel_open = false
	_panel.visible = false
	_panel.remove_from_group("modal_ui")
	if NetworkSession.multiplayer_active:
		_set_local_lock(false)
	else:
		get_tree().paused = false


func _set_local_lock(locked: bool) -> void:
	for player in get_tree().get_nodes_in_group("players"):
		if player.is_local_player():
			player.ui_locked = locked


func _unhandled_input(event: InputEvent) -> void:
	if _panel_open and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact")):
		get_viewport().set_input_as_handled()
		_close_panel()


## Fullscreen close-up: the iron door, keyhole, and the taped note.
func _build_panel() -> void:
	_panel = CanvasLayer.new()
	_panel.layer = 10
	_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.visible = false
	add_child(_panel)
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var board := Control.new()
	board.set_anchors_preset(Control.PRESET_CENTER)
	board.offset_left = -330
	board.offset_right = 330
	board.offset_top = -250
	board.offset_bottom = 250
	overlay.add_child(board)
	# Safe body and door.
	var body := Panel.new()
	var body_style := StyleBoxFlat.new()
	body_style.bg_color = Color(0.2, 0.21, 0.24)
	body_style.border_color = Color(0.1, 0.1, 0.12)
	body_style.set_border_width_all(6)
	body_style.set_corner_radius_all(8)
	body.add_theme_stylebox_override("panel", body_style)
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(body)
	var door := Panel.new()
	var door_style := StyleBoxFlat.new()
	door_style.bg_color = Color(0.27, 0.28, 0.32)
	door_style.border_color = Color(0.14, 0.14, 0.17)
	door_style.set_border_width_all(4)
	door_style.set_corner_radius_all(4)
	door.add_theme_stylebox_override("panel", door_style)
	door.position = Vector2(60, 50)
	door.size = Vector2(540, 400)
	door.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(door)
	for hy in [110.0, 350.0]:
		var hinge := ColorRect.new()
		hinge.color = Color(0.6, 0.6, 0.65)
		hinge.position = Vector2(50, hy)
		hinge.size = Vector2(22, 34)
		hinge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		board.add_child(hinge)
	var keyhole := Control.new()
	keyhole.position = Vector2(470, 240)
	keyhole.size = Vector2(60, 60)
	keyhole.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keyhole.draw.connect(func() -> void:
		keyhole.draw_circle(Vector2(30, 30), 26, Color(0.55, 0.55, 0.6))
		keyhole.draw_circle(Vector2(30, 24), 8, Color(0.05, 0.05, 0.06))
		keyhole.draw_rect(Rect2(26, 24, 8, 20), Color(0.05, 0.05, 0.06)))
	board.add_child(keyhole)
	# The taped note.
	var note := Panel.new()
	var note_style := StyleBoxFlat.new()
	note_style.bg_color = Color(0.9, 0.86, 0.72)
	note_style.border_color = Color(0.7, 0.62, 0.45)
	note_style.set_border_width_all(2)
	note_style.content_margin_left = 16
	note_style.content_margin_right = 16
	note_style.content_margin_top = 12
	note_style.content_margin_bottom = 12
	note.add_theme_stylebox_override("panel", note_style)
	note.position = Vector2(110, 120)
	note.size = Vector2(320, 190)
	note.rotation = deg_to_rad(-3.0)
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(note)
	var tape := ColorRect.new()
	tape.color = Color(0.95, 0.9, 0.7, 0.75)
	tape.position = Vector2(230, 96)
	tape.size = Vector2(80, 22)
	tape.rotation = deg_to_rad(6.0)
	tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(tape)
	var text := Label.new()
	text.text = NOTE_TEXT
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 20)
	text.add_theme_color_override("font_color", Color(0.22, 0.16, 0.1))
	text.set_anchors_preset(Control.PRESET_FULL_RECT)
	note.add_child(text)
	var hint := Label.new()
	hint.text = "Wall safe — no key.  [E] / [ESC] step away."
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -42
	hint.offset_bottom = -10
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	hint.add_theme_constant_override("outline_size", 6)
	overlay.add_child(hint)


# --- World model ---------------------------------------------------------


func _build_box() -> void:
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.2, 0.21, 0.24)
	iron.metallic = 0.6
	iron.roughness = 0.5
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.09, 0.09, 0.11)
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.72, 0.55, 0.25)
	brass.metallic = 0.8
	brass.roughness = 0.3
	# Box: 0.7 wide, 0.7 tall, 0.36 deep, centered at beam height 1.2.
	var box_center := Vector3(0, 1.2, 0.18)
	_add_box(Vector3(0, 1.2, 0.05), Vector3(0.7, 0.7, 0.1), iron)             # back plate
	_add_box(Vector3(-0.32, 1.2, 0.18), Vector3(0.06, 0.7, 0.36), iron)       # sides
	_add_box(Vector3(0.32, 1.2, 0.18), Vector3(0.06, 0.7, 0.36), iron)
	_add_box(Vector3(0, 1.52, 0.18), Vector3(0.7, 0.06, 0.36), iron)          # top / bottom
	_add_box(Vector3(0, 0.88, 0.18), Vector3(0.7, 0.06, 0.36), iron)
	_add_box(Vector3(0, 1.2, 0.2), Vector3(0.58, 0.58, 0.02), dark)           # dark interior
	# Lever inside, hidden behind the door until it swings.
	_lever = Node3D.new()
	_lever.position = Vector3(0.05, 1.05, 0.22)
	add_child(_lever)
	var stem := MeshInstance3D.new()
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.02
	stem_mesh.bottom_radius = 0.02
	stem_mesh.height = 0.26
	stem_mesh.material = brass
	stem.mesh = stem_mesh
	stem.position = Vector3(0, 0.13, 0)
	_lever.add_child(stem)
	var knob := MeshInstance3D.new()
	var knob_mesh := SphereMesh.new()
	knob_mesh.radius = 0.04
	knob_mesh.height = 0.08
	knob_mesh.material = brass
	knob.mesh = knob_mesh
	knob.position = Vector3(0, 0.27, 0)
	_lever.add_child(knob)
	# Door: hinged on its left edge, purely visual (the root body's box
	# below is what the beam and the player collide with); the keyed lock
	# in the middle glows under the beam.
	_door = Node3D.new()
	_door.position = Vector3(-0.32, 1.2, 0.36)
	add_child(_door)
	var door_body := Node3D.new()
	_door.add_child(door_body)
	var door_mesh := MeshInstance3D.new()
	var door_box := BoxMesh.new()
	door_box.size = Vector3(0.62, 0.62, 0.05)
	door_box.material = iron
	door_mesh.mesh = door_box
	door_mesh.position = Vector3(0.31, 0, 0)
	door_body.add_child(door_mesh)
	_lock_mat.albedo_color = COLOR_IDLE
	_lock_mat.emission_enabled = true
	_lock_mat.emission = COLOR_IDLE
	_lock_mat.emission_energy_multiplier = 0.6
	var lock := MeshInstance3D.new()
	var lock_mesh := CylinderMesh.new()
	lock_mesh.top_radius = 0.045
	lock_mesh.bottom_radius = 0.045
	lock_mesh.height = 0.03
	lock_mesh.material = _lock_mat
	lock.mesh = lock_mesh
	lock.rotation.x = PI / 2.0
	lock.position = Vector3(0.44, 0.0, 0.03)
	door_body.add_child(lock)
	# Whole-box collision (including the door face) on the ROOT body: the
	# beam's hit lands on this node so beam_hit() fires, and the player
	# can't stand inside it. Stays put when the door swings.
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.7, 0.7, 0.42)
	col.shape = shape
	col.position = box_center + Vector3(0, 0, 0.03)
	add_child(col)
	# Small brass plaque under the box.
	var plaque := Label3D.new()
	plaque.text = "STRONGBOX"
	plaque.font_size = 28
	plaque.pixel_size = 0.004
	plaque.modulate = Color(0.85, 0.68, 0.3)
	plaque.position = Vector3(0, 0.78, 0.37)
	add_child(plaque)


func _add_box(at: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mesh.mesh = box
	mesh.position = at
	add_child(mesh)
