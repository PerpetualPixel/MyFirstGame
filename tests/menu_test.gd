extends SceneTree
## Main menu regression: scene loads, five styled buttons exist, the
## camera orbits, the LAN lobby opens a real ENet server and closes
## cleanly, modals switch exclusively, and the project boots to the menu.
## Run: godot --headless --path . --script res://tests/menu_test.gd

func _initialize() -> void:
	_run()


func _run() -> void:
	if str(ProjectSettings.get_setting("application/run/main_scene")) != "res://scenes/MainMenu.tscn":
		print("TEST FAIL: MainMenu.tscn is not the project main scene")
		quit(1)
		return

	var menu: MainMenu = (load("res://scenes/MainMenu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	for i in 10:
		await process_frame

	var buttons: VBoxContainer = menu.get_node("UI/Root/Buttons")
	if buttons.get_child_count() != 5:
		print("TEST FAIL: expected 5 menu buttons, got %d" % buttons.get_child_count())
		quit(1)
		return

	var pivot: Node3D = menu.get_node("CameraPivot")
	var yaw0: float = pivot.rotation.y
	for i in 30:
		await process_frame
	if absf(pivot.rotation.y - yaw0) < 0.001:
		print("TEST FAIL: cinematic camera is not orbiting")
		quit(1)
		return

	# LAN lobby: hosting must open a live ENet server.
	menu._open_host()
	await process_frame
	var host_modal: Control = menu.get_node("UI/Root/HostModal")
	var ip_text: String = menu.get_node("UI/Root/HostModal/Center/Panel/VBox/IPLabel").text
	if not host_modal.visible or menu.multiplayer.multiplayer_peer == null or not "Host address" in ip_text:
		print("TEST FAIL: host lobby did not open a server (label: '%s')" % ip_text)
		quit(1)
		return
	menu._close_host()
	if host_modal.visible or menu.multiplayer.multiplayer_peer != null:
		print("TEST FAIL: lobby did not close cleanly")
		quit(1)
		return

	# Modals are mutually exclusive.
	menu._open_modal(menu.get_node("UI/Root/JoinModal"))
	menu._open_modal(menu.get_node("UI/Root/ControlsModal"))
	if menu.get_node("UI/Root/JoinModal").visible or not menu.get_node("UI/Root/ControlsModal").visible:
		print("TEST FAIL: modal exclusivity broken")
		quit(1)
		return

	print("TEST PASS: main menu scene, lobby, and modals OK")
	quit(0)
