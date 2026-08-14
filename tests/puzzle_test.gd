extends SceneTree
## Laser mirror-maze regression: five mirrors exist (4 route + 1 decoy),
## closed doors block the beam, and aligning the four route mirrors to
## their 45-degree solution threads the beam around the privacy screen,
## through the doorframes, and into the receiver.
## Run: godot --headless --path . --script res://tests/puzzle_test.gd

const ROUTE_SPOTS := [
	Vector3(-10, 0, 3), Vector3(-7, 0, 3), Vector3(-7, 0, 0), Vector3(0, 0, 0),
]

func _initialize() -> void:
	_run()


func _run() -> void:
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 30:
		await physics_frame

	var mirrors: Array = []
	var receivers: Array = []
	var emitters: Array = []
	_collect(main, mirrors, receivers, emitters)
	print("found: %d emitter(s), %d mirror(s), %d receiver(s)" % [emitters.size(), mirrors.size(), receivers.size()])
	if emitters.size() != 1 or mirrors.size() != 5 or receivers.size() != 1:
		print("TEST FAIL: unexpected puzzle element counts")
		quit(1)
		return
	var receiver: LightReceiver = receivers[0]

	# Align the whole route; with doors closed the beam must stay blocked.
	var route: Array = []
	for spot in ROUTE_SPOTS:
		var m := _mirror_near(mirrors, spot)
		if m == null:
			print("TEST FAIL: no mirror at expected spot %s" % spot)
			quit(1)
			return
		# Panels are 45 degrees local: root yaw 0 is the solved detent.
		m.rotation.y = 0.0
		route.append(m)
	for i in 60:
		await physics_frame
	if receiver.is_solved:
		print("TEST FAIL: beam reached receiver through CLOSED doors")
		quit(1)
		return

	var doors := _find_doors(main)
	print("opening %d hinged door(s)" % doors.size())
	for door in doors:
		door.set_open(true)
	for i in 120:
		await physics_frame

	if not receiver.is_solved:
		print("TEST FAIL: aligned maze route did not solve the receiver")
		quit(1)
		return
	print("TEST PASS: mirror maze threads the beam to the receiver")
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
