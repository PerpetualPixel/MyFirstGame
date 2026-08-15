class_name GearSocket
extends Interactable

## One gear socket on the grandfather clock. The Roman numeral engraved
## above it names the tooth count it needs. The socket is worked entirely
## from the clock's fullscreen panel (never prompted in-world): the panel
## calls request_seat / request_remove, which replicate to every peer.
## The seated gear still mounts here in 3D, visible behind the waist
## glass.

signal gear_changed

@export var required_teeth: int = 8

var gear: Grabbable = null
var locked := false


## Never a direct [E] target — the clock case is the interactable, and
## this body must not steal its prompt.
func can_interact(_by: Node3D) -> bool:
	return false


## Seat `chosen` from `by`'s pack; replicates to every peer in co-op.
func request_seat(by: Node3D, chosen: Node) -> void:
	if NetworkSession.multiplayer_active:
		_net_seat.rpc(by.get_path(), chosen.get_path())
	else:
		_apply_seat(chosen)


@rpc("any_peer", "call_local", "reliable")
func _net_seat(_by_path: NodePath, gear_path: NodePath) -> void:
	_apply_seat(get_node_or_null(gear_path))


func _apply_seat(chosen: Node) -> void:
	if locked or gear != null or chosen == null:
		return
	var g := chosen as Grabbable
	if g == null:
		return
	g.mount(self, Vector3(0, 0, 0.1))
	gear = g
	AudioSynthesizer.play_at("plug", global_position, -8.0)
	gear_changed.emit()


## Pop the seated gear back out into `by`'s pack (or onto the floor if
## the pack is full); replicates to every peer in co-op.
func request_remove(by: Node3D) -> void:
	if NetworkSession.multiplayer_active:
		_net_remove.rpc(by.get_path())
	else:
		_apply_remove(by)


@rpc("any_peer", "call_local", "reliable")
func _net_remove(by_path: NodePath) -> void:
	_apply_remove(get_node_or_null(by_path))


func _apply_remove(by: Node3D) -> void:
	if locked or gear == null:
		return
	var out := gear
	gear = null
	out.release()
	if by != null and by.has_method("pick_up"):
		by.pick_up(out)  # silently stays on the floor if the pack is full
	AudioSynthesizer.play_at("ratchet", global_position, -6.0)
	gear_changed.emit()


func is_correct() -> bool:
	return gear != null and int(gear.get_meta("teeth", 0)) == required_teeth


func lock() -> void:
	locked = true
