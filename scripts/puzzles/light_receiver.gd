class_name LightReceiver
extends StaticBody3D

## Brass pedestal with a crystal sphere. Idles dim amber; while a laser
## feeds it the crystal shifts to bright cyan, and after required_time of
## continuous light it locks in, bursts particles, and emits puzzle_completed.

signal puzzle_completed

@export var required_time: float = 0.5

const COLOR_IDLE := Color(0.9, 0.45, 0.18)
const COLOR_LIT := Color(0.35, 1.0, 1.0)

@onready var _crystal: MeshInstance3D = $Crystal
@onready var _particles: GPUParticles3D = $Particles

var is_solved := false
var _powered_frame: int = -100
var _accum := 0.0
var _mat := StandardMaterial3D.new()


func _ready() -> void:
	_mat.albedo_color = COLOR_IDLE
	_mat.emission_enabled = true
	_mat.emission = COLOR_IDLE
	_mat.emission_energy_multiplier = 0.6
	_crystal.material_override = _mat


## Called by LaserBeam.dispatch() every physics frame the beam lands here.
func beam_hit() -> void:
	_powered_frame = Engine.get_physics_frames()


func _physics_process(delta: float) -> void:
	var powered := Engine.get_physics_frames() - _powered_frame <= 1
	if powered:
		_accum += delta
		if not is_solved and _accum >= required_time:
			_solve()
	else:
		_accum = 0.0

	# Once solved, the crystal stays lit forever (the puzzle latches).
	var lit := powered or is_solved
	var target := COLOR_LIT if lit else COLOR_IDLE
	var energy := 3.0 if lit else 0.6
	var w := 1.0 - exp(-8.0 * delta)
	_mat.emission = _mat.emission.lerp(target, w)
	_mat.albedo_color = _mat.albedo_color.lerp(target, w)
	_mat.emission_energy_multiplier = lerpf(_mat.emission_energy_multiplier, energy, w)


func _solve() -> void:
	is_solved = true
	_particles.restart()
	puzzle_completed.emit()
