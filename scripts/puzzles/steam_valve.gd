class_name SteamValve
extends Interactable

## Wheel valve venting a hissing steam leak. Turning it requires holding
## the Brass Wrench. Once turned, a decay timer starts: unless every valve
## in the "steam_valves" group is turned before it expires, this valve
## blows back open and resumes leaking (valve_reset). When all valves are
## on simultaneously they lock open for good.

signal valve_activated
signal valve_reset

@export var spin_duration: float = 1.0
## Seconds this valve holds pressure alone before blowing back open.
@export var decay_time: float = 25.0

@onready var _wheel: MeshInstance3D = $Wheel
@onready var _steam: GPUParticles3D = $Steam

var activated := false
var locked_open := false

var _decay_timer: Timer
var _steam_audio: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("steam_valves")
	_decay_timer = Timer.new()
	_decay_timer.one_shot = true
	_decay_timer.timeout.connect(_on_decay_timeout)
	add_child(_decay_timer)
	# Whistling pressure leak that subsides once the valve is tightened.
	_steam_audio = AudioSynthesizer.create_loop("steam", self, -8.0)


func can_interact(_by: Node3D) -> bool:
	return not activated


func get_prompt(by: Node3D = null) -> String:
	if by != null and not _has_wrench(by):
		return "Needs the Brass Wrench"
	return "[E] Turn Valve"


func interact(by: Node3D) -> void:
	if activated or not _has_wrench(by):
		return
	activated = true
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_wheel, "rotation:y", _wheel.rotation.y + TAU * 2.0, spin_duration)
	tween.tween_callback(_finish)
	super.interact(by)


func _finish() -> void:
	_steam.emitting = false
	if _steam_audio:
		create_tween().tween_property(_steam_audio, "volume_db", -50.0, 1.2)
	valve_activated.emit()
	_sync_group()


## All valves on -> everyone locks open; otherwise this valve races its
## decay timer against the player reaching the next one.
func _sync_group() -> void:
	var valves := get_tree().get_nodes_in_group("steam_valves")
	var all_on := true
	for valve in valves:
		if not valve.activated:
			all_on = false
			break
	if all_on:
		for valve in valves:
			valve.lock_open()
	elif activated and not locked_open:
		# Co-op: only the host runs decay timers; it broadcasts the reset.
		if not NetworkSession.multiplayer_active or multiplayer.is_server():
			_decay_timer.start(decay_time)


func lock_open() -> void:
	locked_open = true
	_decay_timer.stop()


func _on_decay_timeout() -> void:
	if locked_open or not activated:
		return
	if NetworkSession.multiplayer_active:
		_net_reset.rpc()
	else:
		_apply_reset()


@rpc("authority", "call_local", "reliable")
func _net_reset() -> void:
	_apply_reset()


func _apply_reset() -> void:
	if locked_open or not activated:
		return
	activated = false
	_steam.emitting = true
	if _steam_audio:
		_steam_audio.volume_db = -4.0  # loud release hiss, settling back
		create_tween().tween_property(_steam_audio, "volume_db", -8.0, 1.5)
	Player.shake(0.7, global_position)  # violent blow-back thud
	valve_reset.emit()


func _has_wrench(by: Node3D) -> bool:
	var held: Node = by.get("held_item")
	return held != null and held.is_in_group("wrenches")
