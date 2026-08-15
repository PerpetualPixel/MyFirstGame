class_name ToyBox
extends Interactable

## Metal toy-parts crate on the west lawn. [E] flips the lid open once,
## releasing whatever was packed inside (the generator stashes a spare
## fuse there, frozen and non-colliding until revealed).

signal box_opened

var opened := false
## Item packed inside; set by the generator before the run starts.
## Untyped on purpose: Grabbable's script base chain (CollisionObject3D)
## and RigidBody3D are sibling types to the analyzer.
var stash: Node = null

@onready var _lid: Node3D = $Lid


func can_interact(_by: Node3D) -> bool:
	return not opened


func get_prompt(_by: Node3D = null) -> String:
	return "[E] Open Toy Crate"


func interact(by: Node3D) -> void:
	if opened:
		return
	opened = true
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_lid, "rotation:x", -1.85, 0.45)
	AudioSynthesizer.play_at("ratchet", global_position, -6.0, 0.8)
	if stash != null:
		# Pop the contents onto the crate's rim, physics restored.
		stash.freeze = false
		stash.collision_layer = 1
		stash.collision_mask = 1
		stash.global_position = global_position + Vector3(0, 0.75, 0)
	box_opened.emit()
	super.interact(by)
