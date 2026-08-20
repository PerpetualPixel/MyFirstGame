class_name HUD
extends CanvasLayer

## HUD chrome behaviors: the objectives list can be collapsed/expanded via
## its header button, its on-screen size follows the
## GameSettings.objectives_scale setting (adjustable in the pause menu),
## and [Tab] toggles the collected-notes panel (PlayerNotes entries).
## Also owns the story chrome: the intro letter shown at run start and
## the queued radio-subtitle bar Mrs. Puddle speaks through (say()).
## Objective label text itself is managed by GameManager.

@onready var _objectives: VBoxContainer = $Objectives
@onready var _toggle: Button = $Objectives/ToggleButton

var _collapsed := false
var _notes_panel: PanelContainer
var _notes_list: VBoxContainer
var _inv_slots: Array[InventorySlot] = []
var _inv_signature := ""
var _slot_style_normal: StyleBoxFlat
var _slot_style_selected: StyleBoxFlat


func _ready() -> void:
	# Keep processing while paused: the pause menu's size slider should
	# update the list live behind the settings panel.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_toggle.pressed.connect(_on_toggle_pressed)
	_apply_scale(GameSettings.objectives_scale)
	_build_notes_panel()
	_build_inventory_bar()
	_build_dialogue_bar()
	_build_intro()
	_emote_wheel = EmoteWheel.new()
	add_child(_emote_wheel)
	# Start folded: the header stays as a "▶ Objectives" tab in the corner
	# and the list unfolds on click, so the screen opens uncluttered.
	_set_collapsed(true, false)
	show_intro()


var _emote_wheel: EmoteWheel


func _input(event: InputEvent) -> void:
	# The intro letter eats the HUD's own shortcuts until dismissed;
	# movement keys still pass through (nothing to reach on the porch yet).
	if _intro_open:
		# A wheel notch is a "pressed" mouse button too, and the wheel is
		# the camera zoom - it must not throw the letter away unread.
		var clicked: bool = event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]
		var dismiss: bool = event.is_action_pressed("interact") \
			or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE) \
			or clicked
		if dismiss:
			dismiss_intro()
			get_viewport().set_input_as_handled()
		return
	# Once the run has ended the HUD's own shortcuts are dead. The
	# victory cinematic deliberately leaves the tree UNPAUSED (the
	# character has to keep animating), so `paused` no longer gates
	# them the way it did before the cinematic existed.
	if _run_over:
		return
	# Hold the emote key for the wheel; release plays the highlighted one.
	# Never over a minigame panel (co-op panels don't pause the tree).
	if event.is_action_pressed("emote"):
		var local := _local_player()
		var busy := not get_tree().get_nodes_in_group("modal_ui").is_empty()
		if local != null and not get_tree().paused and not busy:
			_emote_wheel.open(local)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_released("emote") and _emote_wheel.is_open:
		_emote_wheel.close(true)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("notes"):
		_notes_panel.visible = not _notes_panel.visible
		_notes_hint.visible = not _notes_panel.visible
		if _notes_panel.visible:
			_refresh_notes()
		AudioSynthesizer.play_ui("tick", -16.0, 1.1)
		get_viewport().set_input_as_handled()


## Polled (not signaled): GameSettings is a static class, and the pause
## menu can change the scale at any time while the tree is paused.
func _process(_delta: float) -> void:
	if _objectives.scale.x != GameSettings.objectives_scale:
		_apply_scale(GameSettings.objectives_scale)
	_refresh_inventory_bar()


func _on_toggle_pressed() -> void:
	_set_collapsed(not _collapsed, true)


func _set_collapsed(collapsed: bool, click: bool) -> void:
	_collapsed = collapsed
	for child in _objectives.get_children():
		if child is Label:
			child.visible = not _collapsed
	_toggle.text = "▶ Objectives" if _collapsed else "▼ Objectives"
	if click:
		AudioSynthesizer.play_ui("tick", -14.0, 1.4)


func _apply_scale(value: float) -> void:
	# Scales from the list's top-left corner, so it stays anchored on screen.
	_objectives.scale = Vector2(value, value)


# --- Inventory bar (3 pack slots, bottom-left) -----------------------------


## Item group -> icon. Every pickup in the estate has one; the first
## matching group wins (the wrenches share "wrenches", so their specific
## groups come first). These are RENDERED FROM THE ITEMS' OWN 3D MODELS
## by tools/render_item_icons.gd, so a slot can never show a picture of
## something other than what was picked up — re-run it after changing a
## pickup's look. The pendants entry is the default; _icon_for swaps in
## the sky-mark actually being carried.
const ITEM_ICONS := {
	"fuses": "res://assets/ui/items/fuse.png",
	"crowbars": "res://assets/ui/items/crowbar.png",
	"small_wrenches": "res://assets/ui/items/small_wrench.png",
	"big_wrenches": "res://assets/ui/items/brass_wrench.png",
	"will_items": "res://assets/ui/items/will.png",
	"batteries": "res://assets/ui/items/battery.png",
	"prisms": "res://assets/ui/items/prism.png",
	"pendants": "res://assets/ui/items/pendant_moon.png",
}
var _icon_cache := {}
var _inv_bar: HBoxContainer
## Armed when the run ends (win or loss): retires the HUD's own
## shortcuts and silences queued radio chatter so the end screen
## keeps the screen to itself.
var _run_over := false
var _carry_panel: PanelContainer
var _carry_icon: TextureRect
var _carry_label: Label


## Victory cinematic: sweep the gameplay chrome off the screen so only
## the character (and then the rank card) is in frame. One-way — the
## restart reload rebuilds everything.
func hide_gameplay_chrome() -> void:
	end_run_chrome()
	_objectives.visible = false
	_notes_panel.visible = false
	_notes_hint.visible = false
	if _inv_bar:
		_inv_bar.visible = false


func _icon_for(item: Node) -> Texture2D:
	# Pendants all share a group but not a face.
	if item is AstralPendant:
		var pend := "res://assets/ui/items/pendant_%s.png" % (item as AstralPendant).pendant_symbol
		if not _icon_cache.has(pend):
			_icon_cache[pend] = load(pend) if ResourceLoader.exists(pend) else null
		if _icon_cache[pend] != null:
			return _icon_cache[pend]
	for group in ITEM_ICONS:
		if item.is_in_group(group):
			var path: String = ITEM_ICONS[group]
			if not _icon_cache.has(path):
				_icon_cache[path] = load(path) if ResourceLoader.exists(path) else null
			return _icon_cache[path]
	return null


func _build_inventory_bar() -> void:
	_slot_style_normal = StyleBoxFlat.new()
	_slot_style_normal.bg_color = Color(0.06, 0.05, 0.04, 0.8)
	_slot_style_normal.border_color = Color(0.5, 0.4, 0.2, 0.8)
	_slot_style_normal.set_border_width_all(2)
	_slot_style_normal.set_corner_radius_all(6)
	_slot_style_selected = _slot_style_normal.duplicate() as StyleBoxFlat
	_slot_style_selected.border_color = Color(1.0, 0.85, 0.4)
	_slot_style_selected.set_border_width_all(3)
	_slot_style_selected.bg_color = Color(0.12, 0.1, 0.06, 0.9)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bar.offset_left = 16.0
	bar.offset_top = -92.0
	bar.offset_bottom = -16.0
	add_child(bar)
	_inv_bar = bar
	for i in 3:
		var slot := InventorySlot.new()
		slot.slot_index = i
		slot.add_theme_stylebox_override("panel", _slot_style_normal)
		slot.custom_minimum_size = Vector2(76, 76)
		slot.slot_clicked.connect(_on_slot_clicked)
		slot.swap_requested.connect(_on_slot_swap)
		slot.drop_to_world.connect(_on_slot_drop_to_world)
		bar.add_child(slot)
		_inv_slots.append(slot)

	# "In hand" panel beside the pack: the two-hand load being carried
	# (the Heavy Battery), with its icon. Hidden when hands are free.
	_carry_panel = PanelContainer.new()
	var carry_style := _slot_style_normal.duplicate() as StyleBoxFlat
	carry_style.border_color = Color(0.35, 0.85, 1.0, 0.9)
	_carry_panel.add_theme_stylebox_override("panel", carry_style)
	_carry_panel.custom_minimum_size = Vector2(150, 76)
	_carry_panel.visible = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_carry_panel.add_child(row)
	_carry_icon = TextureRect.new()
	_carry_icon.custom_minimum_size = Vector2(60, 60)
	_carry_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_carry_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_carry_icon)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	var head := Label.new()
	head.text = "IN HAND"
	head.add_theme_font_size_override("font_size", 11)
	head.add_theme_color_override("font_color", Color(0.35, 0.85, 1.0))
	col.add_child(head)
	_carry_label = Label.new()
	_carry_label.add_theme_font_size_override("font_size", 12)
	_carry_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	_carry_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_carry_label.custom_minimum_size = Vector2(76, 0)
	col.add_child(_carry_label)
	var hint := Label.new()
	hint.text = "[G] set down"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.6, 0.55, 0.45))
	col.add_child(hint)
	bar.add_child(_carry_panel)


func _local_player() -> Node:
	for player in get_tree().get_nodes_in_group("players"):
		if player.is_local_player():
			return player
	return null


func _on_slot_clicked(index: int) -> void:
	var local := _local_player()
	if local == null:
		return
	if index < local.inventory.size():
		local.selected_slot = -1 if local.selected_slot == index else index
		_inv_signature = ""  # force refresh


func _on_slot_swap(from_index: int, to_index: int) -> void:
	var local := _local_player()
	if local:
		local.request_swap(from_index, to_index)


func _on_slot_drop_to_world(index: int) -> void:
	var local := _local_player()
	if local:
		local.request_drop(index)


func _refresh_inventory_bar() -> void:
	var local := _local_player()
	if local == null or local.get("inventory") == null:
		return
	var items: Array = local.inventory
	var selected: int = local.get("selected_slot")
	var carried: Node = local.get("carried_item")
	var signature := "%d|" % selected
	for item in items:
		if is_instance_valid(item):
			signature += item.name + ("!" if item.get("spent") else "") + ";"
	signature += "|carry:" + (carried.name if carried != null and is_instance_valid(carried) else "-")
	if signature == _inv_signature:
		return
	_inv_signature = signature
	if _carry_panel != null:
		var show := carried != null and is_instance_valid(carried)
		_carry_panel.visible = show
		if show:
			_carry_icon.texture = _icon_for(carried)
			_carry_label.text = str(carried.get("display_name"))
			_carry_panel.tooltip_text = str(carried.get("display_name"))
	for i in _inv_slots.size():
		var slot := _inv_slots[i]
		for child in slot.get_children():
			child.queue_free()
		slot.add_theme_stylebox_override("panel",
			_slot_style_selected if i == selected else _slot_style_normal)
		if i >= items.size() or not is_instance_valid(items[i]):
			slot.item_name = ""
			slot.tooltip_text = ""
			continue
		var item: Node = items[i]
		slot.item_name = str(item.get("display_name"))
		var icon_tex: Texture2D = _icon_for(item)
		var is_spent: bool = item.get("spent") == true
		# Hovering a slot names the thing in it, and says so when its
		# job is done (the slot also gets a red cross, below).
		slot.tooltip_text = ("%s — used up, safe to drop" % slot.item_name) if is_spent else slot.item_name
		if icon_tex != null:
			var icon := TextureRect.new()
			icon.texture = icon_tex
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if is_spent:
				icon.modulate = Color(1, 1, 1, 0.4)
			_inv_slots[i].add_child(icon)
		else:
			var tag := Label.new()
			tag.text = slot.item_name
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			tag.autowrap_mode = TextServer.AUTOWRAP_WORD
			tag.add_theme_font_size_override("font_size", 12)
			tag.add_theme_color_override("font_color",
				Color(0.6, 0.55, 0.45) if is_spent else Color(0.9, 0.85, 0.7))
			tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_inv_slots[i].add_child(tag)
		if is_spent:
			# Big red cross over the slot: this item's job is done.
			var cross := Label.new()
			cross.text = "✕"
			cross.set_anchors_preset(Control.PRESET_FULL_RECT)
			cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			cross.add_theme_font_size_override("font_size", 52)
			cross.add_theme_color_override("font_color", Color(0.9, 0.2, 0.15, 0.85))
			cross.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
			cross.add_theme_constant_override("outline_size", 4)
			cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_inv_slots[i].add_child(cross)


# --- Notes panel ([Tab]) ---------------------------------------------------


func _build_notes_panel() -> void:
	_notes_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.065, 0.045, 0.94)
	style.border_color = Color(0.55, 0.42, 0.18)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 10.0
	_notes_panel.add_theme_stylebox_override("panel", style)
	# A notepad page in the top-right corner: fixed height with its
	# entries scrolling, so the inventor's longer musings never run off
	# the bottom of the screen.
	_notes_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_notes_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_notes_panel.grow_vertical = Control.GROW_DIRECTION_END
	_notes_panel.offset_left = -348.0
	_notes_panel.offset_right = -16.0
	_notes_panel.offset_top = 16.0
	_notes_panel.offset_bottom = 496.0
	_notes_panel.visible = false
	add_child(_notes_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	_notes_panel.add_child(vbox)
	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.text = "Notes"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.9, 0.78, 0.5))
	header.add_child(title)
	var close_hint := Label.new()
	close_hint.text = "[Tab] close"
	close_hint.add_theme_font_size_override("font_size", 11)
	close_hint.add_theme_color_override("font_color", Color(0.65, 0.58, 0.45))
	header.add_child(close_hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_notes_list = VBoxContainer.new()
	_notes_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notes_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_notes_list)

	# Small standing hint in the same corner while the pad is closed.
	_notes_hint = Label.new()
	_notes_hint.text = "[Tab] Notes"
	_notes_hint.add_theme_font_size_override("font_size", 12)
	_notes_hint.add_theme_color_override("font_color", Color(0.85, 0.75, 0.5, 0.85))
	_notes_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_notes_hint.add_theme_constant_override("outline_size", 4)
	_notes_hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_notes_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_notes_hint.offset_left = -120.0
	_notes_hint.offset_right = -16.0
	_notes_hint.offset_top = 16.0
	_notes_hint.offset_bottom = 36.0
	_notes_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_notes_hint)


var _notes_hint: Label


func _refresh_notes() -> void:
	for child in _notes_list.get_children():
		child.queue_free()
	if PlayerNotes.entries.is_empty():
		var empty := Label.new()
		empty.text = "Nothing written down yet."
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
		_notes_list.add_child(empty)
		return
	for entry in PlayerNotes.entries:
		var note := Label.new()
		note.text = "• " + entry
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		note.add_theme_font_size_override("font_size", 12)
		note.add_theme_color_override("font_color", Color(0.88, 0.84, 0.72))
		_notes_list.add_child(note)


# --- Radio subtitle bar (Mrs. Puddle) --------------------------------------


var _dialogue_box: PanelContainer
var _dialogue_label: Label
var _dialogue_queue: Array[String] = []
var _dialogue_busy := false
var _dialogue_tween: Tween


## The run is over: the end screen owns the screen from here. Drops
## queued radio chatter so it can't talk over the rank card or the
## defeat text, and retires [Tab]/the emote wheel — the win path
## leaves the tree unpaused, so nothing else would stop them.
func end_run_chrome() -> void:
	_run_over = true
	_dialogue_queue.clear()
	if _dialogue_tween:
		_dialogue_tween.kill()
	_dialogue_busy = false
	_dialogue_box.visible = false


func _build_dialogue_bar() -> void:
	_dialogue_box = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.045, 0.035, 0.82)
	style.border_color = Color(0.55, 0.42, 0.18, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 8.0
	_dialogue_box.add_theme_stylebox_override("panel", style)
	_dialogue_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_dialogue_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dialogue_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_dialogue_box.offset_bottom = -108.0
	_dialogue_box.visible = false
	_dialogue_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dialogue_box)
	_dialogue_label = Label.new()
	_dialogue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialogue_label.custom_minimum_size = Vector2(560, 0)
	_dialogue_label.add_theme_font_size_override("font_size", 17)
	_dialogue_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.72))
	_dialogue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_box.add_child(_dialogue_label)


## Queue a radio line from Mrs. Puddle. Lines play one after another (a
## short hold scaled to length), never clobbering each other the way the
## milestone banner does.
func say(line: String) -> void:
	if _run_over:
		return
	_dialogue_queue.append(line)
	if not _dialogue_busy:
		_advance_dialogue()


func _advance_dialogue() -> void:
	if _dialogue_queue.is_empty():
		_dialogue_busy = false
		_dialogue_box.visible = false
		return
	_dialogue_busy = true
	var line: String = _dialogue_queue.pop_front()
	_dialogue_label.text = "MRS. PUDDLE — “%s”" % line
	AudioSynthesizer.play_ui("radio", -14.0)
	_dialogue_box.modulate.a = 0.0
	_dialogue_box.visible = true
	var hold := 2.0 + line.length() * 0.04
	_dialogue_tween = create_tween()
	_dialogue_tween.tween_property(_dialogue_box, "modulate:a", 1.0, 0.22)
	_dialogue_tween.tween_interval(hold)
	_dialogue_tween.tween_property(_dialogue_box, "modulate:a", 0.0, 0.45)
	_dialogue_tween.tween_callback(_advance_dialogue)


# --- Intro letter (run start) ----------------------------------------------


var _intro_layer: Control
var _intro_open := false


func _build_intro() -> void:
	_intro_layer = Control.new()
	_intro_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_layer.visible = false
	add_child(_intro_layer)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.025, 0.02, 0.72)
	_intro_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_layer.add_child(center)
	var page := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.07, 0.97)
	style.border_color = Color(0.62, 0.47, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 34.0
	style.content_margin_right = 34.0
	style.content_margin_top = 24.0
	style.content_margin_bottom = 24.0
	page.add_theme_stylebox_override("panel", style)
	center.add_child(page)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	page.add_child(vbox)
	var title := Label.new()
	title.text = Story.INTRO_TITLE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
	vbox.add_child(title)
	var body := Label.new()
	body.text = Story.INTRO_TEXT
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(620, 0)
	body.add_theme_font_size_override("font_size", 16)
	body.add_theme_color_override("font_color", Color(0.9, 0.86, 0.74))
	vbox.add_child(body)
	var hint := Label.new()
	hint.text = Story.INTRO_HINT
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.7, 0.62, 0.45))
	vbox.add_child(hint)


func show_intro() -> void:
	_intro_open = true
	_intro_layer.visible = true
	# Same busy-gate the minigames use: suppresses the emote wheel and
	# tells the pause menu someone else owns the screen.
	_intro_layer.add_to_group("modal_ui")


func dismiss_intro() -> void:
	if not _intro_open:
		return
	_intro_open = false
	_intro_layer.visible = false
	_intro_layer.remove_from_group("modal_ui")
	AudioSynthesizer.play_ui("tick", -12.0, 0.9)
	say(Story.RADIO["run_start"])
