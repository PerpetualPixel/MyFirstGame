class_name RoomShroud
extends Node3D

## Fog-of-war for one room: an opaque dark roof slab hides the interior
## from the isometric camera until the player first steps inside, then the
## slab fades out and a warm interior light tweens on.

signal room_revealed

@export var room_extent: float = 10.0
@export var fade_time: float = 0.8
@export var lit_energy: float = 0.8

var revealed := false

var _roof: MeshInstance3D
var _mat := StandardMaterial3D.new()
var _light: OmniLight3D
var _area: Area3D


func _ready() -> void:
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(0.05, 0.045, 0.06, 1.0)

	# The slab is inset inside the walls and sits below the wall tops, so it
	# only ever covers this room's own interior — it can never overhang
	# exterior faces, perimeter doorways, or the porch. It casts no shadow.
	_roof = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(room_extent - 0.4, 0.25, room_extent - 0.4)
	box.material = _mat
	_roof.mesh = box
	_roof.position = Vector3(0, 2.85, 0)
	_roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_roof)

	_light = OmniLight3D.new()
	_light.position = Vector3(0, 2.6, 0)
	_light.omni_range = room_extent * 0.75
	_light.light_energy = 0.0
	_light.light_color = Color(1.0, 0.9, 0.75)
	_light.visible = false  # not in the render list until revealed
	add_child(_light)

	_area = Area3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(room_extent - 0.5, 3.0, room_extent - 0.5)
	col.shape = shape
	col.position = Vector3(0, 1.5, 0)
	_area.add_child(col)
	_area.body_entered.connect(_on_body_entered)
	add_child(_area)


func _on_body_entered(body: Node3D) -> void:
	if not revealed and body is Player:
		reveal()


func reveal() -> void:
	if revealed:
		return
	revealed = true
	_light.visible = true
	# One-shot trigger: stop paying for the overlap test once fired.
	_area.set_deferred("monitoring", false)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_mat, "albedo_color:a", 0.0, fade_time)
	tween.tween_property(_light, "light_energy", lit_energy, fade_time)
	tween.chain().tween_callback(func() -> void: _roof.visible = false)
	room_revealed.emit()
