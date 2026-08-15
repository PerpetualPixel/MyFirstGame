extends SceneTree
## Footstep regression: all surface samples exist, the surface map is
## right at known estate spots, the character rig's foot bones are found,
## and steps fire from actual foot plants at a walking cadence.
## Run: godot --headless --path . --script res://tests/footstep_test.gd

func _initialize() -> void:
	_run()


func _run() -> void:
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 30:
		await physics_frame
	var player: Player = main.get_node("Players/1")

	# All twelve step samples synthesized.
	for surface in ["wood", "stone", "gravel", "grass"]:
		for v in 3:
			if not AudioSynthesizer.instance._streams.has("step_%s_%d" % [surface, v]):
				print("TEST FAIL: missing footstep sample step_%s_%d" % [surface, v])
				quit(1)
				return

	# Surface map at known estate spots.
	var expect := {
		Vector3(0, 0, 0): "wood",          # foyer/parlor floors
		Vector3(-12, 0, -12): "wood",
		Vector3(0, 0, 18): "stone",        # porch slab
		Vector3(0, 0, 29): "stone",        # cobble walkway
		Vector3(9.5, 0, 28.5): "gravel",   # driveway
		Vector3(22.5, 0, 20.5): "stone",   # garage slab
		Vector3(-24, 0, 24): "grass",      # west lawn (toy rocket)
		Vector3(27, 0, 25): "grass",       # junk lot behind the garage
	}
	for at in expect:
		var got: String = player._surface_at(at)
		if got != expect[at]:
			print("TEST FAIL: surface at %s = %s (want %s)" % [at, got, expect[at]])
			quit(1)
			return

	# Foot bones located on the rig (steps then come from foot plants).
	player._find_foot_bones()
	if player._foot_skeleton == null or player._foot_bones.size() != 2:
		print("TEST FAIL: foot bones not found on the character skeleton")
		quit(1)
		return

	# Standing still on the open west lawn: no steps at all.
	player.teleport(Vector3(-20, 0.1, 30))
	for i in 60:
		await physics_frame
	var idle_steps: int = player.footsteps_played
	if idle_steps != 0:
		print("TEST FAIL: %d footsteps fired while standing still" % idle_steps)
		quit(1)
		return

	# Walk north across the lawn for 2.4 s: a walk cadence lands ~1.5-2.8
	# steps per second (the old 1.5 m timer gave ~1/s and never lined up
	# with the feet). Only seconds actually spent moving count.
	Input.action_press("move_up")
	var moving_frames := 0
	for i in 144:
		await physics_frame
		if Vector2(player.velocity.x, player.velocity.z).length() > 0.3:
			moving_frames += 1
	Input.action_release("move_up")
	var walked: int = player.footsteps_played
	var moving_seconds := float(moving_frames) / 60.0
	var per_second := float(walked) / maxf(moving_seconds, 0.1)
	print("footsteps: %d in %.2f s of walking (%.2f/s)" % [walked, moving_seconds, per_second])
	if moving_seconds < 1.5:
		print("TEST FAIL: player barely moved (%.2f s) — blocked test route" % moving_seconds)
		quit(1)
		return
	if per_second < 1.4 or per_second > 2.8:
		print("TEST FAIL: footstep cadence %.2f/s outside a walking rhythm" % per_second)
		quit(1)
		return
	print("TEST PASS: footsteps sync to foot plants and match the surface")
	quit(0)
