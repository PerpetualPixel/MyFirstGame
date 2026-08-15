class_name InventorySlot
extends PanelContainer

## One HUD pack slot. Click (or press 1/2/3) to select it; drag onto a
## sibling slot to reorder the pack; drag anywhere else to drop the item
## into the world at the player's feet.

signal slot_clicked(index: int)
signal swap_requested(from_index: int, to_index: int)
signal drop_to_world(index: int)

var slot_index := 0
var item_name := ""

var _drag_started := false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		slot_clicked.emit(slot_index)


func _get_drag_data(_at: Vector2) -> Variant:
	if item_name.is_empty():
		return null
	_drag_started = true
	var preview := Label.new()
	preview.text = item_name
	preview.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	preview.add_theme_font_size_override("font_size", 14)
	set_drag_preview(preview)
	return {"inv_slot": slot_index}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("inv_slot") and int(data["inv_slot"]) != slot_index


func _drop_data(_at: Vector2, data: Variant) -> void:
	swap_requested.emit(int(data["inv_slot"]), slot_index)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _drag_started:
		_drag_started = false
		# Released outside every drop target: toss the item to the ground.
		if not is_drag_successful():
			drop_to_world.emit(slot_index)
