extends SceneTree
## Headless end-to-end test of the deepened game loop:
## crowbar/toy-crate gating -> two-fuse breaker (powers keypad, starts
## timer) -> keypad PIN opens the front doors (code from the junk-lot
## notebook) -> free-angle mirror swivel & detent snap -> clockwork
## gear puzzle (wrong gear fails, correct set runs the clock and releases
## the wrench) -> valves (bare hands rejected, decay, sync-lock) -> laser
## maze -> Will to the porch exit -> WIN. Plus pause menu checks.
## Run: godot --headless --path . --script res://tests/game_loop_test.gd

func _initialize() -> void:
	_run()


func _run() -> void:
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	# ROUTE_OVERRIDE env var (0-2) forces a laser route for full coverage;
	# must be set before add_child so generation in _ready sees it.
	var route_env := OS.get_environment("ROUTE_OVERRIDE")
	if route_env != "":
		main.get_node("MansionGenerator").route_override = int(route_env)
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
	if mirrors.size() != route["mirrors"].size() + 1 or valves.size() != 2 or vault_doors.size() != 1 \
			or breakers.size() != 1 or clocks.size() != 1 or gears.size() != 3 or hinged.size() < 5:
		print("TEST FAIL: unexpected element counts")
		quit(1)
		return
	var vault_door: VaultDoor = vault_doors[0]
	var breaker: BreakerBox = breakers[0]
	var minigame: FusePanel = breaker.minigame
	var clock: ClockworkMechanism = clocks[0]

	# --- PREGAME: frozen timer ---
	for i in 60:
		await physics_frame
	if gm.state != GameManager.State.PREGAME or gm.time_left < gm.run_time:
		print("TEST FAIL: timer ticked during PREGAME")
		quit(1)
		return

	# --- Garage gating: crowbar pries the side door; toy crate frees its fuse ---
	var toy_boxes := _find_all(main, "ToyBox")
	if get_nodes_in_group("crowbars").size() != 1 or get_nodes_in_group("fuses").size() != 2 \
			or toy_boxes.size() != 1:
		print("TEST FAIL: crowbar/fuse/toybox counts wrong")
		quit(1)
		return
	var tbox: ToyBox = toy_boxes[0]
	var fuse_a: RigidBody3D = tbox.stash
	if fuse_a == null or fuse_a.collision_layer != 0:
		print("TEST FAIL: fuse not stashed in the toy crate")
		quit(1)
		return
	tbox.interact(player)
	await physics_frame
	if not tbox.opened or fuse_a.collision_layer == 0:
		print("TEST FAIL: toy crate did not release its fuse")
		quit(1)
		return
	var side_door: Door = null
	for d in hinged:
		if d.name == "GarageSideDoor":
			side_door = d
	if side_door == null or not side_door.locked:
		print("TEST FAIL: garage side door missing or unlocked at spawn")
		quit(1)
		return
	side_door.interact(player)  # bare hands: stays jammed
	if side_door.is_open or not side_door.locked:
		print("TEST FAIL: garage door opened without the crowbar")
		quit(1)
		return
	var bar: Grabbable = get_nodes_in_group("crowbars")[0]
	player.teleport(bar.global_position + Vector3(0, 0, 1.0))
	for i in 10:
		await physics_frame
	player.pick_up(bar)
	side_door.interact(player)
	if side_door.locked or not side_door.is_open:
		print("TEST FAIL: crowbar did not pry the garage door open")
		quit(1)
		return
	if not bar.spent:
		print("TEST FAIL: crowbar not marked spent after the pry")
		quit(1)
		return
	player.drop_held()
	print("garage gating & toy crate OK")

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

	# --- Two fuses power the mansion; keypad PIN opens the front doors ---
	var keypad: Keypad = _find_all(main, "Keypad")[0]
	if keypad.powered:
		print("TEST FAIL: keypad live before power was restored")
		quit(1)
		return
	var fuse_b: Grabbable = null
	for f in get_nodes_in_group("fuses"):
		if f.name == "Fuse_B":
			fuse_b = f
	player.teleport(fuse_b.global_position + Vector3(0, 0, 1.0))
	for i in 10:
		await physics_frame
	player.pick_up(fuse_b)
	breaker.request_install(player)  # the panel's socket-click path
	await process_frame
	if breaker.is_powered or breaker.fuses_installed != 1 or not player.inventory.is_empty():
		print("TEST FAIL: first fuse install state wrong")
		quit(1)
		return
	var fuse_a_world: Grabbable = get_nodes_in_group("fuses")[0]
	player.teleport(fuse_a_world.global_position + Vector3(0, 0, 1.0))
	for i in 10:
		await physics_frame
	player.pick_up(fuse_a_world)
	breaker.request_install(player)
	for i in 90:
		await physics_frame
	if not (breaker.is_powered and not paused and gm.state == GameManager.State.PLAYING):
		print("TEST FAIL: two fuses did not power/start the run")
		quit(1)
		return
	if not keypad.powered:
		print("TEST FAIL: power did not wake the keypad")
		quit(1)
		return
	if keypad.try_pin("0000"):
		print("TEST FAIL: keypad accepted a wrong code")
		quit(1)
		return
	if not keypad.try_pin("%04d" % gen.front_door_pin):
		print("TEST FAIL: keypad rejected the ledger code")
		quit(1)
		return
	for i in 20:
		await physics_frame
	var front_doors_open := 0
	for d in hinged:
		if absf(d.position.z - 15.0) < 0.2 and absf(d.position.x) < 1.5 and d.is_open:
			front_doors_open += 1
	if front_doors_open < 2:
		print("TEST FAIL: PIN did not open both front doors")
		quit(1)
		return
	# Ledger notebook stores the code in the notes.
	var notebooks := _find_all(main, "NotebookPickup")
	if notebooks.size() != 1:
		print("TEST FAIL: expected one notebook in the junk")
		quit(1)
		return
	notebooks[0].interact(player)
	var pin_note_found := false
	for entry in PlayerNotes.entries:
		if ("%04d" % gen.front_door_pin) in entry:
			pin_note_found = true
	if not pin_note_found:
		print("TEST FAIL: notebook did not record the door code")
		quit(1)
		return
	print("fuse power + keypad + notebook OK")

	# --- Free-angle swivel: adjust moves smoothly, release snaps to 15° ---
	var swivel := _mirror_near(mirrors, route["mirrors"][0])
	var before := swivel.rotation.y
	swivel.adjust_by_mouse(-2400.0)  # ~12 degrees of mouse swivel
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
	if clock.is_running or socket8.gear != gear_by_teeth[12] or not player.inventory.is_empty():
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

	# Correct arrangement (request_seat is the chooser's replicated path;
	# a headless test cannot click the popup).
	for s in sockets:
		var gear: Grabbable = gear_by_teeth[s.required_teeth]
		if not player.inventory.has(gear):
			player.teleport(gear.global_position + Vector3(0, 0, 1.0))
			for i in 10:
				await physics_frame
			player.pick_up(gear)
		if not player.inventory.has(gear):
			print("TEST FAIL: could not pack %s" % gear.display_name)
			quit(1)
			return
		s.request_seat(player, gear)
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

	# --- Laser maze: dead until the Heavy Battery is cradled ---
	for door in hinged:
		door.set_open(true)
	var emitter: LightEmitter = _find_all(main, "LightEmitter")[0]
	if emitter.powered:
		print("TEST FAIL: laser powered before battery install")
		quit(1)
		return
	var battery: Grabbable = get_nodes_in_group("batteries")[0]
	player.teleport(battery.global_position + Vector3(0, 0, 1.0))
	for i in 10:
		await physics_frame
	player.pick_up(battery)
	if not player.inventory.has(battery):
		print("TEST FAIL: could not pack the Heavy Battery")
		quit(1)
		return
	var cradle: BatterySocket = emitter.get_node("Housing")
	cradle.interact(player)
	if not emitter.powered or not player.inventory.is_empty():
		print("TEST FAIL: battery install did not power the emitter")
		quit(1)
		return
	print("battery install powers the laser OK")
	# Align this run's route to its published solution angles.
	for i in route["mirrors"].size():
		_mirror_near(mirrors, route["mirrors"][i]).rotation.y = deg_to_rad(route["solutions"][i])
	for i in 90:
		await physics_frame
	if not gm._light_done:
		print("TEST FAIL: laser maze not solved at 45-degree alignment")
		# Diagnose: trace each expected beam segment and report the first
		# collider it strikes.
		var space := player.get_world_3d().direct_space_state
		var trace_points: Array[Vector3] = [emitter.get_node("Muzzle").global_position]
		for m_pos in route["mirrors"]:
			trace_points.append(m_pos + Vector3(0, 1.2, 0))
		for i in trace_points.size() - 1:
			var q := PhysicsRayQueryParameters3D.create(trace_points[i], trace_points[i + 1])
			var hit := space.intersect_ray(q)
			var label: String = "clear"
			if not hit.is_empty():
				label = "%s at %s" % [(hit["collider"] as Node).name, hit["position"]]
			print("  segment %d: %s -> %s : %s" % [i, trace_points[i], trace_points[i + 1], label])
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
	if not player.inventory.has(wrench):
		print("TEST FAIL: could not pack the released wrench")
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
	if not wrench.spent:
		print("TEST FAIL: wrench not marked spent after valve sync")
		quit(1)
		return

	# --- Will to the porch exit ---
	player.drop_held()
	var will: Grabbable = get_nodes_in_group("will_items")[0]
	player.teleport(will.global_position + Vector3(0, 0, 1.0))
	for i in 10:
		await physics_frame
	player.pick_up(will)
	if not player.inventory.has(will):
		print("TEST FAIL: could not pack the Will")
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
