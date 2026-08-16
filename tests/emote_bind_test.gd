extends SceneTree
## Emote wheel + key rebinding regression: every animation source file
## registers a clip, the wheel offers the dances, emoting plays and is
## cancelled by walking, and rebinding an action swaps its key (freeing
## it from any other action) and rewrites the prompt tokens.
## Run: godot --headless --path . --script res://tests/emote_bind_test.gd

func _initialize() -> void:
	_run()


func _run() -> void:
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 30:
		await physics_frame
	var player: Player = main.get_node("Players/1")
	var hud: Node = main.get_node("HUD")

	# Every shipped animation source became a clip.
	for anim_name in Player.EXTRA_ANIM_SOURCES:
		var path: String = Player.EXTRA_ANIM_SOURCES[anim_name]["path"]
		if not ResourceLoader.exists(path):
			print("TEST FAIL: animation source missing: %s" % path)
			quit(1)
			return
		if not player._anim_player.has_animation("moves/%s" % anim_name):
			print("TEST FAIL: clip moves/%s did not register" % anim_name)
			quit(1)
			return

	# The wheel offers every dance emote.
	var emotes := player.available_emotes()
	if emotes.size() != Player.EMOTES.size():
		print("TEST FAIL: wheel offers %d of %d emotes" % [emotes.size(), Player.EMOTES.size()])
		quit(1)
		return

	# Emoting plays the clip; walking cancels it.
	player.teleport(Vector3(-20, 0.1, 30))
	for i in 10:
		await physics_frame
	player.request_emote(emotes[0][0])
	await physics_frame
	if player._emote_anim != emotes[0][0]:
		print("TEST FAIL: emote did not start")
		quit(1)
		return
	for i in 20:
		await physics_frame
	if player._anim_player.current_animation != emotes[0][0]:
		print("TEST FAIL: emote clip not playing (got %s)" % player._anim_player.current_animation)
		quit(1)
		return
	Input.action_press("move_up")
	for i in 30:
		await physics_frame
	Input.action_release("move_up")
	if not player._emote_anim.is_empty():
		print("TEST FAIL: walking did not cancel the emote")
		quit(1)
		return

	# The wheel opens on the local player and closes without a selection.
	var wheel: EmoteWheel = hud._emote_wheel
	wheel.open(player)
	if not wheel.is_open:
		print("TEST FAIL: emote wheel did not open")
		quit(1)
		return
	wheel.close(false)
	if wheel.is_open:
		print("TEST FAIL: emote wheel did not close")
		quit(1)
		return

	# --- Rebinding ---
	var default_interact := GameSettings.key_label("interact")
	if default_interact != "E":
		print("TEST FAIL: interact should default to E, got %s" % default_interact)
		quit(1)
		return
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_T
	GameSettings.rebind("interact", ev)
	if GameSettings.key_label("interact") != "T":
		print("TEST FAIL: rebind did not take (got %s)" % GameSettings.key_label("interact"))
		quit(1)
		return
	# Prompts follow the new key.
	var prompt := GameSettings.fmt("[E] Take Crowbar")
	if prompt != "[T] Take Crowbar":
		print("TEST FAIL: prompt not rewritten (got %s)" % prompt)
		quit(1)
		return
	# Binding a key already used by another action frees it there.
	var steal := InputEventKey.new()
	steal.physical_keycode = KEY_T
	GameSettings.rebind("drop", steal)
	if not InputMap.action_get_events("interact").is_empty():
		print("TEST FAIL: duplicate binding left on the old action")
		quit(1)
		return
	# A mouse button binds too.
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_MIDDLE
	GameSettings.rebind("emote", mouse)
	if GameSettings.key_label("emote") != "Mouse M":
		print("TEST FAIL: mouse rebind failed (got %s)" % GameSettings.key_label("emote"))
		quit(1)
		return
	# Reset restores the defaults.
	GameSettings.reset_bindings()
	if GameSettings.key_label("interact") != "E" or GameSettings.key_label("drop") != "G" \
			or GameSettings.key_label("emote") != "B":
		print("TEST FAIL: reset did not restore defaults (E/G/B)")
		quit(1)
		return
	print("TEST PASS: emote wheel and key rebinding")
	quit(0)
