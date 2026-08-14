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
@export var open_angle_degrees: float = -90.0
@export var swing_time: float = 0.5
## Locked doors show a prompt but refuse to swing (the front double doors
## stay locked until the breaker powers the magnetic lock).
@export var locked: bool = false

var is_open := false

var _closed_yaw: float
var _tween: Tween


func _ready() -> void:
	_closed_yaw = rotation.y

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.28, 0.18)
	mat.roughness = 0.7

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


func get_prompt(_by: Node3D = null) -> String:
	if locked:
		return "Locked tight — no power"
	return "[E] %s" % ("Close Door" if is_open else "Open Door")


func interact(by: Node3D) -> void:
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
	door_toggled.emit(open)


func unlock_and_open() -> void:
	locked = false
	set_open(true)
