extends SceneTree
## Renders every pack item's inventory icon FROM ITS ACTUAL 3D MODEL, so
## the picture in the slot can never drift from the thing you picked up.
## Each item is posed at a three-quarter angle in a transparent
## SubViewport, framed from its own bounding box, and written to
## assets/ui/items/.
## Run (NOT headless — it needs a renderer):
##   godot --path . --script res://tools/render_item_icons.gd --rendering-driver opengl3

const OUT_DIR := "res://assets/ui/items"
const SIZE := 192

## scene -> output name. Pendants are rendered once per symbol so the slot
## shows the sky-mark you are actually carrying.
const ITEMS := [
	["res://scenes/Crowbar.tscn", "crowbar", ""],
	["res://scenes/Fuse.tscn", "fuse", ""],
	["res://scenes/SmallWrench.tscn", "small_wrench", ""],
	["res://scenes/BrassWrench.tscn", "brass_wrench", ""],
	["res://scenes/WillItem.tscn", "will", ""],
	["res://scenes/BigBattery.tscn", "battery", ""],
	["res://scenes/Prism.tscn", "prism", ""],
	["res://scenes/AstralPendant.tscn", "pendant_sun", "sun"],
	["res://scenes/AstralPendant.tscn", "pendant_moon", "moon"],
	["res://scenes/AstralPendant.tscn", "pendant_star", "star"],
	["res://scenes/AstralPendant.tscn", "pendant_comet", "comet"],
]


func _initialize() -> void:
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for entry in ITEMS:
		await _render(entry[0], entry[1], entry[2])
	print("ICONS DONE")
	quit(0)


func _render(scene_path: String, out_name: String, symbol: String) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	# Neutral studio light: a key from the front-left plus flat ambient, so
	# every item reads at the same brightness whatever the mansion is doing.
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CANVAS
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.72, 0.72, 0.78)
	e.ambient_light_energy = 1.5
	env.environment = e
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.light_energy = 2.2
	key.rotation_degrees = Vector3(-38, -46, 0)
	vp.add_child(key)

	var pivot := Node3D.new()
	vp.add_child(pivot)
	var item: Node3D = (load(scene_path) as PackedScene).instantiate()
	if symbol != "":
		item.set("pendant_symbol", symbol)
	item.set("freeze", true)
	pivot.add_child(item)
	item.rotation = Vector3.ZERO
	await process_frame
	await process_frame

	# Frame from the model's real bounds: long tools fill the frame the
	# same way squat ones do.
	var box := _merged_aabb(item)
	var centre := box.get_center()
	var radius := maxf(box.size.length() * 0.5, 0.05)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = radius * 2.15
	vp.add_child(cam)
	# Three-quarter view, and long thin items get turned to lie across the
	# frame diagonally instead of vanishing edge-on.
	var yaw := 35.0 if box.size.x >= box.size.z else -55.0
	cam.rotation_degrees = Vector3(-28, yaw, 0)
	cam.global_position = centre - cam.global_transform.basis.z * -(radius * 3.0)
	cam.look_at(centre)
	await process_frame
	await process_frame
	await process_frame

	var img := vp.get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, out_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("rendered %s (bounds %.2f)" % [path, radius])
	vp.queue_free()
	await process_frame


## World-space bounds of every mesh under `node`.
func _merged_aabb(node: Node) -> AABB:
	var merged := AABB()
	var found := false
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var m := n as MeshInstance3D
			var b: AABB = m.global_transform * m.get_aabb()
			merged = b if not found else merged.merge(b)
			found = true
		stack.append_array(n.get_children())
	return merged if found else AABB(Vector3(-0.2, -0.2, -0.2), Vector3(0.4, 0.4, 0.4))
