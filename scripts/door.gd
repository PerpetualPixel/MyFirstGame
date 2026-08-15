class_name Door
extends Interactable

## Hinged door. The root sits at the hinge; the panel (mesh + collision,
## built in _ready from the exports) extends along local +X. [E] swings it
## 90 degrees with a tween. Because the panel is a physics body, a closed
## door blocks laser raycasts and an open one lets the beam through.

signal door_toggled(open: bool)

@export var panel_width: float = 2.0
@export var panel_height: float = 2.35
@export var panel_thickness: float = 0.12
## Panel finish; default is interior wood. (The garage's side door is a
## plain white external door, for example.)
@export var panel_color: Color = Color(0.4, 0.28, 0.18)
@export var open_angle_degrees: float = -90.0
@export var swing_time: float = 0.5
## Locked doors show a prompt but refuse to swing (the front double doors
## stay locked until the breaker powers the magnetic lock).
@export var locked: bool = false
## When non-empty, a held item from this group pries the door open even
## while locked (e.g. the garage side door yields to a crowbar).
@export var pry_group := ""

var is_open := false

var _closed_yaw: float
var _tween: Tween


func _ready() -> void:
	_closed_yaw = rotation.y

	var mat := StandardMaterial3D.new()
	mat.albedo_color = panel_color
	mat.roughness = 0.7

	# Door panels join the camera-fade system so a door never hides the
	# player. The fade code reads material/footprint via metadata since
	# doors are not CSG boxes (and swing, hence the square footprint).
	add_to_group("fade_walls")
	set_meta("fade_material", mat)
	set_meta("fade_size", Vector3(panel_width, panel_height, panel_width))

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(panel_width, panel_height, panel_thickness)
	box.material = mat
	mesh.mesh = box
	mesh.position = Vector3(panel_width / 2.0, panel_height / 2.0 + 0.02, 0)
	add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	col.position = mesh.position
	add_child(col)

	# Brass handles on both faces near the free edge.
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.75, 0.6, 0.25)
	hmat.metallic = 0.8
	hmat.roughness = 0.3
	for side in [1.0, -1.0]:
		var handle := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.045
		sph.height = 0.09
		sph.material = hmat
		handle.mesh = sph
		handle.position = Vector3(panel_width - 0.14, 1.05, side * (panel_thickness / 2.0 + 0.03))
		add_child(handle)


func get_prompt(by: Node3D = null) -> String:
	if locked:
		if pry_group != "":
			if by != null and _held_pry_tool(by) != null:
				return "[E] Pry Open"
			return "Jammed shut — needs something to pry it"
		return "Locked tight — no power"
	return "[E] %s" % ("Close Door" if is_open else "Open Door")


func interact(by: Node3D) -> void:
	if locked and pry_group != "" and by != null and _held_pry_tool(by) != null:
		# Crowbar wins: force the latch with a groan and a burst of dust.
		# The tool's job is done — the HUD crosses it out.
		locked = false
		_held_pry_tool(by).set("spent", true)
		AudioSynthesizer.play_at("ratchet", global_position, -2.0, 0.55)
		_dust_puff(global_position + global_transform.basis.x * (panel_width / 2.0), 16)
	if locked:
		return
	if not is_open and by != null:
		# Swing away from whoever opens it: the panel's thickness axis is
		# local Z, and +90 deg sends the panel toward local -Z. So a player
		# on the +Z side gets +90 (away), and vice versa — the door never
		# swings into the opener's face.
		var side := to_local(by.global_position).z
		open_angle_degrees = 90.0 if side > 0.0 else -90.0
	set_open(not is_open)
	super.interact(by)


func set_open(open: bool) -> void:
	if is_open == open:
		return
	is_open = open
	if _tween:
		_tween.kill()
	var target := (_closed_yaw + deg_to_rad(open_angle_degrees)) if open else _closed_yaw
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "rotation:y", target, swing_time)
	AudioSynthesizer.play_at("tick", global_position, -6.0, 0.7)  # crisp latch click
	Player.shake(0.12, global_position)
	_dust_puff(global_position + global_transform.basis.x * (panel_width / 2.0), 10)
	door_toggled.emit(open)


## Soft dust puff at floor level (also used by the vault gate).
static func _dust_puff(at: Vector3, amount: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return
	var puff := GPUParticles3D.new()
	puff.amount = amount
	puff.lifetime = 0.9
	puff.one_shot = true
	puff.explosiveness = 1.0
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 80.0
	mat.initial_velocity_min = 0.4
	mat.initial_velocity_max = 1.1
	mat.gravity = Vector3(0, -0.6, 0)
	mat.scale_min = 0.6
	mat.scale_max = 1.4
	puff.process_material = mat
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.85, 0.82, 0.75, 0.4)
	mesh.material = m
	puff.draw_pass_1 = mesh
	puff.position = Vector3(at.x, 0.1, at.z)
	tree.current_scene.add_child(puff)
	puff.emitting = true
	tree.create_timer(1.5).timeout.connect(puff.queue_free)


func unlock_and_open() -> void:
	locked = false
	set_open(true)


func _held_pry_tool(by: Node3D) -> Node:
	if by != null and by.has_method("inventory_find"):
		return by.inventory_find(pry_group)
	return null
