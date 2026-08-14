class_name BreakerBox
extends Interactable

## The porch breaker box. [E] opens the fullscreen wiring minigame; solving
## it powers the mansion (emits `powered`, same contract the front doors
## and GameManager already listen for via the "power_breakers" group).

signal powered

const WIRING_SCENE := preload("res://scenes/Puzzles/WiringMinigame.tscn")

## Deterministic wiring board seed, set by the generator from the shared
## run seed so both co-op peers see the identical board and journal clues.
@export var wiring_seed: int = 0

var is_powered := false
var minigame: WiringMinigame


func _ready() -> void:
	add_to_group("power_breakers")
	minigame = WIRING_SCENE.instantiate()
	add_child(minigame)
	minigame.setup(wiring_seed)
	minigame.solved.connect(_on_solved)


func can_interact(_by: Node3D) -> bool:
	return not is_powered


func get_prompt(_by: Node3D = null) -> String:
	return "[E] Inspect Breaker Box"


func interact(by: Node3D) -> void:
	if is_powered:
		return
	# The interaction RPC runs on every peer, but the fullscreen minigame
	# must only open on the machine of the player who pressed [E].
	if by == null or not by.has_method("is_local_player") or by.is_local_player():
		minigame.open()
	super.interact(by)


func _on_solved() -> void:
	if NetworkSession.multiplayer_active:
		_net_powered.rpc()
	else:
		_apply_powered()


@rpc("any_peer", "call_local", "reliable")
func _net_powered() -> void:
	_apply_powered()


func _apply_powered() -> void:
	if is_powered:
		return
	is_powered = true
	Player.shake(0.35, global_position)
	powered.emit()
