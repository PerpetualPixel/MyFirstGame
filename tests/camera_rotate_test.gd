extends SceneTree
## Regression test for the [Q] camera swing: each discrete press turns
## the pivot exactly 90 degrees, and mashing the key mid-swing queues at
## most ONE extra quarter-turn instead of banking unlimited spins.
## Run: godot --headless --path . --script res://tests/camera_rotate_test.gd

func _initialize() -> void:
	_run()


func _run() -> void:
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 30:
		await physics_frame
	var player: Player = main.get_node("Players/1")
	var pivot: Node3D = player.camera_pivot
	# The unwrapped shadow yaw is the logic's source of truth (the node's
	# rotation.y legitimately wraps into (-PI, PI], which was the bug).
	var y0: float = player._yaw_current

	# One press -> exactly one quarter-turn once the tween settles.
	_press_q()
	for i in 45:
		await physics_frame
	if absf(player._yaw_current - (y0 + PI / 2.0)) > 0.01:
		print("TEST FAIL: first press swung %.3f rad (want %.3f)" % [player._yaw_current - y0, PI / 2.0])
		quit(1)
		return

	# A second discrete press -> another exact quarter-turn, even where
	# the naive node-rotation readback would have wrapped negative.
	_press_q()
	for i in 45:
		await physics_frame
	if absf(player._yaw_current - (y0 + PI)) > 0.01:
		print("TEST FAIL: second press swung to %.3f rad total (want %.3f)" % [player._yaw_current - y0, PI])
		quit(1)
		return

	# Mash three presses inside one swing: the first plays, the second
	# queues, the third must be swallowed -> two quarter-turns total.
	_press_q()
	await physics_frame
	_press_q()
	await physics_frame
	_press_q()
	for i in 90:
		await physics_frame
	if absf(player._yaw_current - (y0 + PI * 2.0)) > 0.01:
		print("TEST FAIL: mashed presses swung to %.3f rad total (want %.3f)" % [player._yaw_current - y0, PI * 2.0])
		quit(1)
		return
	# And the node itself must sit at the same angle, modulo full turns.
	if absf(wrapf(pivot.rotation.y - y0, -PI, PI)) > 0.01:
		print("TEST FAIL: pivot node disagrees with the shadow yaw")
		quit(1)
		return

	print("TEST PASS: camera rotates one exact quarter-turn per press, mash-capped")
	quit(0)


func _press_q() -> void:
	var down := InputEventKey.new()
	down.keycode = KEY_Q
	down.physical_keycode = KEY_Q
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.keycode = KEY_Q
	up.physical_keycode = KEY_Q
	up.pressed = false
	Input.parse_input_event(up)
