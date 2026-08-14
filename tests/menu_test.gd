extends SceneTree
## Main menu + lobby regression: menu loads with five styled buttons and an
## orbiting camera; the Lobby scene hosts a real ENet server on port 8910,
## enables Start for the host (solo allowed), and resets cleanly.
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
	menu.queue_free()
	await process_frame
	await process_frame

	# Lobby: hosting opens a live ENet server on 8910.
	NetworkSession.lobby_mode = "join"  # prevent auto-host; we drive it
	var lobby: Lobby = (load("res://scenes/Lobby.tscn") as PackedScene).instantiate()
	root.add_child(lobby)
	await process_frame
	lobby.host_game()
	await process_frame
	var status: String = lobby.get_node("Center/Panel/VBox/Status").text
	var start_btn: Button = lobby.get_node("Center/Panel/VBox/StartButton")
	if lobby.multiplayer.multiplayer_peer == null or not "Hosting" in status or start_btn.disabled:
		print("TEST FAIL: lobby host failed (status: '%s')" % status)
		quit(1)
		return
	lobby._reset_peer()
	if lobby.multiplayer.multiplayer_peer != null:
		print("TEST FAIL: lobby did not reset its peer")
		quit(1)
		return

	print("TEST PASS: menu and lobby OK")
	quit(0)
