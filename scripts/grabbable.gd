class_name Grabbable
extends Interactable

## Interactable meant for RigidBody3D nodes: [E] picks it up and parents it
## to the player's hold point; [E] again drops it back into the world with
## physics re-enabled. The player owns the carry logic (pick_up/drop_held);
## this script owns the body state (freeze, collision, reparenting).

signal grabbed(by: Node3D)
signal dropped(by: Node3D)

## Who is currently carrying this, or null when it's loose in the world.
var holder: Node3D = null

## True once this tool's job is done (crowbar after the pry, wrench
## after the valves lock). The HUD crosses the item out so players know
## it is safe to drop.
var spent := false

var _body: RigidBody3D
var _original_layer: int
var _original_mask: int
var _original_parent: Node


func _ready() -> void:
	# The analyzer rejects a direct `self as RigidBody3D` (RigidBody3D is not
	# on this script's declared base chain), so widen to Node first.
	var node: Node = self
	_body = node as RigidBody3D
	assert(_body != null, "Grabbable must be attached to a RigidBody3D")


func can_interact(_by: Node3D) -> bool:
	return holder == null


## Drop-position hardening: never release an item inside a wall or over
## the void. A ray from the carrier's chest to the drop point pulls the
## item back in front of any wall it would clip through, and a downward
## ray guarantees there is floor beneath (else drop at the carrier's feet).
func _safe_drop_position(carrier: Node3D) -> Vector3:
	var pos := global_position
	var space := get_world_3d().direct_space_state
	if carrier != null and is_instance_valid(carrier):
		var chest: Vector3 = carrier.global_position + Vector3(0, 1.0, 0)
		var wall_query := PhysicsRayQueryParameters3D.create(chest, pos)
		wall_query.exclude = [get_rid()]
		var wall_hit := space.intersect_ray(wall_query)
		if not wall_hit.is_empty():
			pos = wall_hit["position"] + (wall_hit["normal"] as Vector3) * 0.25
	var floor_query := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.5, 0), pos + Vector3(0, -6.0, 0))
	floor_query.exclude = [get_rid()]
	var floor_hit := space.intersect_ray(floor_query)
	if floor_hit.is_empty():
		# No floor below (over the void): drop at the carrier's feet.
		if carrier != null and is_instance_valid(carrier):
			return carrier.global_position + Vector3(0, 0.4, 0)
		return pos
	return Vector3(pos.x, maxf(pos.y, (floor_hit["position"] as Vector3).y + 0.25), pos.z)


func get_prompt(by: Node3D = null) -> String:
	if by != null and by.has_method("inventory_full") and by.inventory_full():
		return "Pack Full"
	return "[E] Take %s" % display_name


func interact(by: Node3D) -> void:
	if holder == null and by.has_method("pick_up"):
		by.pick_up(self)
	super.interact(by)


## Vanish into a carrier's pack: frozen, collision off, hidden, riding
## the carrier node until released, mounted, or consumed.
func stash(by: Node3D) -> void:
	holder = by
	_original_parent = get_parent()
	_original_layer = _body.collision_layer
	_original_mask = _body.collision_mask
	_body.collision_layer = 0
	_body.collision_mask = 0
	_body.freeze = true
	visible = false
	reparent(by)
	transform = Transform3D.IDENTITY
	grabbed.emit(by)


## Park this item inside a mechanism (frozen, no collision, visible) —
## e.g. a gear seated in a clock socket or the battery in its cradle.
## release() later pops it back into the world.
func mount(parent_node: Node3D, offset := Vector3.ZERO) -> void:
	if holder != null and holder.has_method("inventory_remove"):
		holder.inventory_remove(self)
	holder = null
	visible = true
	reparent(parent_node)
	transform = Transform3D(Basis.IDENTITY, offset)


## Detach from the carrier (or mechanism) and resume physics in place.
func release() -> void:
	var was_holder := holder
	if was_holder != null and was_holder.has_method("inventory_remove"):
		was_holder.inventory_remove(self)
	holder = null
	visible = true
	# Return to wherever we lived before being grabbed; fall back to the
	# current scene if that node is gone (e.g. regenerated level).
	var drop_parent: Node = _original_parent if is_instance_valid(_original_parent) else get_tree().current_scene
	reparent(drop_parent)
	global_position = _safe_drop_position(was_holder)
	_body.collision_layer = _original_layer
	_body.collision_mask = _original_mask
	_body.freeze = false
	_body.linear_velocity = Vector3.ZERO
	_body.angular_velocity = Vector3.ZERO
	dropped.emit(was_holder)
