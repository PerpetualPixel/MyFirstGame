class_name LightEmitter
extends Node3D

## Fires a continuous laser along its -Z axis from the muzzle every physics
## frame. Hits are forwarded through LaserBeam.dispatch(): mirrors reflect,
## receivers charge, and anything else (walls, player) simply stops the beam.
## The emitter starts DEAD: its cradle (Housing, a BatterySocket) must be
## fed a Heavy Battery before the beam fires.

const MAX_BOUNCES := 8

## Off until a Heavy Battery is installed in the cradle.
var powered := false

@onready var _beam: LaserBeam = $Beam
@onready var _muzzle: Marker3D = $Muzzle


func _ready() -> void:
	_beam.add_exception($Housing)


func power_on() -> void:
	powered = true


func _physics_process(_delta: float) -> void:
	if not powered:
		_beam.shut_off()
		return
	var dir := -global_transform.basis.z
	var hit := _beam.fire(_muzzle.global_position, dir)
	LaserBeam.dispatch(hit, dir, MAX_BOUNCES)
