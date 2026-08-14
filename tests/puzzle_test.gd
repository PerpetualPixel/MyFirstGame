extends SceneTree
## Laser route regression: iterates ALL route variants via route_override,
## proving each is solvable at its published solution angles — and that
## closed doors block the beam (checked on the first variant).
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
		var mirrors: Array = []
		var receivers: Array = []
		var emitters: Array = []
		_collect(main, mirrors, receivers, emitters)
		if emitters.size() != 1 or mirrors.size() != 5 or receivers.size() != 1:
			print("TEST FAIL [%s]: counts wrong (%d emitters, %d mirrors, %d receivers)" % [route["name"], emitters.size(), mirrors.size(), receivers.size()])
			quit(1)
			return
		var receiver: LightReceiver = receivers[0]

		# Align the whole route to its solution.
		var spots: Array = route["mirrors"]
		var solutions: Array = route["solutions"]
		for i in spots.size():
			var m := _mirror_near(mirrors, spots[i])
			if m == null:
				print("TEST FAIL [%s]: no mirror at %s" % [route["name"], spots[i]])
				quit(1)
				return
			m.rotation.y = deg_to_rad(solutions[i])

		if variant == 0:
			for i in 60:
				await physics_frame
			if receiver.is_solved:
				print("TEST FAIL: beam reached receiver through CLOSED doors")
				quit(1)
				return

		for door in _find_doors(main):
			door.set_open(true)
		for i in 120:
			await physics_frame
		if not receiver.is_solved:
			print("TEST FAIL [%s]: aligned route did not solve the receiver" % route["name"])
			quit(1)
			return
		print("variant '%s' solvable" % route["name"])
		main.queue_free()
		for i in 5:
			await physics_frame

	print("TEST PASS: all laser route variants are solvable")
	quit(0)


func _mirror_near(mirrors: Array, pos: Vector3) -> RotatingMirror:
	for m in mirrors:
		if m.global_position.distance_to(pos) < 1.0:
			return m
	return null


func _find_doors(node: Node) -> Array:
	var found: Array = []
	for child in node.get_children():
		if child is Door:
			found.append(child)
		found.append_array(_find_doors(child))
	return found


func _collect(node: Node, mirrors: Array, receivers: Array, emitters: Array) -> void:
	for child in node.get_children():
		if child is RotatingMirror:
			mirrors.append(child)
		elif child is LightReceiver:
			receivers.append(child)
		elif child is LightEmitter:
			emitters.append(child)
		_collect(child, mirrors, receivers, emitters)
