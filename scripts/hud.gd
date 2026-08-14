extends CanvasLayer

## HUD chrome behaviors: the objectives list can be collapsed/expanded via
## its header button, and its on-screen size follows the
## GameSettings.objectives_scale setting (adjustable in the pause menu).
## Objective label text itself is managed by GameManager.

@onready var _objectives: VBoxContainer = $Objectives
@onready var _toggle: Button = $Objectives/ToggleButton

var _collapsed := false


func _ready() -> void:
	_toggle.pressed.connect(_on_toggle_pressed)
	_apply_scale(GameSettings.objectives_scale)
	GameSettings.objectives_scale_changed.connect(_apply_scale)


func _on_toggle_pressed() -> void:
	_collapsed = not _collapsed
	for child in _objectives.get_children():
		if child is Label:
			child.visible = not _collapsed
	_toggle.text = "▶ Objectives" if _collapsed else "▼ Objectives"
	AudioSynthesizer.play_ui("tick", -14.0, 1.4)


func _apply_scale(value: float) -> void:
	# Scales from the list's top-left corner, so it stays anchored on screen.
	_objectives.scale = Vector2(value, value)
