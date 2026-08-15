class_name PressureValve
extends Interactable

## One of the hydraulic press's five hand valves. A pure ON/OFF toggle:
## while open it contributes its signed `pressure_value` to the press's
## PSI total. No wrench, no timer, no fail state — flip it as often as
## you like until the gauge hits the target. The press manager gates it
## (`enabled` only after every fitting is torqued) and freezes it
## (`locked`) once the target pressure is reached.

signal valve_toggled(valve: PressureValve)

## Signed PSI this valve feeds into the manifold while open.
@export var pressure_value: int = 10
@export var spin_duration: float = 0.45

var is_on := false
## Sequence gate, owned by PressurePuzzleManager.
var enabled := false
## Set once the puzzle solves: the combination must not be breakable.
var locked := false

@onready var _wheel: MeshInstance3D = $Wheel
@onready var _lamp: MeshInstance3D = $Lamp
@onready var _label: Label3D = $ValueLabel

var _lamp_mat := StandardMaterial3D.new()
var _tween: Tween


func _ready() -> void:
	_label.text = "%+d" % pressure_value
	_label.modulate = Color(0.4, 0.9, 1.0) if pressure_value >= 0 else Color(1.0, 0.5, 0.4)
	_lamp_mat.emission_enabled = true
	_lamp.material_override = _lamp_mat
	_refresh_lamp()


func can_interact(_by: Node3D) -> bool:
	return not locked


func get_prompt(_by: Node3D = null) -> String:
	if not enabled:
		return "Sealed — torque every fitting first"
	return "[E] Close Valve" if is_on else "[E] Open Valve"


func interact(by: Node3D) -> void:
	if locked:
		return
	if not enabled:
		AudioSynthesizer.play_at("tick", global_position, -8.0, 0.55)
		return
	# State flips immediately so the PSI math never waits on animation;
	# spamming [E] just retargets the cosmetic tween.
	is_on = not is_on
	if _tween:
		_tween.kill()
	var spin := TAU if is_on else -TAU
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_wheel, "rotation:y", _wheel.rotation.y + spin, spin_duration)
	_refresh_lamp()
	AudioSynthesizer.play_at("ratchet", global_position, -6.0)
	if is_on:
		AudioSynthesizer.play_at("steam", global_position, -18.0, 1.7)
	valve_toggled.emit(self)
	super.interact(by)


## Freeze the winning combination in place (puzzle solved).
func lock() -> void:
	locked = true


func _refresh_lamp() -> void:
	var color := Color(0.3, 1.0, 0.75) if is_on else Color(0.45, 0.3, 0.15)
	_lamp_mat.albedo_color = color
	_lamp_mat.emission = color
	_lamp_mat.emission_energy_multiplier = 2.2 if is_on else 0.4
