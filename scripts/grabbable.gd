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


func get_prompt(by: Node3D = null) -> String:
	if by != null and by.get("held_item") != null:
		return "Hands Full"
	return "[E] Pick up %s" % display_name


func interact(by: Node3D) -> void:
	if holder == null and by.has_method("pick_up"):
		by.pick_up(self)
	super.interact(by)


## Freeze physics and attach to the carrier's hold point.
func grab(by: Node3D, hold_point: Node3D) -> void:
	holder = by
	_original_parent = get_parent()
	_original_layer = _body.collision_layer
	_original_mask = _body.collision_mask
	_body.collision_layer = 0
	_body.collision_mask = 0
	_body.freeze = true
	reparent(hold_point)
	transform = Transform3D.IDENTITY
	grabbed.emit(by)


## Park this item inside a mechanism (frozen, no collision) — e.g. a gear
## seated in a clock socket. release() later pops it back into the world.
func mount(parent_node: Node3D, offset := Vector3.ZERO) -> void:
	holder = null
	reparent(parent_node)
	transform = Transform3D(Basis.IDENTITY, offset)


## Detach from the carrier and resume physics where the hold point is.
func release() -> void:
	var was_holder := holder
	holder = null
	# Return to wherever we lived before being grabbed; fall back to the
	# current scene if that node is gone (e.g. regenerated level).
	var drop_parent: Node = _original_parent if is_instance_valid(_original_parent) else get_tree().current_scene
	reparent(drop_parent)
	_body.collision_layer = _original_layer
	_body.collision_mask = _original_mask
	_body.freeze = false
	_body.linear_velocity = Vector3.ZERO
	_body.angular_velocity = Vector3.ZERO
	dropped.emit(was_holder)
