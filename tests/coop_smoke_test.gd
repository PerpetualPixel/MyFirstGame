extends SceneTree
## Co-op smoke test (single process, host with no client yet):
## with an active ENet server and a shared seed, Main must spawn the host
## player as "Players/1" with authority, the seed must drive generation,
## RPC-routed interaction and pings must work call_local, and restart via
## the host path must be accepted. Also checks juice hooks: camera shake,
## banner, and safe item drop.
## Run: godot --headless --path . --script res://tests/coop_smoke_test.gd

func _initialize() -> void:
	_run()


func _run() -> void:
	# The root MultiplayerAPI is not ready during _initialize; wait a frame.
	await process_frame
	# Watchdog: never hang the CI run.
	create_timer(90.0).timeout.connect(func() -> void:
		print("TEST FAIL: watchdog timeout")
		quit(1))
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(8910, 2) != OK:
		print("TEST FAIL: could not open ENet server")
		quit(1)
		return
	root.multiplayer.multiplayer_peer = peer
	NetworkSession.multiplayer_active = true
	NetworkSession.run_seed = 424242

	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 40:
		await physics_frame

	var players: Node3D = main.get_node("Players")
	if players.get_child_count() != 1 or players.get_child(0).name != &"1":
		print("TEST FAIL: host player not spawned as Players/1")
		quit(1)
		return
	var player: Player = players.get_child(0)
	if not player.is_multiplayer_authority() or not player.is_local_player():
		print("TEST FAIL: host player authority wrong")
		quit(1)
		return

	# Seed determinism: a bare generator with the same generation_seed must
	# draw the identical layout the shared run seed produced.
	var gen: MansionGenerator = main.get_node("MansionGenerator")
	var twin := MansionGenerator.new()
	twin.generation_seed = 424242
	NetworkSession.run_seed = 0  # ensure the twin uses generation_seed only
	root.add_child(twin)
	await physics_frame
	if twin.active_route["name"] != gen.active_route["name"] \
			or str(twin._valve_cells) != str(gen._valve_cells) \
			or str(twin._gear_cells) != str(gen._gear_cells):
		print("TEST FAIL: shared seed did not reproduce the layout")
		quit(1)
		return
	twin.queue_free()
	NetworkSession.run_seed = 424242
	print("shared-seed generation OK")

	# RPC-routed interaction (call_local path): open a door via the same
	# entry point the input handler uses.
	var test_door: Door = null
	for door in _find_all(main, "Door"):
		if not door.locked:
			test_door = door
			break
	player.request_interact(test_door)
	await physics_frame
	if not test_door.is_open:
		print("TEST FAIL: RPC-routed interact did not open the door")
		quit(1)
		return
	print("net interact OK")

	# Ping beacon spawns and cleans up.
	player._net_ping(player.global_position + Vector3(0, 0, -2))
	await physics_frame
	var found_beacon := false
	for child in root.get_children():
		if _has_ping_label(child):
			found_beacon = true
	if not found_beacon:
		print("TEST FAIL: ping beacon did not spawn")
		quit(1)
		return
	print("ping OK")

	# Juice hooks: shake accumulates trauma; banner animates in.
	Player.shake(0.5, player.global_position)
	if player._trauma <= 0.0:
		print("TEST FAIL: camera shake did not register")
		quit(1)
		return
	var gm: GameManager = main.get_node("GameManager")
	gm.show_banner("TEST BANNER")
	await physics_frame
	if gm._banner.text != "TEST BANNER":
		print("TEST FAIL: banner did not display")
		quit(1)
		return
	print("shake + banner OK")

	# Safe drop: carry the cog to a wall corner and drop — it must end up
	# above a floor, not inside geometry or the void. The cog is a
	# test-only prop now, spawned here on the porch.
	var cog: Grabbable = (load("res://scenes/BrassCog.tscn") as PackedScene).instantiate()
	cog.name = "BrassCog"
	cog.position = Vector3(2, 0.6, 10)
	main.add_child(cog)
	for i in 20:
		await physics_frame
	player.teleport(cog.global_position + Vector3(0, 0, 1.0))
	for i in 10:
		await physics_frame
	player.pick_up(cog)
	player.teleport(Vector3(0, 0.1, 5.6))  # nose against the foyer's north wall
	for i in 5:
		await physics_frame
	player._net_drop()
	for i in 40:
		await physics_frame
	var cog_pos := cog.global_position
	if cog_pos.y < -1.0 or cog_pos.y > 2.0:
		print("TEST FAIL: dropped item ended up out of bounds (%s)" % cog_pos)
		quit(1)
		return
	print("safe drop OK (cog at %s)" % cog_pos)

	# Host restart path must be accepted (we don't follow the reload here).
	if not gm._is_verdict_authority():
		print("TEST FAIL: host is not the verdict authority")
		quit(1)
		return

	NetworkSession.reset()
	root.multiplayer.multiplayer_peer = null
	print("TEST PASS: co-op smoke (host authority, seed, rpc, ping, juice)")
	quit(0)


func _has_ping_label(node: Node) -> bool:
	if node is Label3D and "pinged" in str((node as Label3D).text):
		return true
	for child in node.get_children():
		if _has_ping_label(child):
			return true
	return false


func _find_all(node: Node, klass: String) -> Array:
	var found: Array = []
	for child in node.get_children():
		if child.get_script() != null and child.get_script().get_global_name() == klass:
			found.append(child)
		found.append_array(_find_all(child, klass))
	return found
