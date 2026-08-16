extends SceneTree
## Verifies the Sophie character integration: model normalized (~1.8 m,
## feet on ground, centered), walk animation registered/looped/in-place,
## playback driven by velocity, HoldPoint at the chest, carrying intact.
## Run: godot --headless --path . --script res://tests/character_test.gd

func _initialize() -> void:
	_run()


func _run() -> void:
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 30:
		await physics_frame

	var player: Player = main.get_node("Players/1")
	var visual: Node3D = player.get_node_or_null("CharacterVisual")
	if visual == null or player.get_node_or_null("MeshInstance3D") != null:
		print("TEST FAIL: visual node wrong (Sophie missing or capsule present)")
		quit(1)
		return

	# --- Normalization: merged world AABB relative to the body ---
	var merged := AABB()
	var first := true
	var stack: Array = [visual]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and node.mesh != null:
			var box: AABB = node.global_transform * node.get_aabb()
			merged = box if first else merged.merge(box)
			first = false
		stack.append_array(node.get_children())
	var feet := merged.position.y - player.global_position.y
	var height := merged.size.y
	var center := merged.get_center() - player.global_position
	print("height=%.3f feet=%.3f center_off=(%.3f, %.3f)" % [height, feet, center.x, center.z])
	if absf(height - 1.8) > 0.05 or absf(feet) > 0.15 or absf(center.x) > 0.25 or absf(center.z) > 0.25:
		print("TEST FAIL: model not normalized")
		quit(1)
		return

	# --- Animation wiring ---
	if player._anim_player == null or player._walk_anim != "moves/walk":
		print("TEST FAIL: walk animation not registered (walk='%s')" % player._walk_anim)
		quit(1)
		return
	var walk: Animation = player._anim_player.get_animation(player._walk_anim)
	if walk.loop_mode != Animation.LOOP_LINEAR:
		print("TEST FAIL: walk animation does not loop")
		quit(1)
		return
	for i in walk.get_track_count():
		if walk.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		if not str(walk.track_get_path(i)).to_lower().contains("hips"):
			continue
		var kc := walk.track_get_key_count(i)
		var a: Vector3 = walk.track_get_key_value(i, 0)
		var b: Vector3 = walk.track_get_key_value(i, kc - 1)
		if Vector2(b.x - a.x, b.z - a.z).length() > 0.01:
			print("TEST FAIL: walk cycle still travels (hips move %.2f m)" % Vector2(b.x - a.x, b.z - a.z).length())
			quit(1)
			return

	if player._idle_anim != "moves/idle":
		print("TEST FAIL: idle animation not registered (idle='%s')" % player._idle_anim)
		quit(1)
		return

	# --- Velocity drives playback (no awaits between these calls) ---
	player.velocity = Vector3(0, 0, -6)
	player._animate_visual(0.016)
	if not player._anim_player.is_playing() or player._anim_player.current_animation != player._walk_anim:
		print("TEST FAIL: walk did not play while moving")
		quit(1)
		return
	player.velocity = Vector3.ZERO
	player._animate_visual(0.016)
	if not player._anim_player.is_playing() or player._anim_player.current_animation != player._idle_anim:
		print("TEST FAIL: idle did not play while stationary (playing '%s')" % player._anim_player.current_animation)
		quit(1)
		return

	# --- One-shot actions play and are cancelled by movement ---
	player.play_action("moves/open_door")
	player._animate_visual(0.016)
	if player._anim_player.current_animation != "moves/open_door":
		print("TEST FAIL: open_door action did not play")
		quit(1)
		return
	player.velocity = Vector3(0, 0, -6)
	player._animate_visual(0.016)
	if player._anim_player.current_animation != player._walk_anim:
		print("TEST FAIL: movement did not cancel the action back into walk")
		quit(1)
		return
	player.velocity = Vector3.ZERO
	print("animation wiring OK")

	# --- HoldPoint & carrying ---
	var hold_point: Node3D = player.get_node("HoldPoint")
	if not hold_point.position.is_equal_approx(Vector3(0, 1.0, -0.35)):
		print("TEST FAIL: HoldPoint not at chest (found %s)" % hold_point.position)
		quit(1)
		return
	var cog: Grabbable = (load("res://scenes/BrassCog.tscn") as PackedScene).instantiate()
	cog.name = "BrassCog"
	cog.position = Vector3(2, 0.6, 10)
	main.add_child(cog)
	for i in 20:
		await physics_frame
	player.teleport(cog.global_position + Vector3(0, 0, 1.0))
	for i in 10:
		await physics_frame
	player.pick_up(cog)
	if not player.inventory.has(cog) or cog.get_parent() != player or cog.visible:
		print("TEST FAIL: item did not stow into the pack")
		quit(1)
		return
	# Floor items get the crouched clip, higher ones the standing reach.
	if not player._anim_player.current_animation in ["moves/pick_up", "moves/pick_up_object"]:
		print("TEST FAIL: pick_up action did not play on pickup (got %s)" % player._anim_player.current_animation)
		quit(1)
		return

	print("TEST PASS: Sophie integrated with animations")
	quit(0)
