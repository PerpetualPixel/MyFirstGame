extends Node

## Global game settings autoload (hints toggle, music volume, etc).
## Accessed as GameSettings.hints_enabled, GameSettings.music_volume_db.

signal objectives_scale_changed(value: float)

var hints_enabled := true
var music_volume_db := -10.4  # 30% volume in dB

## On-screen size of the objectives list (0.6 = compact, 1.6 = large).
var objectives_scale := 1.0:
	set(value):
		objectives_scale = clampf(value, 0.6, 1.6)
		objectives_scale_changed.emit(objectives_scale)


func _ready() -> void:
	# Could load from a config file here for persistence across app restarts.
	pass
