extends CanvasLayer

## HUD chrome behaviors: the objectives list can be collapsed/expanded via
## its header button, and its on-screen size follows the
## GameSettings.objectives_scale setting (adjustable in the pause menu).
## Objective label text itself is managed by GameManager.

@onready var _objectives: VBoxContainer = $Objectives
@onready var _toggle: Button = $Objectives/ToggleButton

var _collapsed := false


func _ready() -> void:
	# Keep processing while paused: the pause menu's size slider should
	# update the list live behind the settings panel.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_toggle.pressed.connect(_on_toggle_pressed)
	_apply_scale(GameSettings.objectives_scale)


## Polled (not signaled): GameSettings is a static class, and the pause
## menu can change the scale at any time while the tree is paused.
func _process(_delta: float) -> void:
	if _objectives.scale.x != GameSettings.objectives_scale:
		_apply_scale(GameSettings.objectives_scale)


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
