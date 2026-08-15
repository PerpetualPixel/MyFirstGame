class_name BatterySocket
extends Interactable

## The laser emitter's power cradle (attached to its Housing body). The
## mansion's laser sits dead until a Heavy Battery is carried here and
## seated with [E]. Installing is permanent for the run — the interaction
## replicates on every peer, same contract as gear sockets and valves.

signal battery_installed

var installed := false


func can_interact(_by: Node3D) -> bool:
	return not installed


func get_prompt(by: Node3D = null) -> String:
	if by != null and _held_battery(by) != null:
		return "[E] Install Heavy Battery"
	return "Dead — needs a heavy power cell"


func interact(by: Node3D) -> void:
	if installed:
		return
	var battery := _held_battery(by)
	if battery == null:
		return
	# Seat the battery visibly at the housing's base (mount pulls it out
	# of the carrier's pack).
	battery.mount(self, Vector3(0, 0.25, 0.62))
	installed = true
	var emitter := get_parent() as LightEmitter
	if emitter:
		emitter.power_on()
	AudioSynthesizer.play_at("plug", global_position, -4.0)
	AudioSynthesizer.play_ui("power_up", -10.0)
	battery_installed.emit()
	super.interact(by)


func _held_battery(by: Node3D) -> Grabbable:
	if by != null and by.has_method("inventory_find"):
		return by.inventory_find("batteries")
	return null
