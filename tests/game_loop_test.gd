extends SceneTree
## Headless end-to-end test of the deepened game loop:
## intro letter -> crowbar/toy-crate gating -> two-fuse breaker (powers
## keypad, starts timer) -> keypad PIN opens the front doors (code from
## the junk-lot notebook) -> free-angle mirror swivel & detent snap ->
## puzzle box dial-and-lever combination (wrong symbol or mistimed input
## resets it, the engraved sequence unlocks it and releases the Brass
## Wrench) -> hydraulic press (fittings sequenced behind the Small/Brass
## wrenches, then five signed-PSI toggle valves matched to a target) ->
## the pressure lock frees the Heavy Battery -> laser maze (every prism
## table required, spans >= 2 rooms) -> each mastered machine reveals a
## strongbox digit into the notes -> the vault strongbox's dials free
## the Will -> porch exit -> victory cinematic + S rank. Plus pause
## menu and lore-note checks.
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

	# The intro letter opens the run; dismissing it hands over control
	# and queues Mrs. Puddle's radio check.
	var hud: HUD = main.get_node("HUD")
	if not hud._intro_open:
		print("TEST FAIL: intro letter did not show at run start")
		quit(1)
		return
	hud.dismiss_intro()
	if hud._intro_open:
		print("TEST FAIL: intro letter did not dismiss")
		quit(1)
		return

	# Every pickup has a HUD icon that loads, and every handling foley
	# sample was synthesized.
	for group in hud.ITEM_ICONS:
		var tex: Texture2D = load(hud.ITEM_ICONS[group]) if ResourceLoader.exists(hud.ITEM_ICONS[group]) else null
		if tex == null:
			print("TEST FAIL: missing item icon for group %s (%s)" % [group, hud.ITEM_ICONS[group]])
			quit(1)
			return
	for sound in ["pickup_metal", "pickup_heavy", "pickup_ceramic", "pickup_paper", "drop_metal",
			"drop_metal_soft", "drop_heavy", "drop_heavy_soft", "drop_ceramic", "drop_ceramic_soft", "drop_paper"]:
		if not AudioSynthesizer.instance._streams.has(sound):
			print("TEST FAIL: missing handling sound %s" % sound)
			quit(1)
			return

	var gen: MansionGenerator = main.get_node("MansionGenerator")
	var route: Dictionary = gen.active_route
	print("run layout: route=%s (%d mirrors) valves=%s puzzle_box=%s" % [
		route["name"], route["mirrors"].size(), gen._valve_cells, gen._puzzle_box_cell])
	var player: Player = main.get_node("Players/1")
	var gm: GameManager = main.get_node("GameManager")
	# Main.tscn may ship with the playtest switch off; the loop test
	# always exercises the real timed run.
	gm.timer_enabled = true
	var pause_menu: PauseMenu = main.get_node("PauseMenu")
	var mirrors := _find_all(main, "PrismTable")
	var machines := _find_all(main, "PressurePuzzleManager")
	var gates := _find_all(main, "HydraulicDoor")
	var vault_doors := _find_all(main, "VaultDoor")
	var hinged := _find_all(main, "Door")
	var breakers := _find_all(main, "BreakerBox")
	var boxes := _find_all(main, "PuzzleBox")
	var lockboxes := _find_all(main, "LockBox")
	print("found: %d mirrors, %d presses, %d gates, %d vault doors, %d hinged, %d breakers, %d puzzle boxes, %d strongboxes" % [
		mirrors.size(), machines.size(), gates.size(), vault_doors.size(), hinged.size(), breakers.size(), boxes.size(), lockboxes.size()])
	if mirrors.size() != route["mirrors"].size() + 1 or machines.size() != 1 or gates.size() != 1 \
			or vault_doors.size() != 1 or breakers.size() != 1 or boxes.size() != 1 \
			or lockboxes.size() != 1 or hinged.size() < 5:
		print("TEST FAIL: unexpected element counts")
		quit(1)
		return
	var lockbox: LockBox = lockboxes[0]
	var machine: PressurePuzzleManager = machines[0]
	var pressure_gate: HydraulicDoor = gates[0]
	# The puzzle box and the press live in different rooms, and the
	# console stands right beside the hydraulic gate it controls.
	if gen._puzzle_box_cell == gen._valve_cells[0]:
		print("TEST FAIL: puzzle box and press share a room")
		quit(1)
		return
	if machine.global_position.distance_to(pressure_gate.global_position) > 3.5:
		print("TEST FAIL: press console is not beside the hydraulic gate (%.1f m)" % machine.global_position.distance_to(pressure_gate.global_position))
		quit(1)
		return
	if machine.valve_on.size() != 5 or machine.small_tight.size() < 1 or machine.small_tight.size() > 3 \
			or machine.big_tight.size() < 1 or machine.big_tight.size() > 2:
		print("TEST FAIL: press built %d valves, %d small, %d big fittings" % [
			machine.valve_on.size(), machine.small_tight.size(), machine.big_tight.size()])
		quit(1)
		return
	# Every route must span at least 2 real rooms and, per the necessity
	# design, provably require every one of its prism tables — asserted
	# separately by puzzle_test.gd's removal sweep; here we just check
	# the room-count invariant holds for whichever route this run drew.
	var room_cells := {}
	var route_pts: Array = [route["emitter"]] + route["mirrors"] + [route["safe"]]
	for p in route_pts:
		room_cells[gen._cell_of(p)] = true
	if room_cells.size() < 2:
		print("TEST FAIL: route %s only touches %d room(s)" % [route["name"], room_cells.size()])
		quit(1)
		return
	var vault_door: VaultDoor = vault_doors[0]
	var breaker: BreakerBox = breakers[0]
	var minigame: FusePanel = breaker.minigame
	var box: PuzzleBox = boxes[0]

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
	# Ledger notebook stores the code in the notes; the inventor's five
	# lore notes stand beside their machines and read into the notepad.
	var notebooks := _find_all(main, "NotebookPickup")
	var ledger: NotebookPickup = null
	var lore_notes: Array = []
	var clue_notes: Array = []
	for nb in notebooks:
		if "front door code" in nb.note_text:
			ledger = nb
		elif nb.name in ["ObservatoryLog", "WorkshopScrap"]:
			clue_notes.append(nb)
		else:
			lore_notes.append(nb)
	# 1 door-code ledger, 5 of the inventor's musings, and the 2 puzzle-box
	# clues (the observatory log and the workshop scrap).
	if ledger == null or lore_notes.size() != 5 or clue_notes.size() != 2:
		print("TEST FAIL: expected 1 ledger + 5 lore + 2 clues, found %d notebooks (%d lore, %d clues)" % [
			notebooks.size(), lore_notes.size(), clue_notes.size()])
		quit(1)
		return
	ledger.interact(player)
	var pin_note_found := false
	for entry in PlayerNotes.entries:
		if ("%04d" % gen.front_door_pin) in entry:
			pin_note_found = true
	if not pin_note_found:
		print("TEST FAIL: notebook did not record the door code")
		quit(1)
		return
	lore_notes[0].interact(player)
	var lore_found := false
	for entry in PlayerNotes.entries:
		if "C.G." in entry:
			lore_found = true
	if not lore_found:
		print("TEST FAIL: lore note did not read into the notepad")
		quit(1)
		return
	print("fuse power + keypad + notebook + lore OK")

	# --- Mirrors: hauled ones park by a wall and must be pushed home ---
	var route_mirrors: Array = []
	for i in route["mirrors"].size():
		route_mirrors.append(_mirror_named(mirrors, "Mirror_%d" % i))
	var hauled_count := 0
	for i in route_mirrors.size():
		var m: PrismTable = route_mirrors[i]
		var target: Vector3 = route["mirrors"][i]
		if m.pushable:
			hauled_count += 1
			if m.seated or m.global_position.distance_to(target) < 1.5:
				print("TEST FAIL: hauled mirror %d spawned seated / on its ring" % i)
				quit(1)
				return
			if m.global_position.distance_to(gen.get_room_center(gen._cell_of(target))) < 3.0:
				print("TEST FAIL: hauled mirror %d not parked by a wall (%s)" % [i, m.global_position])
				quit(1)
				return
		elif m.global_position.distance_to(target) > 0.05 or not m.seated:
			print("TEST FAIL: fixed mirror %d off its beam spot" % i)
			quit(1)
			return
	if hauled_count == 0 or hauled_count == route_mirrors.size():
		print("TEST FAIL: expected a mix of hauled and fixed mirrors (hauled=%d/%d)" % [hauled_count, route_mirrors.size()])
		quit(1)
		return
	# Swivel is refused until a hauled mirror is seated; hauling it to its
	# ring seats it (snap), after which it swivels like any other.
	for i in route_mirrors.size():
		var m: PrismTable = route_mirrors[i]
		if not m.pushable:
			continue
		var target: Vector3 = route["mirrors"][i]
		player.teleport(m.global_position + Vector3(0, 0, 1.1))
		for k in 5:
			await physics_frame
		if not player.start_pushing(m):
			print("TEST FAIL: could not take hold of hauled mirror %d" % i)
			quit(1)
			return
		# Walk it home: the mirror rides the grip offset, so parking the
		# player one grip-length short of the ring lands it inside the snap.
		player.teleport(target - player._push_offset)
		for k in 20:
			await physics_frame
		if not m.seated or m.global_position.distance_to(target) > 0.05:
			print("TEST FAIL: hauled mirror %d did not seat on its ring (at %s)" % [i, m.global_position])
			quit(1)
			return
		if player._pushing_mirror != null:
			print("TEST FAIL: player still holding a seated mirror")
			quit(1)
			return
	# The decoy is FREE: haul it anywhere, swivel it while holding, it
	# never seats and shows no ring.
	var decoy := _mirror_named(mirrors, "Mirror_Decoy")
	if decoy == null or not decoy.pushable or decoy.has_target or decoy.seated:
		print("TEST FAIL: decoy is not a free (ringless, unseated) pushable")
		quit(1)
		return
	player.teleport(decoy.global_position + Vector3(0, 0, 1.1))
	for k in 5:
		await physics_frame
	if not player.start_pushing(decoy):
		print("TEST FAIL: could not take hold of the decoy")
		quit(1)
		return
	var decoy_from := decoy.global_position
	var decoy_yaw := decoy.rotation.y
	decoy.adjust_by_mouse(-600.0)  # swivel while held
	player.teleport(player.global_position + Vector3(2.0, 0, 0))
	for k in 5:
		await physics_frame
	if decoy.global_position.distance_to(decoy_from) < 1.5 or absf(decoy.rotation.y - decoy_yaw) < 0.5:
		print("TEST FAIL: free decoy did not haul/swivel (moved %.2f, turned %.2f)" % [
			decoy.global_position.distance_to(decoy_from), absf(decoy.rotation.y - decoy_yaw)])
		quit(1)
		return
	player._finish_push()
	if decoy.seated or player._pushing_mirror != null:
		print("TEST FAIL: free decoy seated or stayed held after release")
		quit(1)
		return
	print("hauled mirrors push + snap OK; free decoy OK")

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

	# --- Puzzle box, stage one: the dial is dead until all three astral
	# pendants are carried back and seated ---
	var wrench: Grabbable = get_nodes_in_group("big_wrenches")[0]
	if wrench.collision_layer != 0 or wrench.get_parent() != box:
		print("TEST FAIL: wrench not stashed inside the puzzle box")
		quit(1)
		return
	# Panel modal: [E] on the case opens the dial overlay (pausing solo);
	# ESC steps away.
	box.interact(player)
	await process_frame
	if not box._panel_open or not paused:
		print("TEST FAIL: puzzle box panel did not open/pause")
		quit(1)
		return
	_press_escape()
	await process_frame
	await process_frame
	if box._panel_open or paused:
		print("TEST FAIL: ESC did not close the puzzle box panel")
		quit(1)
		return
	var pendants := get_nodes_in_group("pendants")
	if pendants.size() != box.sequence_length:
		print("TEST FAIL: expected %d pendants, found %d" % [box.sequence_length, pendants.size()])
		quit(1)
		return
	# Every pendant must be a hunt: never in the box's own room.
	for pd in pendants:
		if gen._cell_of(pd.global_position) == gen._puzzle_box_cell:
			print("TEST FAIL: pendant %s spawned in the box's own room" % pd.name)
			quit(1)
			return
	# The dial is inert while sockets are empty.
	box.register_dial_input(box.active_target_sequence[0])
	if not box.current_input_buffer.is_empty() or box.is_armed():
		print("TEST FAIL: the dial accepted input before the box was armed")
		quit(1)
		return
	# Carry each pendant back and fit it.
	for pd in pendants:
		player.teleport(pd.global_position + Vector3(0, 0, 1.0))
		for w in 10:
			await physics_frame
		player.pick_up(pd)
		box.interact(player)
		await physics_frame
	if not box.is_armed() or box.seated_symbols.size() != box.sequence_length:
		print("TEST FAIL: seating every pendant did not arm the box (%s)" % [box.seated_symbols])
		quit(1)
		return
	if box._panel_open:
		box._close_panel()

	# The order itself is only in the observatory log, in another room.
	var log_note: NotebookPickup = main.find_child("ObservatoryLog", true, false)
	if log_note == null or gen._cell_of(log_note.global_position) == gen._puzzle_box_cell:
		print("TEST FAIL: observatory log missing or in the box's own room")
		quit(1)
		return
	log_note.interact(player)
	var order_names: Array[String] = []
	for sym in box.required_symbols():
		order_names.append(PuzzleBox.SYMBOL_LABELS[sym])
	var logged := ""
	for entry in PlayerNotes.entries:
		if "Observatory log" in entry:
			logged = entry
	if logged.is_empty():
		print("TEST FAIL: the observatory log did not reach the notes")
		quit(1)
		return
	# It must name the symbols in the real dial order.
	var seen_at: Array[int] = []
	for label_name in order_names:
		seen_at.append(logged.find(label_name))
	if seen_at[0] < 0 or seen_at[0] > seen_at[1] or seen_at[1] > seen_at[2]:
		print("TEST FAIL: log does not name %s in dial order: %s" % [order_names, logged])
		quit(1)
		return

	box.interact(player)
	await process_frame

	# A wrong symbol on the very first slot resets the whole attempt.
	var correct0: String = box.active_target_sequence[0]
	var wrong0 := ""
	for sym in PuzzleBox.SYMBOLS:
		if sym != correct0:
			wrong0 = sym
			break
	box.register_dial_input(wrong0)
	if box.current_input_buffer.size() != 0 or box.is_locked == false:
		print("TEST FAIL: wrong symbol did not reset the puzzle box")
		quit(1)
		return

	box.register_dial_input(correct0)
	if box.current_input_buffer != [correct0]:
		print("TEST FAIL: correct symbol was not accepted")
		quit(1)
		return
	box.register_advance_input()
	if not box.is_waiting_for_cadence:
		print("TEST FAIL: lever pull did not start the settle flourish")
		quit(1)
		return
	# The settle is FLOURISH ONLY. It must not swallow or fail the next
	# click: a player entering the CORRECT order at a normal clicking
	# pace was told they were wrong every time, which read as a broken
	# lock in playtest. Dial the rest immediately, mid-settle.
	var mid_settle: String = box.active_target_sequence[2]
	box.register_dial_input(mid_settle)
	if box.current_input_buffer != [correct0, PuzzleBox.ADVANCE_SYMBOL, mid_settle]:
		print("TEST FAIL: the settle swallowed a correct click (%s)" % [box.current_input_buffer])
		quit(1)
		return
	box.reset_puzzle()

	# The correct order entered back-to-back, with NO waiting at all,
	# must unlock it — that is exactly how a player clicks.
	for i in box.active_target_sequence.size():
		var expected: String = box.active_target_sequence[i]
		if expected == PuzzleBox.ADVANCE_SYMBOL:
			box.register_advance_input()
		else:
			box.register_dial_input(expected)
	if box.is_locked:
		print("TEST FAIL: puzzle box did not unlock on the correct sequence")
		quit(1)
		return
	# The unlock flourish runs ~1.4 s (lever, then the compartment
	# sliding open) before the wrench is handed over.
	for i in 120:
		await physics_frame
	if wrench.collision_layer == 0 or wrench.get_parent() == box:
		print("TEST FAIL: compartment did not release the wrench")
		quit(1)
		return
	# It must land out the FRONT of the case (the back stands against the
	# room wall) and stay inside the room, not in the masonry.
	var to_wrench := wrench.global_position - box.global_position
	var box_front := box.global_transform.basis.z
	if to_wrench.dot(box_front) < 0.4:
		print("TEST FAIL: wrench dropped behind the puzzle box (offset %s)" % to_wrench)
		quit(1)
		return
	var box_room := gen.get_room_center(gen._puzzle_box_cell)
	if absf(wrench.global_position.x - box_room.x) > 4.8 or absf(wrench.global_position.z - box_room.z) > 4.8:
		print("TEST FAIL: wrench landed outside the puzzle box's room at %s" % wrench.global_position)
		quit(1)
		return
	# The astronomical box surrenders dial II, and nothing else.
	var after_box := _revealed_digits()
	if after_box.size() != 1 or not after_box.has("II") or after_box["II"] != gen._lockbox_code[1]:
		print("TEST FAIL: puzzle box revealed %s, expected only dial II = %d" % [
			after_box, gen._lockbox_code[1]])
		quit(1)
		return
	print("puzzle box dial-and-lever sequence OK")

	# --- Pause menu freezes the run ---
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

	# --- Hydraulic press: modal panel, phase gating, wrench checks, PSI ---
	# [E] opens the fullscreen control panel (solo pauses); ESC steps away.
	machine.interact(player)
	await process_frame
	if not machine.minigame.is_open or not paused:
		print("TEST FAIL: press panel did not open/pause")
		quit(1)
		return
	_press_escape()
	await process_frame
	await process_frame
	if machine.minigame.is_open or paused:
		print("TEST FAIL: ESC did not close the press panel")
		quit(1)
		return
	var wrong_uses := [0]
	machine.wrong_item_used.connect(func(_by: Node3D) -> void: wrong_uses[0] += 1)
	# Valves are sealed until every fitting is torqued.
	machine.request_toggle_valve(player, 0)
	if machine.valve_on[0]:
		print("TEST FAIL: valve toggled before the fittings were tightened")
		quit(1)
		return
	# Small fittings refuse bare hands.
	machine.request_tighten(player, false, 0)
	if machine.small_tight[0]:
		print("TEST FAIL: fitting tightened without a wrench")
		quit(1)
		return
	# Fetch the garage's Small Wrench.
	var small_wrench: Grabbable = get_nodes_in_group("small_wrenches")[0]
	player.teleport(small_wrench.global_position + Vector3(0, 0, 1.0))
	for i in 10:
		await physics_frame
	player.pick_up(small_wrench)
	if not player.inventory.has(small_wrench):
		print("TEST FAIL: could not pack the Small Wrench")
		quit(1)
		return
	# Big fittings are still phase-locked while small ones remain loose.
	machine.request_tighten(player, true, 0)
	if machine.big_tight[0]:
		print("TEST FAIL: big fitting accepted work before its phase")
		quit(1)
		return
	for i in machine.small_tight.size():
		machine.request_tighten(player, false, i)
	if machine.phase != PressurePuzzleManager.Phase.BIG_FITTINGS:
		print("TEST FAIL: press did not advance after the small fittings")
		quit(1)
		return
	# Big fitting with only the small wrench -> wrong-item event, no turn.
	machine.request_tighten(player, true, 0)
	if machine.big_tight[0] or wrong_uses[0] == 0:
		print("TEST FAIL: big fitting accepted the small wrench (wrong_uses=%d)" % wrong_uses[0])
		quit(1)
		return
	# The Brass Wrench the puzzle box released is the big one.
	player.teleport(wrench.global_position + Vector3(0, 0, 1.0))
	for i in 10:
		await physics_frame
	player.pick_up(wrench)
	if not player.inventory.has(wrench):
		print("TEST FAIL: could not pack the released Brass Wrench")
		quit(1)
		return
	for i in machine.big_tight.size():
		machine.request_tighten(player, true, i)
	if machine.phase != PressurePuzzleManager.Phase.VALVES:
		print("TEST FAIL: press did not open the valve phase")
		quit(1)
		return
	# Toggle math: opening adds the signed PSI, closing removes it. Probe
	# with a valve that is NOT a one-valve solution, else the press solves
	# and locks mid-check.
	var probe := -1
	for i in 5:
		if machine.base_psi + machine.valve_pressures[i] != machine.target_psi:
			probe = i
			break
	machine.request_toggle_valve(player, probe)
	if machine.current_psi != machine.base_psi + machine.valve_pressures[probe]:
		print("TEST FAIL: PSI after opening the probe valve: %d" % machine.current_psi)
		quit(1)
		return
	machine.request_toggle_valve(player, probe)
	if machine.current_psi != machine.base_psi:
		print("TEST FAIL: PSI did not return to base after closing")
		quit(1)
		return
	# Solve it the way a player would: find a combination hitting the
	# target and flip exactly those valves open.
	var solution_mask := -1
	for mask in range(1, 32):
		var total := machine.base_psi
		for i in 5:
			if mask & (1 << i):
				total += machine.valve_pressures[i]
		if total == machine.target_psi:
			solution_mask = mask
			break
	if solution_mask < 0:
		print("TEST FAIL: no valve combination reaches the target PSI")
		quit(1)
		return
	for i in 5:
		var want := (solution_mask & (1 << i)) != 0
		if machine.valve_on[i] != want:
			machine.request_toggle_valve(player, i)
	if not machine.solved:
		print("TEST FAIL: press not solved at target PSI (%d/%d)" % [machine.current_psi, machine.target_psi])
		quit(1)
		return
	for i in 120:
		await physics_frame
	if not pressure_gate.is_open:
		print("TEST FAIL: hydraulic gate did not vent on solve")
		quit(1)
		return
	if not (small_wrench.spent and wrench.spent):
		print("TEST FAIL: wrenches not marked spent after the solve")
		quit(1)
		return
	# The locked machine must ignore further pokes.
	var psi_locked: int = machine.current_psi
	machine.request_toggle_valve(player, 0)
	if machine.current_psi != psi_locked:
		print("TEST FAIL: solved press still accepts valve toggles")
		quit(1)
		return
	# The press adds dial III — and only dial III.
	var after_press := _revealed_digits()
	if after_press.size() != 2 or not after_press.has("III") or after_press["III"] != gen._lockbox_code[2]:
		print("TEST FAIL: press revealed %s, expected dials II+III" % after_press)
		quit(1)
		return
	print("hydraulic press panel three-phase puzzle OK")

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
	# Two-hand load: carried in front, never in the pack, and visible.
	if player.carried_item != battery or player.inventory.has(battery) or not battery.visible:
		print("TEST FAIL: Heavy Battery was not lifted as a carried load")
		quit(1)
		return
	if battery.get_parent() != player.hold_point:
		print("TEST FAIL: carried battery is not riding the hold point")
		quit(1)
		return
	# Carrying it halves the player's speed: walk a second on the spot and
	# check the top speed reached.
	var carry_top := 0.0
	Input.action_press("move_up")
	for i in 60:
		await physics_frame
		carry_top = maxf(carry_top, Vector2(player.velocity.x, player.velocity.z).length())
	Input.action_release("move_up")
	for i in 20:
		await physics_frame
	if carry_top > player.max_speed * player.carry_speed_factor + 0.15 or carry_top < 0.3:
		print("TEST FAIL: carrying speed %.2f (want ~%.2f)" % [carry_top, player.max_speed * player.carry_speed_factor])
		quit(1)
		return
	# Hands full: mirrors refuse hauling.
	if decoy != null and player.start_pushing(decoy):
		print("TEST FAIL: hauled a mirror while carrying the battery")
		quit(1)
		return
	# Set it down and pick it back up (G-drop path), then install.
	player.drop_at(player.CARRY_SLOT)
	for i in 10:
		await physics_frame
	if player.carried_item != null or battery.get_parent() == player.hold_point:
		print("TEST FAIL: could not set the battery down")
		quit(1)
		return
	player.teleport(battery.global_position + Vector3(0, 0, 1.0))
	for i in 10:
		await physics_frame
	player.pick_up(battery)
	if player.carried_item != battery:
		print("TEST FAIL: could not lift the battery again")
		quit(1)
		return
	var cradle: BatterySocket = emitter.get_node("Housing")
	cradle.interact(player)
	# The pack still holds both (spent) wrenches; only the battery leaves.
	if not emitter.powered or player.carried_item != null or player.inventory.has(battery):
		print("TEST FAIL: battery install did not power the emitter")
		quit(1)
		return
	print("battery carry + install powers the laser OK")

	# --- Prisms: at least one table's prism is loose in the house ---
	var safes := _find_all(main, "LaserSafe")
	if safes.size() != 1:
		print("TEST FAIL: expected one wall safe, found %d" % safes.size())
		quit(1)
		return
	var safe: LaserSafe = safes[0]
	var empty_tables: Array = []
	for i in route["mirrors"].size():
		var t: PrismTable = _mirror_near(mirrors, route["mirrors"][i])
		if t.prism == null:
			empty_tables.append(t)
	if empty_tables.is_empty():
		print("TEST FAIL: no table is missing its prism")
		quit(1)
		return
	var loose_prisms: Array = []
	for p in get_nodes_in_group("prisms"):
		if p.holder == null and not (p.get_parent() is PrismTable):
			loose_prisms.append(p)
	if loose_prisms.size() < empty_tables.size():
		print("TEST FAIL: %d empty tables but only %d loose prisms" % [empty_tables.size(), loose_prisms.size()])
		quit(1)
		return
	# Beam cannot solve while a table is empty: align now, expect no crack.
	for i in route["mirrors"].size():
		_mirror_near(mirrors, route["mirrors"][i]).rotation.y = deg_to_rad(route["solutions"][i])
	for i in 60:
		await physics_frame
	if safe.cracked:
		print("TEST FAIL: safe cracked with an empty prism table on the route")
		quit(1)
		return
	# Fetch each loose prism (pack item) and set it on an empty table.
	for k in empty_tables.size():
		var loose: Grabbable = loose_prisms[k]
		var table: PrismTable = empty_tables[k]
		player.teleport(loose.global_position + Vector3(0, 0, 1.0))
		for i in 10:
			await physics_frame
		player.pick_up(loose)
		if player.inventory_find("prisms") == null:
			print("TEST FAIL: could not pack the loose prism")
			quit(1)
			return
		table.request_seat_prism(player)
		if table.prism != loose or player.inventory.has(loose):
			print("TEST FAIL: prism did not seat on the empty table")
			quit(1)
			return
	print("misplaced prism found and seated OK")

	# --- Aligned route cracks the wall safe; the lever opens the gate ---
	# Step out of the beam's way first (the porch end of the foyer is off
	# every route).
	player.teleport(Vector3(0, 0.1, 13.5))
	for i in 90:
		await physics_frame
	if not safe.cracked:
		print("TEST FAIL: laser maze did not crack the safe at the solution angles")
		# Diagnose: trace each expected beam segment and report the first
		# collider it strikes.
		var space := player.get_world_3d().direct_space_state
		var trace_points: Array[Vector3] = [emitter.get_node("Muzzle").global_position]
		for m_pos in route["mirrors"]:
			trace_points.append(m_pos + Vector3(0, 1.2, 0))
		trace_points.append(route["safe"] + Vector3(0, 1.2, 0))
		for i in trace_points.size() - 1:
			var q := PhysicsRayQueryParameters3D.create(trace_points[i], trace_points[i + 1])
			var hit := space.intersect_ray(q)
			var label: String = "clear"
			if not hit.is_empty():
				label = "%s at %s" % [(hit["collider"] as Node).name, hit["position"]]
			print("  segment %d: %s -> %s : %s" % [i, trace_points[i], trace_points[i + 1], label])
		quit(1)
		return
	if gm._light_done:
		print("TEST FAIL: light objective completed before the lever was pulled")
		quit(1)
		return
	# Before cracking, [E] would have opened the note close-up; now it
	# throws the lever.
	safe.interact(player)
	await process_frame
	if not safe.lever_pulled or not gm._light_done:
		print("TEST FAIL: pulling the lever did not complete the light puzzle")
		quit(1)
		return
	# The safe completes the set with dial I.
	var after_safe := _revealed_digits()
	if after_safe.size() != 3 or not after_safe.has("I") or after_safe["I"] != gen._lockbox_code[0]:
		print("TEST FAIL: safe revealed %s, expected all three dials" % after_safe)
		quit(1)
		return
	print("wall safe cracked + lever pulled OK")

	# Light + hydraulics both done: the vault gate must stand open.
	for i in 120:
		await physics_frame
	if not vault_door.is_open:
		print("TEST FAIL: vault gate closed with light + hydraulics done")
		quit(1)
		return

	# --- Strongbox: the three mastered machines revealed its digits ---
	# Notes arrive in solve order; the numeral names the dial.
	var numeral_to_dial := {"I": 0, "II": 1, "III": 2}
	var revealed := [-1, -1, -1]
	var reveal_count := 0
	for entry in PlayerNotes.entries:
		if entry.begins_with("Strongbox dial"):
			var numeral: String = entry.get_slice(" ", 2)
			revealed[numeral_to_dial[numeral]] = int(entry.get_slice(": ", 1))
			reveal_count += 1
	if reveal_count != 3:
		print("TEST FAIL: expected 3 revealed strongbox digits, notes held %d" % reveal_count)
		quit(1)
		return
	if str(revealed) != str(gen._lockbox_code):
		print("TEST FAIL: revealed digits %s != combination %s" % [revealed, gen._lockbox_code])
		quit(1)
		return
	player.drop_held()
	var will: Grabbable = get_nodes_in_group("will_items")[0]
	if will.get_parent() != lockbox or will.collision_layer != 0:
		print("TEST FAIL: the Will is not stashed inside the strongbox")
		quit(1)
		return
	# A wrong combination just clunks — dials keep their positions.
	lockbox.request_set_dial(player, 0, (lockbox.combination[0] + 1) % 10)
	lockbox.request_set_dial(player, 1, lockbox.combination[1])
	lockbox.request_set_dial(player, 2, lockbox.combination[2])
	lockbox.request_try_open(player)
	if not lockbox.is_locked or lockbox.dials[1] != lockbox.combination[1]:
		print("TEST FAIL: wrong combination opened the strongbox (or reset the dials)")
		quit(1)
		return
	# The revealed digits open it and free the Will.
	lockbox.request_set_dial(player, 0, lockbox.combination[0])
	lockbox.request_try_open(player)
	if lockbox.is_locked:
		print("TEST FAIL: correct combination did not open the strongbox")
		quit(1)
		return
	for i in 60:
		await physics_frame
	if will.get_parent() == lockbox or will.collision_layer == 0:
		print("TEST FAIL: strongbox did not release the Will")
		quit(1)
		return
	print("strongbox digits + dials + release OK")

	# --- Will to the porch exit; victory cinematic + rank ---
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
	if gm.state != GameManager.State.WON:
		print("TEST FAIL: not WON at porch exit (state=%d)" % gm.state)
		quit(1)
		return
	# The victory cinematic must NOT pause the tree (the character keeps
	# idling on camera) and must lock the player's input instead.
	if paused or not player.ui_locked:
		print("TEST FAIL: victory should lock input, not pause the tree")
		quit(1)
		return
	if not is_instance_valid(gm._cine_cam) or not gm._cine_cam.current:
		print("TEST FAIL: victory cinematic camera did not take over")
		quit(1)
		return
	# After the cinematic beat the rank screen fades in: a sub-2:00 run
	# grades S.
	for i in 120:
		await physics_frame
	var end_screen: Control = main.get_node("HUD/EndScreen")
	var rank_label: Label = main.get_node("HUD/EndScreen/Center/VBox/Rank")
	if not end_screen.visible or not rank_label.visible or rank_label.text != "S":
		print("TEST FAIL: rank screen wrong (visible=%s rank=%s)" % [end_screen.visible, rank_label.text])
		quit(1)
		return
	print("victory rank: %s — %s" % [rank_label.text, main.get_node("HUD/EndScreen/Center/VBox/Subtitle").text])
	print("TEST PASS: deepened game loop end-to-end")
	quit(0)


## Strongbox notes written so far, as {dial_numeral: digit}. The
## design is one digit per mastered machine, so this is sampled
## between completions, not just at the end.
func _revealed_digits() -> Dictionary:
	var found := {}
	for entry in PlayerNotes.entries:
		if entry.begins_with("Strongbox dial"):
			found[entry.get_slice(" ", 2)] = int(entry.get_slice(": ", 1))
	return found


func _press_escape() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)


func _mirror_named(mirrors: Array, node_name: String) -> PrismTable:
	for m in mirrors:
		if m.name == node_name:
			return m
	return null


func _mirror_near(mirrors: Array, pos: Vector3) -> PrismTable:
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
