extends Node

## Global game settings autoload (hints toggle, music volume, etc).
## Accessed as GameSettings.hints_enabled, GameSettings.music_volume_db.

var hints_enabled := true
var music_volume_db := -10.4  # 30% volume in dB


func _ready() -> void:
	# Could load from a config file here for persistence across app restarts.
	pass
