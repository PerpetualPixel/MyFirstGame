extends SceneTree
## Laser route regression: iterates ALL route variants via route_override
## and proves each is solvable at its computed solution angles — every
## table on its spot with a prism seated, emitter powered, beam cracks
## the wall safe — and that with the tables at random angles it does not.
## Also proves the route's whole point (every reused this session): the
## route spans >= 2 rooms, and EVERY prism table is individually
## necessary — pulling any single one's prism (leaving that socket
## empty, so the beam sails straight through) must stop the beam from
## ever reaching the safe, even with every other table perfectly
## aligned. A route with a skippable table, or one that never leaves a
## single room, would pass the plain solvability check above and still
## be a bad puzzle — this is what actually catches that.
## Run: godot --headless --path . --script res://tests/puzzle_test.gd

func _initialize() -> void:
	_run()


func _run() -> void:
	for variant in 3:
		var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
		var gen: MansionGenerator = main.get_node("MansionGenerator")
		gen.route_override = variant
		root.add_child(main)
		for i in 30:
			await physics_frame

		var route: Dictionary = gen.active_route
		print("--- variant %d: %s ---" % [variant, route["name"]])
		var tables: Array = []
		var safes: Array = []
		var emitters: Array = []
		_collect(main, tables, safes, emitters)
		if emitters.size() != 1 or tables.size() != route["mirrors"].size() + 1 or safes.size() != 1:
			print("TEST FAIL [%s]: counts wrong (%d emitters, %d tables, %d safes)" % [route["name"], emitters.size(), tables.size(), safes.size()])
			quit(1)
			return
		var safe: LaserSafe = safes[0]
		var emitter: LightEmitter = emitters[0]
		# Park the player well off every route.
		(main.get_node("Players/1") as Player).teleport(Vector3(0, 0.1, 13.5))

		# The route must actually go somewhere: at least 2 distinct rooms.
		var room_cells := {}
		var route_pts: Array = [route["emitter"]] + route["mirrors"] + [route["safe"]]
		for p in route_pts:
			room_cells[gen._cell_of(p)] = true
		if room_cells.size() < 2:
			print("TEST FAIL [%s]: route only touches %d room(s): %s" % [route["name"], room_cells.size(), room_cells.keys()])
			quit(1)
			return
		print("route '%s' spans %d rooms: %s" % [route["name"], room_cells.size(), room_cells.keys()])

		# Every route table on its spot with a prism, then power the beam.
		var spots: Array = route["mirrors"]
		var solutions: Array = route["solutions"]
		var route_tables: Array = []
		for i in spots.size():
			var t: PrismTable = _table_named(tables, "Mirror_%d" % i)
			if t == null:
				print("TEST FAIL [%s]: no table Mirror_%d" % [route["name"], i])
				quit(1)
				return
			if not t.seated:
				t.seated = true
				t.global_position = spots[i]
			if t.prism == null:
				var p: Grabbable = (load("res://scenes/Prism.tscn") as PackedScene).instantiate()
				p.name = "TestPrism_%d" % i
				gen._generated_root.add_child(p)
				t.seat_prism(p)
			route_tables.append(t)
		emitter.power_on()

		# Random angles: must not crack the safe.
		for i in route_tables.size():
			route_tables[i].rotation.y = deg_to_rad(15.0 * float((i * 7 + 3) % 24) + 7.5)
		for i in 60:
			await physics_frame
		if safe.cracked:
			print("TEST FAIL [%s]: safe cracked with tables at arbitrary angles" % route["name"])
			quit(1)
			return

		# Solution angles: cracks it.
		for i in route_tables.size():
			route_tables[i].rotation.y = deg_to_rad(solutions[i])
		for i in 120:
			await physics_frame
		if not safe.cracked:
			print("TEST FAIL [%s]: aligned route did not crack the safe" % route["name"])
			quit(1)
			return
		print("variant '%s' solvable" % route["name"])
		main.queue_free()
		for i in 5:
			await physics_frame

		# Necessity sweep: pull ONE table's prism at a time (fresh scene
		# per table, since `cracked` latches permanently once true) with
		# every other table correctly seated and aligned; the safe must
		# never crack no matter which single table is skipped.
		for remove_idx in spots.size():
			var ok := await _assert_table_required(variant, route, remove_idx)
			if not ok:
				return
		print("variant '%s' requires every one of its %d prism tables" % [route["name"], spots.size()])

	print("TEST PASS: all laser route variants are solvable and fully necessary")
	quit(0)


## Fresh instance of `variant`: every table seated + aligned EXCEPT
## `remove_idx`, whose socket is left empty (prism=null -> face
## collision disabled -> beam passes straight through, exactly like a
## player who never touched that table). Returns false (and prints a
## TEST FAIL) if the safe cracks anyway.
func _assert_table_required(variant: int, route: Dictionary, remove_idx: int) -> bool:
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	var gen: MansionGenerator = main.get_node("MansionGenerator")
	gen.route_override = variant
	root.add_child(main)
	for i in 30:
		await physics_frame
	var spots: Array = route["mirrors"]
	var solutions: Array = route["solutions"]
	for i in spots.size():
		var t: PrismTable = main.find_child("Mirror_%d" % i, true, false)
		t.seated = true
		t.global_position = spots[i]
		if i == remove_idx:
			t.prism = null
			t._refresh_prism()
			continue
		if t.prism == null:
			var p: Grabbable = (load("res://scenes/Prism.tscn") as PackedScene).instantiate()
			gen._generated_root.add_child(p)
			t.seat_prism(p)
		t.rotation.y = deg_to_rad(solutions[i])
	var emitter: LightEmitter = main.find_child("Emitter", true, false)
	var safe: LaserSafe = main.find_child("WallSafe", true, false)
	emitter.power_on()
	(main.get_node("Players/1") as Player).teleport(Vector3(0, 0.1, 13.5))
	for i in 60:
		await physics_frame
	var required := not safe.cracked
	if not required:
		print("TEST FAIL [%s]: safe cracked with table %d skipped (empty socket) — that table is not actually required" % [route["name"], remove_idx])
	main.queue_free()
	for i in 5:
		await physics_frame
	if not required:
		quit(1)
	return required


func _table_named(tables: Array, node_name: String) -> PrismTable:
	for t in tables:
		if t.name == node_name:
			return t
	return null


func _collect(node: Node, tables: Array, safes: Array, emitters: Array) -> void:
	for child in node.get_children():
		if child is PrismTable:
			tables.append(child)
		elif child is LaserSafe:
			safes.append(child)
		elif child is LightEmitter:
			emitters.append(child)
		_collect(child, tables, safes, emitters)
