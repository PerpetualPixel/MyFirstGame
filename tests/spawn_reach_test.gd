extends SceneTree
## Spawn-reachability regression. Two ways a seeded item spot can quietly
## ruin a run, both of which shipped once:
##  1. The Crowbar landing INSIDE the garage — it is the only key to that
##     garage, and both other ways in open from the inside, so the run
##     becomes unwinnable.
##  2. An item coming to rest sealed inside a decor mesh. The junk car's
##     hood and cabin are bare MeshInstance3Ds with no collision, so an
##     item placed "on" one falls through and rests inside it, invisible
##     from every angle. room_flow_test cannot see this: it probes at
##     y+0.9 and only along room centres and door lines.
## Sweeps seeds until every spot in every seeded array has been drawn, so
## a bad spot cannot hide behind an unlucky sample.
## Run: godot --headless --path . --script res://tests/spawn_reach_test.gd

const SEEDS := 60
## Garage interior (walls at c +/- 3.35 x, c +/- 3.0 z, c = 22.5, 20.5).
const GARAGE_MIN := Vector2(19.15, 17.5)
const GARAGE_MAX := Vector2(25.85, 23.5)
## Spot counts the generator authors; coverage must reach all of them.
const WANT_SPOTS := {"crowbar": 5, "fuse": 6, "wrench": 4, "notebook": 5}

func _initialize() -> void:
	_run()


func _run() -> void:
	var seen := {"crowbar": {}, "fuse": {}, "wrench": {}, "notebook": {}}
	var failures: Array[String] = []

	for seed_value in range(1, SEEDS + 1):
		var gen := MansionGenerator.new()
		gen.rng_seed = seed_value
		root.add_child(gen)
		# Let the loose RigidBody3D pickups fall and settle.
		for i in 40:
			await physics_frame

		seen["crowbar"][str(gen._crowbar_spot)] = true
		seen["fuse"][str(gen._fuse_b_spot)] = true
		seen["wrench"][str(gen._small_wrench_spot)] = true
		seen["notebook"][str(gen._notebook_spot)] = true

		# 1. The crowbar must never be locked inside the garage.
		var bar := _find(gen, "Crowbar")
		if bar != null:
			var p := bar.global_position
			if p.x > GARAGE_MIN.x and p.x < GARAGE_MAX.x \
					and p.z > GARAGE_MIN.y and p.z < GARAGE_MAX.y:
				failures.append("seed %d: crowbar inside the garage it unlocks at %s" % [seed_value, p])

		# 2. No pickup may come to rest enclosed in a decor mesh.
		var decor := _decor_boxes(gen)
		# The puzzle box's pendants and clue notes are hunted for by
		# sight, so they matter here as much as the tools do.
		var hunted: Array[String] = ["Crowbar", "Fuse_B", "SmallWrench", "Notebook",
			"ObservatoryLog", "WorkshopScrap"]
		for pd in gen.get_tree().get_nodes_in_group("pendants"):
			hunted.append(pd.name)
		for item_name in hunted:
			var item := _find(gen, item_name)
			if item == null:
				continue
			# Test where the item's VISIBLE geometry ended up, not its
			# origin: a pickup resting on a surface has its origin exactly
			# on the boundary, where floating point makes has_point a
			# coin flip, while its body sits clearly inside.
			var body := _visible_center(item)
			for box in decor:
				if box.has_point(body):
					failures.append("seed %d: %s rests sealed inside a decor mesh (body at %s)" % [
						seed_value, item_name, body])
					break

		gen.queue_free()
		await physics_frame
		if not failures.is_empty():
			break

	if not failures.is_empty():
		print("TEST FAIL: %s" % failures[0])
		for extra in failures.slice(1, 4):
			print("  also: %s" % extra)
		quit(1)
		return

	# Pendants must also be lit: a small dark medallion on a dark floor
	# is unfindable, and three of them is then no hunt at all.
	var lit_check := MansionGenerator.new()
	lit_check.rng_seed = 4242
	root.add_child(lit_check)
	for i in 10:
		await physics_frame
	for pd in lit_check.get_tree().get_nodes_in_group("pendants"):
		var lamp: OmniLight3D = null
		for child in pd.get_children():
			if child is OmniLight3D:
				lamp = child
		var disc := pd.get_node_or_null("Disc") as MeshInstance3D
		if lamp == null or disc == null or disc.material_override == null:
			print("TEST FAIL: pendant %s has no lamp/emissive disc to be spotted by" % pd.name)
			quit(1)
			return
	lit_check.queue_free()
	await physics_frame
	print("pendants: lit and findable")

	# Every authored spot must actually have been exercised above.
	for key in WANT_SPOTS:
		if seen[key].size() != WANT_SPOTS[key]:
			print("TEST FAIL: only saw %d of %d %s spots in %d seeds — coverage gap, raise SEEDS or fix WANT_SPOTS" % [
				seen[key].size(), WANT_SPOTS[key], key, SEEDS])
			quit(1)
			return
		print("%s: all %d spots drawn and clear" % [key, seen[key].size()])

	print("TEST PASS: every seeded item spot is reachable and visible")
	quit(0)


## World-space AABBs of meshes that carry NO collision of their own — the
## ones an item can fall straight through and end up hidden inside.
func _decor_boxes(node: Node) -> Array[AABB]:
	var boxes: Array[AABB] = []
	_collect_decor(node, boxes)
	return boxes


func _collect_decor(node: Node, boxes: Array[AABB]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh := child as MeshInstance3D
			# A mesh under a body is that body's skin, not free-floating decor.
			if not (mesh.get_parent() is CollisionObject3D) and mesh.mesh != null:
				var box: AABB = mesh.global_transform * mesh.get_aabb()
				# Ignore ground slabs and other flat expanses: an item can
				# rest on top of one without being inside it.
				if box.size.y > 0.12 and box.size.x < 6.0 and box.size.z < 6.0:
					boxes.append(box)
		_collect_decor(child, boxes)


## Centre of an item's own mesh geometry in world space (its origin
## usually sits at its base, on whatever it is resting on).
func _visible_center(item: Node3D) -> Vector3:
	var merged := AABB()
	var found := false
	var stack: Array = [item]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var box: AABB = (n as MeshInstance3D).global_transform * (n as MeshInstance3D).get_aabb()
			merged = box if not found else merged.merge(box)
			found = true
		stack.append_array(n.get_children())
	if not found:
		return item.global_position + Vector3(0, 0.08, 0)
	return merged.get_center()


func _find(node: Node, item_name: String) -> Node3D:
	if node.name == item_name and node is Node3D:
		return node
	for child in node.get_children():
		var hit := _find(child, item_name)
		if hit != null:
			return hit
	return null
