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
var _fuse_icon: Texture2D
var _crowbar_icon: Texture2D
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


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("notes"):
		_notes_panel.visible = not _notes_panel.visible
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
	_collapsed = not _collapsed
	for child in _objectives.get_children():
		if child is Label:
			child.visible = not _collapsed
	_toggle.text = "▶ Objectives" if _collapsed else "▼ Objectives"
	AudioSynthesizer.play_ui("tick", -14.0, 1.4)


func _apply_scale(value: float) -> void:
	# Scales from the list's top-left corner, so it stays anchored on screen.
	_objectives.scale = Vector2(value, value)


# --- Inventory bar (3 pack slots, bottom-left) -----------------------------


func _build_inventory_bar() -> void:
	if ResourceLoader.exists("res://assets/ui/FuseIcon.png"):
		_fuse_icon = load("res://assets/ui/FuseIcon.png")
	if ResourceLoader.exists("res://assets/ui/CrowbarIcon.png"):
		_crowbar_icon = load("res://assets/ui/CrowbarIcon.png")
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
	var signature := "%d|" % selected
	for item in items:
		if is_instance_valid(item):
			signature += item.name + ("!" if item.get("spent") else "") + ";"
	if signature == _inv_signature:
		return
	_inv_signature = signature
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
		var icon_tex: Texture2D = null
		if item.is_in_group("fuses"):
			icon_tex = _fuse_icon
		elif item.is_in_group("crowbars"):
			icon_tex = _crowbar_icon
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
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 14.0
	_notes_panel.add_theme_stylebox_override("panel", style)
	_notes_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_notes_panel.offset_left = -420.0
	_notes_panel.offset_right = -24.0
	_notes_panel.offset_top = -160.0
	_notes_panel.offset_bottom = 160.0
	_notes_panel.visible = false
	add_child(_notes_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_notes_panel.add_child(vbox)
	var title := Label.new()
	title.text = "Notes                                    [Tab] close"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.78, 0.5))
	vbox.add_child(title)
	_notes_list = VBoxContainer.new()
	_notes_list.add_theme_constant_override("separation", 6)
	vbox.add_child(_notes_list)


func _refresh_notes() -> void:
	for child in _notes_list.get_children():
		child.queue_free()
	if PlayerNotes.entries.is_empty():
		var empty := Label.new()
		empty.text = "Nothing written down yet."
		empty.add_theme_font_size_override("font_size", 16)
		empty.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
		_notes_list.add_child(empty)
		return
	for entry in PlayerNotes.entries:
		var note := Label.new()
		note.text = "• " + entry
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_font_size_override("font_size", 16)
		note.add_theme_color_override("font_color", Color(0.88, 0.84, 0.72))
		_notes_list.add_child(note)
