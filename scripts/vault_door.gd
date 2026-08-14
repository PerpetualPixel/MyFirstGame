class_name VaultDoor
extends Node3D

## Heavy brass gate sealing the Vault Study doorway. Two lamps show puzzle
## status (amber -> cyan): left = light puzzle, right = steam valves. The
## gate is two stacked slabs with a horizontal viewing slit at laser height
## (y 1.1..1.3), so the beam can reach the receiver while the player stays
## locked out. When both puzzles are done the gate sinks into the floor.

signal opened

@export var valves_required: int = 2
@export var open_duration: float = 1.6

const COLOR_WAIT := Color(1.0, 0.55, 0.1)
const COLOR_DONE := Color(0.35, 1.0, 1.0)

@onready var _gate: StaticBody3D = $Gate
@onready var _light_lamp: MeshInstance3D = $Gate/LightLamp
@onready var _steam_lamp: MeshInstance3D = $Gate/SteamLamp

var is_open := false
var _light_done := false
var _valves_done := 0
var _light_mat := StandardMaterial3D.new()
var _steam_mat := StandardMaterial3D.new()


func _ready() -> void:
	add_to_group("vault_doors")
	_light_mat.emission_enabled = true
	_steam_mat.emission_enabled = true
	_apply_lamp_color(_light_mat, COLOR_WAIT)
	_apply_lamp_color(_steam_mat, COLOR_WAIT)
	_light_lamp.material_override = _light_mat
	_steam_lamp.material_override = _steam_mat


func on_light_puzzle_completed() -> void:
	_light_done = true
	_apply_lamp_color(_light_mat, COLOR_DONE)
	_try_open()


func on_valve_activated() -> void:
	_valves_done += 1
	if _valves_done >= valves_required:
		_apply_lamp_color(_steam_mat, COLOR_DONE)
	_try_open()


## A valve's decay timer expired and it blew back open.
func on_valve_reset() -> void:
	_valves_done = maxi(0, _valves_done - 1)
	if not is_open:
		_apply_lamp_color(_steam_mat, COLOR_WAIT)


func _try_open() -> void:
	if is_open or not _light_done or _valves_done < valves_required:
		return
	is_open = true
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_gate, "position:y", _gate.position.y - 2.7, open_duration)
	# Heavy brass gate collapsing into the floor: rumble + dust + chime.
	Player.shake(0.55, global_position)
	Door._dust_puff(global_position + Vector3(-0.8, 0, 0), 14)
	Door._dust_puff(global_position + Vector3(0.8, 0, 0), 14)
	AudioSynthesizer.play_at("chime", global_position, -8.0, 0.6)
	opened.emit()


func _apply_lamp_color(mat: StandardMaterial3D, color: Color) -> void:
	mat.albedo_color = color
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
