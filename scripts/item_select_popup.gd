class_name ItemSelectPopup
extends CanvasLayer

## Tiny Resident Evil-style chooser: "use which carried item here?".
## Opened only on the local machine; the pick is routed back through the
## caller's replication path (e.g. GearSocket.request_seat).

static func open(items: Array, on_pick: Callable, title := "Use which item?") -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var popup := ItemSelectPopup.new()
	popup.layer = 15
	popup.process_mode = Node.PROCESS_MODE_ALWAYS

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.065, 0.045, 0.96)
	style.border_color = Color(0.55, 0.42, 0.18)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(260, 0)
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 20)
	heading.add_theme_color_override("font_color", Color(0.9, 0.78, 0.5))
	vbox.add_child(heading)

	for item in items:
		var b := Button.new()
		b.text = str(item.get("display_name"))
		b.custom_minimum_size = Vector2(0, 40)
		b.pressed.connect(func() -> void:
			popup.queue_free()
			on_pick.call(item))
		vbox.add_child(b)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(0, 36)
	cancel.pressed.connect(popup.queue_free)
	vbox.add_child(cancel)

	tree.root.add_child(popup)
