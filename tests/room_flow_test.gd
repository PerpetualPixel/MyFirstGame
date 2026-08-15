extends SceneTree
## Egress regression across several seeds: in every mansion room, the
## room's center and the straight line from the center to each of its
## doorways must be free of solid geometry (a 0.32 m probe at torso
## height, sampled every 0.4 m, stopping 0.9 m short of the doorway so
## the door panel/frame itself doesn't count). Furniture, mirrors, and
## puzzle fixtures all live in wall slots or corners, so this must hold
## on any seed. The vault (pedestal at its center) is exempt.
## Run: godot --headless --path . --script res://tests/room_flow_test.gd

const SEEDS := [11, 22, 33, 44, 55, 66, 77, 88]

func _initialize() -> void:
	_run()


func _run() -> void:
	for s in SEEDS:
		var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
		main.get_node("MansionGenerator").generation_seed = s
		root.add_child(main)
		for i in 20:
			await physics_frame
		var gen: MansionGenerator = main.get_node("MansionGenerator")
		var player: Player = main.get_node("Players/1")
		var space := player.get_world_3d().direct_space_state
		var problems := 0
		for z in gen.GRID_SIZE.y:
			for x in gen.GRID_SIZE.x:
				var cell := Vector2i(x, z)
				if cell == gen.VAULT_STUDY_CELL:
					continue
				var center := gen.get_room_center(cell)
				var doors: Array[Vector3] = []
				for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var next := cell + offset
					if gen._has_door(cell, next) or (cell == gen.FOYER_CELL and offset == Vector2i(0, 1)):
						doors.append(center + Vector3(offset.x, 0, offset.y) * (gen.room_size / 2.0))
				var lines: Array = [[center, center]]
				for d in doors:
					lines.append([center, d])
				for line in lines:
					var a: Vector3 = line[0]
					var b: Vector3 = line[1]
					var length := a.distance_to(b)
					var usable := maxf(length - 0.9, 0.0)
					var t := 0.0
					while t <= usable + 0.001:
						var p := a + (b - a).normalized() * t if length > 0.0 else a
						var hit := _probe(space, p, player)
						if hit != "":
							problems += 1
							print("seed %d room %s: %s blocked at %s by %s" % [s, cell, "center" if length == 0.0 else "path to %s" % b, p, hit])
						if length == 0.0:
							break
						t += 0.4
		main.queue_free()
		await process_frame
		if problems > 0:
			print("TEST FAIL: %d egress obstructions on seed %d" % [problems, s])
			quit(1)
			return
		print("seed %d: all room centers and door approaches clear" % s)
	print("TEST PASS: room flow — centers and door paths clear on %d seeds" % SEEDS.size())
	quit(0)


func _probe(space: PhysicsDirectSpaceState3D, at: Vector3, player: Node3D) -> String:
	var shape := SphereShape3D.new()
	shape.radius = 0.32
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 0.9, 0))
	params.exclude = [player.get_rid()]
	params.collide_with_areas = false
	var hits := space.intersect_shape(params, 4)
	for h in hits:
		var collider: Object = h["collider"]
		if collider is Node:
			var n := collider as Node
			# Hinged door panels sit in doorways; open ones sweep 2 m in.
			# They are the player's own to open/close, not clutter.
			if n is Door or (n.get_parent() != null and n.get_parent() is Door):
				continue
			return "%s (%s)" % [n.name, n.get_class()]
	return ""
