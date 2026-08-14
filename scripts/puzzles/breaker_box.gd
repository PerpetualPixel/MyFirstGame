class_name BreakerBox
extends Interactable

## The porch breaker box. [E] opens the fullscreen wiring minigame; solving
## it powers the mansion (emits `powered`, same contract the front doors
## and GameManager already listen for via the "power_breakers" group).

signal powered

const WIRING_SCENE := preload("res://scenes/Puzzles/WiringMinigame.tscn")

var is_powered := false
var minigame: WiringMinigame


func _ready() -> void:
	add_to_group("power_breakers")
	minigame = WIRING_SCENE.instantiate()
	add_child(minigame)
	minigame.solved.connect(_on_solved)


func can_interact(_by: Node3D) -> bool:
	return not is_powered


func get_prompt(_by: Node3D = null) -> String:
	return "[E] Inspect Breaker Box"


func interact(by: Node3D) -> void:
	if is_powered:
		return
	minigame.open()
	super.interact(by)


func _on_solved() -> void:
	is_powered = true
	powered.emit()
