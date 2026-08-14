class_name GameSettings
extends Node

## Global game settings persisted across runs (hints toggle, music volume, etc).
## Accessed as GameSettings.hints_enabled, GameSettings.music_volume_db (static).

static var hints_enabled := true
static var music_volume_db := -10.4  # 30% volume in dB


func _ready() -> void:
	# Could load from a config file here for persistence across app restarts.
	pass
