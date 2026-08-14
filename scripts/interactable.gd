class_name Interactable
extends CollisionObject3D

## Base class for anything the player can target with [E].
## Attach a subclass to any CollisionObject3D-derived node (Area3D,
## StaticBody3D, RigidBody3D, ...) so the player's InteractionArea can
## detect it. Subclasses override interact().

signal interacted(by: Node3D)

@export var display_name: String = "Interactable"
## Verb shown in the floating "[E] ..." prompt.
@export var prompt_action: String = "Use"
## How far above the object's origin the prompt floats.
@export var prompt_height: float = 1.6


## Text for the player's floating prompt while this object is in reach.
## `by` is the asking player, so prompts can react to what they're holding.
func get_prompt(_by: Node3D = null) -> String:
	return "[E] %s" % prompt_action


## Called by the player when [E] is pressed with this object in reach.
func interact(by: Node3D) -> void:
	interacted.emit(by)


## Subclasses can override to make interaction conditional.
func can_interact(_by: Node3D) -> bool:
	return true
