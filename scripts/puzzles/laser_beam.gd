class_name LaserBeam
extends Node3D

## One visible laser segment: raycasts along -Z and stretches a glowing
## cylinder to the hit point. The emitter and each mirror own one of these,
## so a bounced beam is a chain of LaserBeam segments.
## dispatch() forwards a hit to whatever was struck (mirror or receiver).

@export var max_range: float = 40.0
@export var beam_radius: float = 0.05
@export var color: Color = Color(0.35, 1.0, 1.0)

var _ray: RayCast3D
var _visual: MeshInstance3D


func _ready() -> void:
	_ray = RayCast3D.new()
	_ray.enabled = false  # updated manually with force_raycast_update()
	_ray.collide_with_areas = false
	add_child(_ray)

	var mesh := CylinderMesh.new()
	mesh.top_radius = beam_radius
	mesh.bottom_radius = beam_radius
	mesh.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.5
	mesh.material = mat

	_visual = MeshInstance3D.new()
	_visual.mesh = mesh
	_visual.rotation_degrees = Vector3(-90, 0, 0)  # cylinder Y axis -> node -Z
	add_child(_visual)
	visible = false


## Keep the ray from hitting its own emitter/mirror body.
func add_exception(body: CollisionObject3D) -> void:
	_ray.add_exception(body)


## Cast from a world-space point along dir, show the beam, and return hit
## info {collider, point, normal} — or an empty Dictionary on a miss.
func fire(from: Vector3, dir: Vector3) -> Dictionary:
	global_position = from
	look_at(from + dir)
	_ray.target_position = Vector3(0, 0, -max_range)
	_ray.force_raycast_update()

	var length := max_range
	var hit := {}
	if _ray.is_colliding():
		var point := _ray.get_collision_point()
		length = maxf(from.distance_to(point), 0.05)
		hit = {
			"collider": _ray.get_collider(),
			"point": point,
			"normal": _ray.get_collision_normal(),
		}
	_visual.position = Vector3(0, 0, -length / 2.0)
	_visual.scale = Vector3(1, length, 1)
	visible = true
	return hit


func shut_off() -> void:
	visible = false


## Forward a beam hit to the struck object. Duck-typed so beam logic has no
## hard dependency on the mirror/receiver classes.
static func dispatch(hit: Dictionary, dir: Vector3, bounces_left: int) -> void:
	if hit.is_empty():
		return
	var collider: Object = hit["collider"]
	if collider == null:
		return
	if collider.has_method("reflect_beam"):
		collider.reflect_beam(dir, hit["point"], hit["normal"], bounces_left)
	elif collider.has_method("beam_hit"):
		collider.beam_hit()
