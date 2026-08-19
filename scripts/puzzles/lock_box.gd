class_name LockBox
extends Interactable

## The vault's final lock: an iron strongbox on the will pedestal with
## three brass number dials (0-9). Each digit is engraved into one of the
## mansion's machines and revealed — into the [Tab] notes — when that
## machine is mastered (wall safe, astronomical box, hydraulic press).
## Dial in all three and try the latch: wrong guesses just clunk (the
## dials keep their positions — no reset, no lockout); the right ones
## swing the lid open and surrender the will.
##
## Spawned by the generator as a bare StaticBody3D + set_script, with
## `combination` assigned from the seeded run RNG BEFORE add_child so
## every co-op peer agrees on the secret.

signal dial_changed(index: int, value: int)
signal open_attempted()
signal unlocked()

## The three winning digits, seeded per run by the generator.
@export var combination: Array[int] = [0, 0, 0]

var dials: Array[int] = [0, 0, 0]
var is_locked := true

var minigame: CanvasLayer
var _stashed: Node3D
var _lid_pivot: Node3D
var _dial_labels: Array[Label3D] = []


func _ready() -> void:
	add_to_group("lock_boxes")
	# The panel's ESC handler lives on THIS node (see _input below); solo
	# pauses the whole tree, so this node must keep receiving input while
	# paused or the ✕ button becomes the only way out.
	process_mode = Node.PROCESS_MODE_ALWAYS
	display_name = "Vault Strongbox"
	prompt_action = "Inspect the Strongbox"
	prompt_height = 1.1
	_build_case()
	_build_panel()


func can_interact(_by: Node3D) -> bool:
	return is_locked


## [E] inspects; the dials and latch are worked from inside the overlay.
## It only opens on the interacting machine.
func interact(by: Node3D) -> void:
	if not is_locked:
		return
	if by == null or not by.has_method("is_local_player") or by.is_local_player():
		_open_panel()
	super.interact(by)


## Park an item (frozen, collision off) inside the box until the latch
## gives. Call before the item is added anywhere else.
func stash_item(item: Node3D) -> void:
	_stashed = item
	item.set("freeze", true)
	item.set("collision_layer", 0)
	item.set("collision_mask", 0)
	# Out of sight until the lid opens: the Will carries its own
	# lamp and particle aura, and the shell is far too small to
	# contain them — a sealed box glowing gold would give the
	# whole reveal away.
	item.visible = false
	add_child(item)
	item.position = Vector3(0, 0.22, 0)


# --- Dial-and-latch state machine -----------------------------------------


func set_dial(index: int, value: int) -> void:
	if not is_locked or index < 0 or index >= dials.size():
		return
	dials[index] = posmod(value, 10)
	dial_changed.emit(index, dials[index])
	_refresh_dials()


func try_open() -> void:
	if not is_locked:
		return
	open_attempted.emit()
	if dials == combination:
		_unlock()
	else:
		_play_failure()


func _unlock() -> void:
	is_locked = false
	unlocked.emit()
	_play_unlock()


# --- Replicated entry points (called by the panel overlay) ----------------


func request_set_dial(_by: Node3D, index: int, value: int) -> void:
	if NetworkSession.multiplayer_active:
		_net_set_dial.rpc(index, value)
	else:
		set_dial(index, value)


@rpc("any_peer", "call_local", "reliable")
func _net_set_dial(index: int, value: int) -> void:
	set_dial(index, value)


func request_try_open(_by: Node3D) -> void:
	if NetworkSession.multiplayer_active:
		_net_try_open.rpc()
	else:
		try_open()


@rpc("any_peer", "call_local", "reliable")
func _net_try_open() -> void:
	try_open()


# --- World model + physical feedback --------------------------------------


func _play_failure() -> void:
	AudioSynthesizer.play_at("zap", global_position, -12.0, 0.8)
	Player.shake(0.1, global_position)
	var tween := create_tween()
	for i in 2:
		tween.tween_property(self, "rotation:z", deg_to_rad(1.6), 0.04)
		tween.tween_property(self, "rotation:z", deg_to_rad(-1.6), 0.08)
	tween.tween_property(self, "rotation:z", 0.0, 0.04)


func _play_unlock() -> void:
	AudioSynthesizer.play_at("chime", global_position, -2.0, 1.25)
	_close_panel()
	var tween := create_tween()
	if _lid_pivot:
		tween.tween_property(_lid_pivot, "rotation:x", deg_to_rad(-105.0), 0.6) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_release_stash)


func _release_stash() -> void:
	if _stashed == null:
		return
	var item := _stashed
	_stashed = null
	item.reparent(get_parent())
	item.visible = true
	# Out the front (+Z, into the room) and up, so the will tumbles off
	# the pedestal onto the vault floor where it can be grabbed.
	item.global_position = global_position + global_transform.basis.z * 0.9 + Vector3(0, 0.3, 0)
	item.set("freeze", false)
	item.set("collision_layer", 1)
	item.set("collision_mask", 1)


func _refresh_dials() -> void:
	for i in _dial_labels.size():
		_dial_labels[i].text = str(dials[i])


## Procedural strongbox: iron body, brass banding, a hinged lid, three
## front-facing number dials with live readouts, and an engraved plate.
func _build_case() -> void:
	var iron := _mat(Color(0.16, 0.16, 0.19), 0.7, 0.5)
	var brass := _mat(Color(0.72, 0.55, 0.25), 0.9, 0.35)
	var dark_brass := _mat(Color(0.45, 0.34, 0.16), 0.85, 0.45)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.68, 0.52, 0.52)
	col.shape = shape
	col.position = Vector3(0, 0.26, 0)
	add_child(col)

	_box_mesh_at(Vector3(0, 0.17, 0), Vector3(0.62, 0.34, 0.44), iron)
	# Brass banding: two straps over the body.
	for x in [-0.18, 0.18]:
		_box_mesh_at(Vector3(x, 0.17, 0), Vector3(0.05, 0.35, 0.455), brass)
	# Hinged lid on a rear pivot so it swings up and back on unlock.
	_lid_pivot = Node3D.new()
	_lid_pivot.position = Vector3(0, 0.34, -0.22)
	add_child(_lid_pivot)
	var lid := MeshInstance3D.new()
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(0.64, 0.1, 0.46)
	lid_mesh.material = iron
	lid.mesh = lid_mesh
	lid.position = Vector3(0, 0.05, 0.22)
	_lid_pivot.add_child(lid)
	for x in [-0.18, 0.18]:
		var strap := MeshInstance3D.new()
		var strap_mesh := BoxMesh.new()
		strap_mesh.size = Vector3(0.05, 0.11, 0.47)
		strap_mesh.material = brass
		strap.mesh = strap_mesh
		strap.position = Vector3(x, 0.05, 0.22)
		_lid_pivot.add_child(strap)

	# Three brass number dials across the front face, readouts above.
	for i in 3:
		var x := -0.16 + 0.16 * i
		var dial := MeshInstance3D.new()
		var dial_mesh := CylinderMesh.new()
		dial_mesh.top_radius = 0.045
		dial_mesh.bottom_radius = 0.045
		dial_mesh.height = 0.03
		dial_mesh.material = dark_brass
		dial.mesh = dial_mesh
		dial.rotation.x = PI / 2.0
		dial.position = Vector3(x, 0.12, 0.235)
		add_child(dial)
		var digit := Label3D.new()
		digit.text = "0"
		digit.font_size = 34
		digit.pixel_size = 0.004
		digit.modulate = Color(1.0, 0.85, 0.45)
		digit.position = Vector3(x, 0.24, 0.235)
		add_child(digit)
		_dial_labels.append(digit)

	var plaque := Label3D.new()
	plaque.text = "THREE MACHINES · THREE NUMBERS"
	plaque.font_size = 22
	plaque.pixel_size = 0.0018
	plaque.modulate = Color(0.8, 0.66, 0.35)
	plaque.position = Vector3(0, 0.05, 0.24)
	add_child(plaque)


func _box_mesh_at(at: Vector3, size: Vector3, material: StandardMaterial3D) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	mesh.mesh = box
	mesh.position = at
	add_child(mesh)


func _mat(color: Color, metallic := 0.0, roughness := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


# --- Fullscreen panel ------------------------------------------------------
# Same modal contract as every other minigame in the mansion: [E] opens
# it (local machine only), solo pauses the tree, co-op locks just this
# player's input, [ESC] or the close button steps away.


var _panel_open := false
var _panel_digits: Array[Label] = []
var _panel_hint: Label


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
	board.offset_left = -320
	board.offset_right = 320
	board.offset_top = -230
	board.offset_bottom = 230
	overlay.add_child(board)

	var plate := Panel.new()
	var plate_style := StyleBoxFlat.new()
	plate_style.bg_color = Color(0.09, 0.08, 0.075)
	plate_style.border_color = Color(0.72, 0.55, 0.25)
	plate_style.set_border_width_all(3)
	plate_style.set_corner_radius_all(10)
	plate.add_theme_stylebox_override("panel", plate_style)
	plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(plate)

	var title := Label.new()
	title.text = "VAULT STRONGBOX"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.78, 0.5))
	title.position = Vector2(0, 14)
	title.size = Vector2(640, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	board.add_child(title)

	var engraving := Label.new()
	engraving.text = "“My machines each surrendered a number.” — C.G."
	engraving.add_theme_font_size_override("font_size", 15)
	engraving.add_theme_color_override("font_color", Color(0.75, 0.62, 0.35))
	engraving.position = Vector2(0, 48)
	engraving.size = Vector2(640, 22)
	engraving.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	board.add_child(engraving)

	var sources := Label.new()
	sources.text = "THE SAFE          THE BOX          THE PRESS"
	sources.add_theme_font_size_override("font_size", 13)
	sources.add_theme_color_override("font_color", Color(0.6, 0.55, 0.45))
	sources.position = Vector2(0, 86)
	sources.size = Vector2(640, 18)
	sources.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	board.add_child(sources)

	# Three dial columns: ▲, big digit plate, ▼.
	for i in 3:
		var cx := 175.0 + 145.0 * i
		var up := Button.new()
		up.text = "▲"
		up.focus_mode = Control.FOCUS_NONE
		up.position = Vector2(cx, 112)
		up.size = Vector2(96, 36)
		up.pressed.connect(_on_dial_stepped.bind(i, 1))
		board.add_child(up)
		var plate_bg := Panel.new()
		var digit_style := StyleBoxFlat.new()
		digit_style.bg_color = Color(0.05, 0.045, 0.04)
		digit_style.border_color = Color(0.5, 0.4, 0.2)
		digit_style.set_border_width_all(2)
		digit_style.set_corner_radius_all(8)
		plate_bg.add_theme_stylebox_override("panel", digit_style)
		plate_bg.position = Vector2(cx, 154)
		plate_bg.size = Vector2(96, 96)
		plate_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		board.add_child(plate_bg)
		var digit := Label.new()
		digit.text = "0"
		digit.add_theme_font_size_override("font_size", 56)
		digit.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
		digit.position = Vector2(cx, 154)
		digit.size = Vector2(96, 96)
		digit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		digit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		board.add_child(digit)
		_panel_digits.append(digit)
		var down := Button.new()
		down.text = "▼"
		down.focus_mode = Control.FOCUS_NONE
		down.position = Vector2(cx, 256)
		down.size = Vector2(96, 36)
		down.pressed.connect(_on_dial_stepped.bind(i, -1))
		board.add_child(down)

	var latch := Button.new()
	latch.text = "TRY THE LATCH"
	latch.focus_mode = Control.FOCUS_NONE
	latch.add_theme_font_size_override("font_size", 19)
	latch.position = Vector2(220, 322)
	latch.size = Vector2(200, 46)
	latch.pressed.connect(_on_latch_pressed)
	board.add_child(latch)

	_panel_hint = Label.new()
	_panel_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel_hint.offset_top = -46
	_panel_hint.offset_bottom = -10
	_panel_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel_hint.add_theme_font_size_override("font_size", 16)
	_panel_hint.text = "Its numbers are written in your notes — [Tab]"
	_panel_hint.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	board.add_child(_panel_hint)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.position = Vector2(598, 10)
	close_btn.size = Vector2(32, 32)
	close_btn.pressed.connect(func() -> void: _close_panel())
	board.add_child(close_btn)

	dial_changed.connect(func(_i: int, _v: int) -> void: _refresh_panel())
	open_attempted.connect(_on_panel_attempted)
	unlocked.connect(_on_panel_unlocked)


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


func _on_dial_stepped(index: int, delta: int) -> void:
	var local := _local_player()
	if local == null or not is_locked:
		return
	AudioSynthesizer.play_ui("ratchet", -14.0, 1.4)
	request_set_dial(local, index, posmod(dials[index] + delta, 10))


func _on_latch_pressed() -> void:
	var local := _local_player()
	if local == null or not is_locked:
		return
	request_try_open(local)


func _on_panel_attempted() -> void:
	if not is_locked:
		return
	_panel_hint.text = "The latch holds fast. Wrong numbers."
	_panel_hint.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))


func _on_panel_unlocked() -> void:
	_panel_hint.text = "The latch gives — the lid swings open!"
	_panel_hint.add_theme_color_override("font_color", Color(0.55, 1.0, 0.65))


func _refresh_panel() -> void:
	for i in _panel_digits.size():
		_panel_digits[i].text = str(dials[i])


func _input(event: InputEvent) -> void:
	if _panel_open and event.is_action_pressed("ui_cancel"):
		_close_panel()
		get_viewport().set_input_as_handled()
