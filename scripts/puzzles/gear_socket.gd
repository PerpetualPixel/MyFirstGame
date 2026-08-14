class_name GearSocket
extends Interactable

## One gear socket on the grandfather clock. The Roman numeral engraved
## above it names the tooth count it needs. [E] with a gear in hand seats
## it; [E] on a filled socket pops the gear back out onto the floor.

signal gear_changed

@export var required_teeth: int = 8

var gear: Grabbable = null
var locked := false


func can_interact(_by: Node3D) -> bool:
	return not locked


func get_prompt(by: Node3D = null) -> String:
	if gear != null:
		return "[E] Remove Gear"
	if by != null and _held_gear(by) != null:
		return "[E] Seat Gear"
	return "Needs a Brass Gear"


func interact(by: Node3D) -> void:
	if locked:
		return
	if gear != null:
		var out := gear
		gear = null
		out.release()
		AudioSynthesizer.play_at("ratchet", global_position, -6.0)
		gear_changed.emit()
	else:
		var held := _held_gear(by)
		if held == null:
			return
		by.set("held_item", null)
		held.mount(self, Vector3(0, 0, 0.1))
		gear = held
		AudioSynthesizer.play_at("plug", global_position, -8.0)
		gear_changed.emit()
	super.interact(by)


func is_correct() -> bool:
	return gear != null and int(gear.get_meta("teeth", 0)) == required_teeth


func lock() -> void:
	locked = true


func _held_gear(by: Node3D) -> Grabbable:
	var held: Node = by.get("held_item")
	if held != null and held.is_in_group("clock_gears"):
		return held
	return null
