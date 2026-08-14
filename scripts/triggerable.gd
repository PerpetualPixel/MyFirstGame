class_name Triggerable
extends Interactable

## Interactable that toggles on/off when the player presses [E].
## Wire the signals to doors, lights, mechanisms, etc.

signal activated(by: Node3D)
signal deactivated(by: Node3D)
signal toggled(is_on: bool, by: Node3D)

@export var starts_on: bool = false
## When true, the first activation locks it on; further presses do nothing.
@export var one_shot: bool = false

var is_on: bool = false


func _ready() -> void:
	is_on = starts_on


func interact(by: Node3D) -> void:
	if one_shot and is_on:
		return
	is_on = not is_on
	toggled.emit(is_on, by)
	if is_on:
		activated.emit(by)
	else:
		deactivated.emit(by)
	super.interact(by)
