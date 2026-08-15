class_name GearSocket
extends Interactable

## One gear socket on the grandfather clock. The Roman numeral engraved
## above it names the tooth count it needs. [E] with gears in the pack
## seats one (a chooser pops when carrying several); [E] on a filled
## socket pops the gear back out — into the pack if there's room.

signal gear_changed

@export var required_teeth: int = 8

var gear: Grabbable = null
var locked := false


func can_interact(_by: Node3D) -> bool:
	return not locked


func get_prompt(by: Node3D = null) -> String:
	if gear != null:
		return "[E] Remove Gear"
	if by != null and by.has_method("inventory_find") and by.inventory_find("clock_gears") != null:
		return "[E] Seat Gear"
	return "Needs a Brass Gear"


func interact(by: Node3D) -> void:
	if locked:
		return
	if gear != null:
		# Pop the seated gear out; prefer the interactor's pack.
		var out := gear
		gear = null
		out.release()
		if by != null and by.has_method("pick_up"):
			by.pick_up(out)  # silently stays on the floor if the pack is full
		AudioSynthesizer.play_at("ratchet", global_position, -6.0)
		gear_changed.emit()
		super.interact(by)
		return

	var candidates: Array = []
	if by != null and by.get("inventory") != null:
		for item in by.inventory:
			if is_instance_valid(item) and item.is_in_group("clock_gears"):
				candidates.append(item)
	if candidates.is_empty():
		super.interact(by)
		return
	if candidates.size() == 1:
		request_seat(by, candidates[0])
	elif not by.has_method("is_local_player") or by.is_local_player():
		# Several gears in the pack: let the local player choose; the
		# choice replicates via request_seat.
		ItemSelectPopup.open(candidates,
			func(chosen: Node) -> void: request_seat(by, chosen),
			"Seat which gear?")
	super.interact(by)


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


func is_correct() -> bool:
	return gear != null and int(gear.get_meta("teeth", 0)) == required_teeth


func lock() -> void:
	locked = true
