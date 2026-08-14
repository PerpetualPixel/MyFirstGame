extends SceneTree
## Headless end-to-end test of the deepened game loop:
## 8-wire breaker (clue consistency, wrong wiring inert, solve powers &
## starts timer) -> free-angle mirror swivel & detent snap -> clockwork
## gear puzzle (wrong gear fails, correct set runs the clock and releases
## the wrench) -> valves (bare hands rejected, decay, sync-lock) -> laser
## maze -> Will to the porch exit -> WIN. Plus pause menu checks.
## Run: godot --headless --path . --script res://tests/game_loop_test.gd

func _initialize() -> void:
	_run()


func _run() -> void:
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 30:
		await physics_frame

	var gen: MansionGenerator = main.get_node("MansionGenerator")
	var route: Dictionary = gen.active_route
	print("run layout: route=%s valves=%s clock=%s gears=%s" % [route["name"], gen._valve_cells, gen._clock_cell, gen._gear_cells])
	var player: Player = main.get_node("Players/1")
	var gm: GameManager = main.get_node("GameManager")
	var pause_menu: PauseMenu = main.get_node("PauseMenu")
	var mirrors := _find_all(main, "RotatingMirror")
	var valves := _find_all(main, "SteamValve")
	var vault_doors := _find_all(main, "VaultDoor")
	var hinged := _find_all(main, "Door")
	var breakers := _find_all(main, "BreakerBox")
	var clocks := _find_all(main, "ClockworkMechanism")
	var gears := get_nodes_in_group("clock_gears")
	print("found: %d mirrors, %d valves, %d vault doors, %d hinged, %d breakers, %d clocks, %d gears" % [
		mirrors.size(), valves.size(), vault_doors.size(), hinged.size(), breakers.size(), clocks.size(), gears.size()])
	if mirrors.size() != 5 or valves.size() != 2 or vault_doors.size() != 1 or breakers.size() != 1 \
			or clocks.size() != 1 or gears.size() != 3 or hinged.size() < 5:
		print("TEST FAIL: unexpected element counts")
		quit(1)
		return
	var vault_door: VaultDoor = vault_doors[0]
	var breaker: BreakerBox = breakers[0]
	var minigame: WiringMinigame = breaker.minigame
	var clock: ClockworkMechanism = clocks[0]

	# --- PREGAME: frozen timer ---
	for i in 60:
		await physics_frame
	if gm.state != GameManager.State.PREGAME or gm.time_left < gm.run_time:
		print("TEST FAIL: timer ticked during PREGAME")
		quit(1)
		return

	# --- 8-wire board: sanity + clue consistency against ground truth ---
	if minigame._mapping.size() != 8 or minigame._clues.size() < 6:
		print("TEST FAIL: expected 8 wires and clue set (got %d wires, %d clues)" % [minigame._mapping.size(), minigame._clues.size()])
		quit(1)
		return
	for clue in minigame._clues:
		if not WiringMinigame.clue_holds(clue, minigame._mapping):
			print("TEST FAIL: generated clue inconsistent with mapping: %s" % clue["text"])
			quit(1)
			return
	print("8-wire clue set consistent")

	# --- ESC closes the minigame, not the pause menu ---
	breaker.interact(player)
	await process_frame
	if not minigame.is_open or not paused:
		print("TEST FAIL: minigame did not open/pause")
		quit(1)
		return
	_press_escape()
	await process_frame
	await process_frame
	if minigame.is_open or pause_menu.is_open or paused:
		print("TEST FAIL: ESC priority wrong")
		quit(1)
		return

	# --- Wrong wiring inert; correct wiring powers the mansion ---
	breaker.interact(player)
	await process_frame
	var names: Array = minigame._mapping.keys()
	for wire_name in names:
		minigame.connect_wire(wire_name, (minigame._mapping[wire_name] + 1) % 8)
	await process_frame
	if minigame.is_solved or breaker.is_powered:
		print("TEST FAIL: wrong wiring completed the circuit")
		quit(1)
		return
	for wire_name in names:
		minigame.connect_wire(wire_name, minigame._mapping[wire_name])
	for i in 90:
		await physics_frame
	if not (minigame.is_solved and breaker.is_powered and not paused and gm.state == GameManager.State.PLAYING):
		print("TEST FAIL: correct wiring did not power/start the run")
		quit(1)
		return

	# --- Free-angle swivel: adjust moves smoothly, release snaps to 15° ---
	var swivel := _mirror_near(mirrors, route["mirrors"][0])
	var before := swivel.rotation.y
	swivel.adjust(1.0, 0.2)  # 12 degrees of hold-swivel
	if absf(swivel.rotation.y - before) < 0.15:
		print("TEST FAIL: adjust() did not swivel the mirror")
		quit(1)
		return
	swivel.end_adjust()
	for i in 20:
		await physics_frame
	var detent := wrapf(rad_to_deg(swivel.rotation.y), 0.0, 360.0)
	var remainder := fmod(detent, 15.0)
	if remainder > 0.5 and remainder < 14.5:
		print("TEST FAIL: end_adjust did not snap to a 15-degree detent (%f)" % detent)
		quit(1)
		return
	print("free-angle swivel + detent snap OK")

	# --- Clockwork: wrong gear fails, correct set releases the wrench ---
	var wrench: Grabbable = get_nodes_in_group("wrenches")[0]
	if wrench.collision_layer != 0 or wrench.get_parent() != clock:
		print("TEST FAIL: wrench not stashed inside the clock")
		quit(1)
		return
	var gear_by_teeth := {}
	for gear in gears:
		gear_by_teeth[int(gear.get_meta("teeth"))] = gear
	var sockets: Array = clock._sockets

	# Seat the 12-tooth gear in the 8-tooth socket: clock must stay dead.
	var socket8: GearSocket = null
	for s in sockets:
		if s.required_teeth == 8:
			socket8 = s
	player.teleport(gear_by_teeth[12].global_position + Vector3(0, 0, 1.0))
	for i in 10:
		await physics_frame
	player.pick_up(gear_by_teeth[12])
	socket8.interact(player)
	if clock.is_running or socket8.gear != gear_by_teeth[12] or player.held_item != null:
		print("TEST FAIL: wrong-gear insertion behaved unexpectedly")
		quit(1)
		return
	socket8.interact(player)  # pop it back out
	for i in 20:
		await physics_frame
	if socket8.gear != null:
		print("TEST FAIL: could not remove a seated gear")
		quit(1)
		return

	# Correct arrangement.
	for s in sockets:
		var gear: Grabbable = gear_by_teeth[s.required_teeth]
		player.teleport(gear.global_position + Vector3(0, 0, 1.0))
		for i in 10:
			await physics_frame
		player.pick_up(gear)
		if player.held_item != gear:
			print("TEST FAIL: could not pick up %s" % gear.display_name)
			quit(1)
			return
		s.interact(player)
	if not clock.is_running:
		print("TEST FAIL: clock did not start with correct gears")
		quit(1)
		return
	for i in 120:
		await physics_frame
	if wrench.collision_layer == 0 or wrench.get_parent() == clock:
		print("TEST FAIL: compartment did not release the wrench")
		quit(1)
		return
	print("clockwork gear puzzle OK")

	# --- Pause menu freezes the clock ---
	pause_menu.open_menu()
	await process_frame
	var t0: float = gm.time_left
	for i in 30:
		await process_frame
	if gm.time_left < t0 - 0.05 or not paused:
		print("TEST FAIL: pause menu did not freeze the run")
		quit(1)
		return
	pause_menu.resume()
	await process_frame

	# --- Laser maze ---
	for door in hinged:
		door.set_open(true)
	# Align this run's route to its published solution angles.
	for i in route["mirrors"].size():
		_mirror_near(mirrors, route["mirrors"][i]).rotation.y = deg_to_rad(route["solutions"][i])
	for i in 90:
		await physics_frame
	if not gm._light_done:
		print("TEST FAIL: laser maze not solved at 45-degree alignment")
		quit(1)
		return

	# --- Valves: bare hands rejected, decay, then sync-lock ---
	var valve_a: SteamValve = valves[0]
	var valve_b: SteamValve = valves[1]
	valve_a.interact(player)
	if valve_a.activated:
		print("TEST FAIL: valve turned without the wrench")
		quit(1)
		return
	player.teleport(wrench.global_position + Vector3(0, 0, 1.0))
	for i in 10:
		await physics_frame
	player.pick_up(wrench)
	if player.held_item != wrench:
		print("TEST FAIL: could not pick up the released wrench")
		quit(1)
		return
	valve_a.decay_time = 1.0
	valve_a.interact(player)
	for i in 160:
		await physics_frame
	if valve_a.activated:
		print("TEST FAIL: lone valve did not decay and reset")
		quit(1)
		return
	print("valve decay/reset OK")
	valve_a.decay_time = 60.0
	valve_b.decay_time = 60.0
	valve_a.interact(player)
	valve_b.interact(player)
	for i in 120:
		await physics_frame
	if not (valve_a.locked_open and valve_b.locked_open and vault_door.is_open):
		print("TEST FAIL: valves/vault door state wrong after sync")
		quit(1)
		return

	# --- Will to the porch exit ---
	player.drop_held()
	var will: Grabbable = get_nodes_in_group("will_items")[0]
	player.teleport(will.global_position + Vector3(0, 0, 1.0))
	for i in 10:
		await physics_frame
	player.pick_up(will)
	if player.held_item != will:
		print("TEST FAIL: could not pick up the Will")
		quit(1)
		return
	player.teleport(Vector3(0, 0.1, 16.5))
	for i in 30:
		await physics_frame
	if gm.state != GameManager.State.WON or not paused:
		print("TEST FAIL: not WON at porch exit (state=%d)" % gm.state)
		quit(1)
		return
	paused = false
	print("victory subtitle: ", main.get_node("HUD/EndScreen/Center/VBox/Subtitle").text)
	print("TEST PASS: deepened game loop end-to-end")
	quit(0)


func _press_escape() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)


func _mirror_near(mirrors: Array, pos: Vector3) -> RotatingMirror:
	for m in mirrors:
		if m.global_position.distance_to(pos) < 1.0:
			return m
	return null


func _find_all(node: Node, klass: String) -> Array:
	var found: Array = []
	for child in node.get_children():
		if child.get_script() != null and child.get_script().get_global_name() == klass:
			found.append(child)
		found.append_array(_find_all(child, klass))
	return found
