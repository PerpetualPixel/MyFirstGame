class_name CodeNote
extends NotebookPickup

## The estate ledger page that carries the front-door code. Unlike the
## inventor's other notes it is worth looking at, so [E] pulls the page
## up full-screen: a hand-torn leaf of squared paper, ruled and stained,
## with the code inked across it in his hand.
##
## The last digit is blotted out. The keypad takes unlimited attempts, so
## a smudged digit costs a player ten tries at worst — it turns a number
## you simply read into one you have to work at, without ever being able
## to lock the run.

## Set by the generator alongside note_text.
@export var full_code := "0000"

var _panel: CanvasLayer
var _panel_open := false
## Which character of the code is unreadable (always the last).
var _smudged_index := 3


func _ready() -> void:
	# The close-up's ESC handler lives on THIS node, and solo pauses the
	# whole tree — without ALWAYS it would stop receiving input the
	# moment the page came up.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_smudged_index = full_code.length() - 1
	_build_panel()


func get_prompt(_by: Node3D = null) -> String:
	return "[E] Read the Ledger Page"


## Reading it banks the legible part in the notepad AND shows the page.
func interact(by: Node3D) -> void:
	if taken:
		return
	taken = true
	PlayerNotes.add(note_text)
	AudioSynthesizer.play_at("drop_paper", global_position, -8.0, 1.1)
	if by == null or not by.has_method("is_local_player") or by.is_local_player():
		_open_panel()
	# Deliberately NOT freed: the page stays where it lies so it can be
	# read again — the smudged digit means a player may want a second look.
	interacted.emit(by)


func can_interact(_by: Node3D) -> bool:
	return true


func _open_panel() -> void:
	if _panel_open:
		return
	_panel_open = true
	_panel.visible = true
	_panel.add_to_group("modal_ui")
	if NetworkSession.multiplayer_active:
		_set_local_lock(true)
	else:
		get_tree().paused = true


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
	if not _panel_open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		_close_panel()
		get_viewport().set_input_as_handled()


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
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	# The page itself, drawn rather than styled: paper, rules, ink and
	# the blot all come from _draw_page below.
	var page := Control.new()
	page.set_anchors_preset(Control.PRESET_CENTER)
	page.offset_left = -300
	page.offset_right = 300
	page.offset_top = -215
	page.offset_bottom = 215
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.draw.connect(_draw_page.bind(page))
	overlay.add_child(page)

	var hint := Label.new()
	hint.text = "[E] or [ESC] to put the page down"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -52.0
	hint.offset_bottom = -18.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.8, 0.75, 0.62))
	overlay.add_child(hint)


## A leaf of old squared paper: warm stock, a torn left edge, faint rules,
## two tea rings, the inventor's hand, and a blot of ink over one digit.
func _draw_page(page: Control) -> void:
	var w := page.size.x
	var h := page.size.y
	var paper := Color(0.90, 0.86, 0.74)
	var ink := Color(0.16, 0.13, 0.24)

	page.draw_rect(Rect2(Vector2(6, 8), Vector2(w, h)), Color(0, 0, 0, 0.35))
	page.draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), paper)
	# Torn left edge: a ragged sawtooth bitten out of the sheet.
	var tear := PackedVector2Array([Vector2(0, 0)])
	var y := 0.0
	var k := 0
	while y < h:
		tear.append(Vector2(5.0 + (6.0 if k % 2 == 0 else 0.0), y))
		y += 13.0
		k += 1
	tear.append(Vector2(0, h))
	page.draw_colored_polygon(tear, Color(0.82, 0.78, 0.66))
	# Faint blue rules and a red margin, like a ledger sheet.
	for i in int(h / 26.0):
		var ry := 44.0 + i * 26.0
		if ry < h - 12.0:
			page.draw_line(Vector2(26, ry), Vector2(w - 20, ry), Color(0.55, 0.6, 0.68, 0.4), 1.0)
	page.draw_line(Vector2(58, 8), Vector2(58, h - 8), Color(0.7, 0.35, 0.32, 0.45), 1.5)
	# Tea rings.
	for ring in [[Vector2(w - 92, 70), 40.0], [Vector2(96, h - 62), 27.0]]:
		page.draw_arc(ring[0], ring[1], 0.0, TAU, 48, Color(0.62, 0.47, 0.28, 0.30), 4.0)

	var font := ThemeDB.fallback_font
	page.draw_string(font, Vector2(74, 46), "Gearhart estate — day book",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 21, ink * Color(1, 1, 1, 0.85))
	page.draw_string(font, Vector2(74, 96), "Front door, north porch. Changed it again",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, ink)
	page.draw_string(font, Vector2(74, 122), "because C. keeps writing it on his cuff.",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, ink)

	# The code, inked large, digit by digit — with one lost under a blot.
	var x := 108.0
	for i in full_code.length():
		var centre := Vector2(x + 34.0, 208.0)
		if i == _smudged_index:
			_draw_blot(page, centre)
		else:
			page.draw_string(font, Vector2(x, 226), full_code[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 58, ink)
		x += 84.0
	page.draw_line(Vector2(100, 244), Vector2(x - 16, 244), Color(0.7, 0.35, 0.32, 0.5), 2.0)

	page.draw_string(font, Vector2(74, 296), "— and the last one is a write-off. Ink ran.",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ink * Color(1, 1, 1, 0.9))
	page.draw_string(font, Vector2(74, 322), "Ten tries at worst. The old girl doesn't bite.",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ink * Color(1, 1, 1, 0.9))
	page.draw_string(font, Vector2(74, 372), "— Mrs. P.",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ink * Color(1, 1, 1, 0.8))


## A run of ink: overlapping blobs with a couple of dribbles, sized to
## swallow a digit whole so there is nothing to squint at.
func _draw_blot(page: Control, centre: Vector2) -> void:
	var blot := Color(0.13, 0.11, 0.20, 0.94)
	page.draw_circle(centre + Vector2(-4, -6), 27.0, blot)
	page.draw_circle(centre + Vector2(12, 2), 23.0, blot)
	page.draw_circle(centre + Vector2(-10, 12), 19.0, blot)
	page.draw_circle(centre + Vector2(6, -20), 14.0, blot)
	# Dribbles running down the page.
	page.draw_line(centre + Vector2(9, 18), centre + Vector2(13, 44), blot, 5.0)
	page.draw_circle(centre + Vector2(13, 46), 4.0, blot)
	page.draw_line(centre + Vector2(-14, 14), centre + Vector2(-17, 32), blot, 3.0)
	# A faint halo where the ink soaked into the fibres.
	page.draw_circle(centre + Vector2(0, 0), 34.0, Color(0.30, 0.25, 0.32, 0.22))
