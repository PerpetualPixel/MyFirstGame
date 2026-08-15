class_name BreakerBox
extends Interactable

## The garage fuse panel. Two circuits (FRONT DOOR, LIVING ROOM) are dead
## because their cartridge fuses are missing. [E] while holding a ceramic
## fuse seats it (interactions run on every co-op peer, so consumption
## replicates like gear sockets); [E] empty-handed opens the panel overlay
## showing what's missing. Both fuses in -> emits `powered` (GameManager
## and the keypad/garage listen).

signal powered

const PANEL_SCENE := preload("res://scenes/Puzzles/FusePanel.tscn")

## Kept for the generator's call contract (the old wiring board was
## seeded; the fuse hunt derives everything from world spawns instead).
@export var wiring_seed: int = 0

const FUSES_NEEDED := 2

var is_powered := false
var fuses_installed := 0
var minigame: FusePanel


func _ready() -> void:
	add_to_group("power_breakers")
	minigame = PANEL_SCENE.instantiate()
	add_child(minigame)


func can_interact(_by: Node3D) -> bool:
	return not is_powered


func get_prompt(by: Node3D = null) -> String:
	if by != null and _carried_fuse(by) != null:
		return "[E] Inspect Fuse Panel (fuse ready)"
	return "[E] Inspect Fuse Panel"


## RE-style: [E] always inspects; the fuse is selected and inserted from
## inside the panel overlay (clicking an empty socket).
func interact(by: Node3D) -> void:
	if is_powered:
		return
	if by == null or not by.has_method("is_local_player") or by.is_local_player():
		# The fullscreen overlay only opens on the interacting machine.
		minigame.open()
	super.interact(by)


## Called from the panel overlay when the local player clicks an empty
## socket with a fuse in their pack. Replicates to every peer.
func request_install(by: Node3D) -> void:
	if NetworkSession.multiplayer_active:
		_net_install.rpc(by.get_path())
	else:
		_apply_install(by)


@rpc("any_peer", "call_local", "reliable")
func _net_install(by_path: NodePath) -> void:
	_apply_install(get_node_or_null(by_path))


func _apply_install(by: Node3D) -> void:
	if is_powered or by == null:
		return
	var fuse := _carried_fuse(by)
	if fuse == null:
		return
	if by.has_method("inventory_remove"):
		by.inventory_remove(fuse)
	fuse.queue_free()
	fuses_installed += 1
	minigame.mark_installed(fuses_installed)
	AudioSynthesizer.play_at("plug", global_position, -4.0)
	if fuses_installed >= FUSES_NEEDED:
		_apply_powered()


func _carried_fuse(by: Node3D) -> Grabbable:
	if by != null and by.has_method("inventory_find"):
		return by.inventory_find("fuses")
	return null


func _apply_powered() -> void:
	if is_powered:
		return
	is_powered = true
	AudioSynthesizer.play_ui("power_up", -8.0)
	Player.shake(0.35, global_position)
	powered.emit()
