extends CanvasLayer

## HUD chrome behaviors: the objectives list can be collapsed/expanded via
## its header button, its on-screen size follows the
## GameSettings.objectives_scale setting (adjustable in the pause menu),
## and [Tab] toggles the collected-notes panel (PlayerNotes entries).
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
	_emote_wheel = EmoteWheel.new()
	add_child(_emote_wheel)
	# Start folded: the header stays as a "▶ Objectives" tab in the corner
	# and the list unfolds on click, so the screen opens uncluttered.
	_set_collapsed(true, false)


var _emote_wheel: EmoteWheel


func _input(event: InputEvent) -> void:
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
## groups come first).
const ITEM_ICONS := {
	"fuses": "res://assets/ui/FuseIcon.png",
	"crowbars": "res://assets/ui/CrowbarIcon.png",
	"small_wrenches": "res://assets/ui/SmallWrenchIcon.svg",
	"big_wrenches": "res://assets/ui/WrenchIcon.svg",
	"will_items": "res://assets/ui/WillIcon.svg",
	"batteries": "res://assets/ui/BatteryIcon.svg",
	"prisms": "res://assets/ui/PrismIcon.svg",
}
var _icon_cache := {}
var _carry_panel: PanelContainer
var _carry_icon: TextureRect
var _carry_label: Label


func _icon_for(item: Node) -> Texture2D:
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
	for i in _inv_slots.size():
		var slot := _inv_slots[i]
		for child in slot.get_children():
			child.queue_free()
		slot.add_theme_stylebox_override("panel",
			_slot_style_selected if i == selected else _slot_style_normal)
		if i >= items.size() or not is_instance_valid(items[i]):
			slot.item_name = ""
			continue
		var item: Node = items[i]
		slot.item_name = str(item.get("display_name"))
		var icon_tex: Texture2D = _icon_for(item)
		var is_spent: bool = item.get("spent") == true
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
	# A small notepad tucked into the top-right corner; it grows downward
	# only as far as its entries need.
	_notes_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_notes_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_notes_panel.grow_vertical = Control.GROW_DIRECTION_END
	_notes_panel.offset_left = -300.0
	_notes_panel.offset_right = -16.0
	_notes_panel.offset_top = 16.0
	_notes_panel.offset_bottom = 60.0
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
	_notes_list = VBoxContainer.new()
	_notes_list.add_theme_constant_override("separation", 4)
	vbox.add_child(_notes_list)

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
		note.add_theme_font_size_override("font_size", 12)
		note.add_theme_color_override("font_color", Color(0.88, 0.84, 0.72))
		_notes_list.add_child(note)
