class_name TighteningPoint
extends Interactable

## One loose fitting on the hydraulic press. Comes in two sizes: SMALL
## fittings want the Small Wrench (garage workbench), BIG fittings want
## the Brass Wrench (grandfather clock). The press manager gates the
## sequence by flipping `enabled` — a fitting whose phase hasn't started
## just clunks. Tightening is permanent; the nut spins home, the fluid
## leak stops, and the manager advances the phase once its tier is done.

signal fitting_tightened(point: TighteningPoint)
## The player swung a wrench at this fitting, but the wrong one.
signal wrong_item(point: TighteningPoint, by: Node3D)

enum WrenchSize { SMALL, BIG }

@export var wrench_size := WrenchSize.SMALL
@export var spin_duration: float = 0.7

var is_tight := false
## Sequence gate, owned by PressurePuzzleManager: big fittings stay
## disabled until every small fitting is home.
var enabled := false

@onready var _nut: MeshInstance3D = $Nut
@onready var _leak: GPUParticles3D = $Leak


func required_group() -> String:
	return "small_wrenches" if wrench_size == WrenchSize.SMALL else "big_wrenches"


func _wrench_label() -> String:
	return "Small Wrench" if wrench_size == WrenchSize.SMALL else "Brass Wrench"


func can_interact(_by: Node3D) -> bool:
	return not is_tight


func get_prompt(by: Node3D = null) -> String:
	if not enabled:
		return "Sealed — tighten the small fittings first"
	if by != null and _held_wrench(by) == null:
		return "Needs the %s" % _wrench_label()
	return "[E] Tighten Fitting"


func interact(by: Node3D) -> void:
	if is_tight:
		return
	if not enabled:
		# Out of sequence: a dull clunk, nothing moves.
		AudioSynthesizer.play_at("tick", global_position, -8.0, 0.55)
		return
	if _held_wrench(by) == null:
		# Holding a wrench, just not the right one -> explicit feedback so
		# the player knows the tool (not the fitting) is the problem. Bare
		# hands stay silent; the prompt already names the missing wrench.
		if by != null and by.has_method("inventory_find") \
				and by.inventory_find("wrenches") != null:
			AudioSynthesizer.play_at("zap", global_position, -16.0, 0.8)
			_jiggle_nut()
			wrong_item.emit(self, by)
		return
	is_tight = true
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_nut, "rotation:y", _nut.rotation.y + TAU * 1.5, spin_duration)
	tween.tween_callback(_finish)
	AudioSynthesizer.play_at("ratchet", global_position, -4.0)
	super.interact(by)


func _finish() -> void:
	_leak.emitting = false
	AudioSynthesizer.play_at("tick", global_position, -6.0, 1.2)
	fitting_tightened.emit(self)


## Wrong-tool feedback: the nut wiggles but never seats.
func _jiggle_nut() -> void:
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_nut, "rotation:y", _nut.rotation.y + 0.18, 0.08)
	tween.tween_property(_nut, "rotation:y", _nut.rotation.y, 0.1)


func _held_wrench(by: Node3D) -> Grabbable:
	if by != null and by.has_method("inventory_find"):
		return by.inventory_find(required_group())
	return null
