class_name GameSettings
extends Node

## Global game settings persisted across runs (hints toggle, etc).
## Accessed as GameSettings.hints_enabled (static convenience).

static var hints_enabled := true


func _ready() -> void:
	# Could load from a config file here for persistence across app restarts.
	pass
