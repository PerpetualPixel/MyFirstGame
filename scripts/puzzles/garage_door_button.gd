class_name GarageDoorButton
extends Interactable

## Wall button beside the garage's rolling door. Dead until the fuse
## panel restores power; then one press rolls the door up. Runs on every
## co-op peer via the shared interaction RPC, so the door lifts for both.

var powered := false
var opened := false
## The rolling door assembly (meshes + collision) the press lifts.
var roll_door: Node3D


func power_on() -> void:
	powered = true


func can_interact(_by: Node3D) -> bool:
	return not opened


func get_prompt(_by: Node3D = null) -> String:
	if not powered:
		return "Door button — dead, no power"
	return "[E] Open Garage Door"


func interact(by: Node3D) -> void:
	if not powered or opened or roll_door == null:
		return
	opened = true
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(roll_door, "position:y", roll_door.position.y + 2.25, 1.6)
	AudioSynthesizer.play_at("ratchet", global_position, -4.0, 0.5)
	Player.shake(0.15, global_position)
	super.interact(by)
