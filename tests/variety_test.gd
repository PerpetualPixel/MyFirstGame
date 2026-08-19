extends SceneTree
## Run-variety regression: generates the mansion under several fixed seeds
## and asserts (a) layouts genuinely differ across seeds — routes, valve
## rooms, puzzle box wall slot, item spawn spots, strongbox combination —
## and (b) the same seed reproduces the exact same layout (determinism).
## Run: godot --headless --path . --script res://tests/variety_test.gd

const SEEDS := [11, 22, 33, 44, 55, 66]

func _initialize() -> void:
	_run()


func _run() -> void:
	var snapshots: Array = []
	for seed_value in SEEDS:
		snapshots.append(await _generate_snapshot(seed_value))
	for i in SEEDS.size():
		print("seed %d -> %s" % [SEEDS[i], snapshots[i]])

	# Determinism: regenerating the first seed must reproduce it exactly.
	var again: Dictionary = await _generate_snapshot(SEEDS[0])
	if str(again) != str(snapshots[0]):
		print("TEST FAIL: same seed produced a different layout")
		quit(1)
		return

	var routes := {}
	var valves := {}
	var boxes := {}
	var decoys := {}
	var crowbars := {}
	var lock_codes := {}
	for s in snapshots:
		routes[s["route"]] = true
		valves[str(s["valves"])] = true
		boxes[str(s["puzzle_box"])] = true
		decoys[str(s["decoy"])] = true
		crowbars[str(s["crowbar"])] = true
		lock_codes[str(s["lockbox"])] = true
	print("distinct across %d seeds: routes=%d valve_pairs=%d puzzle_box_spots=%d decoys=%d crowbar_spots=%d lockbox_codes=%d" % [
		SEEDS.size(), routes.size(), valves.size(), boxes.size(), decoys.size(), crowbars.size(), lock_codes.size()])
	if routes.size() < 2 or valves.size() < 2 or boxes.size() < 2 \
			or crowbars.size() < 2 or lock_codes.size() < 2:
		print("TEST FAIL: insufficient layout variety across seeds")
		quit(1)
		return

	print("TEST PASS: runs vary by seed and reproduce deterministically")
	quit(0)


func _generate_snapshot(seed_value: int) -> Dictionary:
	var gen := MansionGenerator.new()
	gen.rng_seed = seed_value
	root.add_child(gen)
	await physics_frame
	var snapshot := {
		"route": gen.active_route["name"],
		"valves": str(gen._valve_cells),
		"puzzle_box": str(gen._puzzle_box_pos),
		"decoy": str(gen._decoy_cell),
		"door_count": gen._doors.size(),
		"crowbar": str(gen._crowbar_spot),
		"fuse": str(gen._fuse_b_spot),
		"wrench": str(gen._small_wrench_spot),
		"notebook": str(gen._notebook_spot),
		"lockbox": str(gen._lockbox_code),
	}
	gen.queue_free()
	await physics_frame
	await physics_frame
	return snapshot
