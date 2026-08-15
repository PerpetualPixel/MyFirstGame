extends SceneTree
## Headless regression test for the Grabbable pickup/drop flow.
## Run from the project root:
##   godot --headless --path . --script res://tests/pickup_test.gd

func _initialize() -> void:
	_run()


func _run() -> void:
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)

	# The cog is a test-only prop (no longer shipped in Main): spawn it
	# where it used to sit on the porch.
	var test_cog: Grabbable = (load("res://scenes/BrassCog.tscn") as PackedScene).instantiate()
	test_cog.name = "BrassCog"
	test_cog.position = Vector3(2, 0.6, 10)
	main.add_child(test_cog)

	# Let the mansion generate and the cog fall asleep on the floor (the
	# worst case for area detection).
	for i in 120:
		await physics_frame

	var player: Player = main.get_node("Players/1")
	var cog: Grabbable = main.get_node_or_null("BrassCog")
	if cog == null:
		print("TEST FAIL: BrassCog not found in Main scene")
		quit(1)
		return
	print("cog resting at: ", cog.global_position)

	# Stand 1 m south of the cog; with no input the player keeps rotation 0,
	# which faces -Z, i.e. straight at the cog.
	player.teleport(Vector3(cog.global_position.x, 0.1, cog.global_position.z + 1.0))
	player.rotation.y = 0.0
	for i in 10:
		await physics_frame

	var target := player.get_nearest_interactable()
	print("nearest interactable: ", target)
	if target != cog:
		print("TEST FAIL: cog not detected by InteractionArea")
		quit(1)
		return

	target.interact(player)
	await physics_frame
	if not player.inventory.has(cog) or cog.get_parent() != player or cog.visible:
		print("TEST FAIL: interact() did not stow the cog (in pack=%s, parent=%s, visible=%s)" % [player.inventory.has(cog), cog.get_parent(), cog.visible])
		quit(1)
		return
	print("packed OK, cog riding: ", cog.get_parent().name)

	player.drop_held()
	for i in 30:
		await physics_frame
	if not player.inventory.is_empty() or not cog.visible:
		print("TEST FAIL: pack not cleared (or cog invisible) after drop")
		quit(1)
		return
	if cog.global_position.y > 0.5:
		print("TEST FAIL: cog did not fall back to the floor after drop (y=%f)" % cog.global_position.y)
		quit(1)
		return
	print("dropped OK, cog resting at: ", cog.global_position)
	print("TEST PASS")
	quit(0)
