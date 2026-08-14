class_name PauseMenu
extends CanvasLayer

## Global pause menu on [ESC]. The wiring minigame consumes ESC in _input
## (set_input_as_handled) before this node's _unhandled_input runs, so an
## open minigame always closes first instead of opening this menu. The menu
## also refuses to open when something else owns the pause (end screen or
## minigame), and it keeps working while paused via PROCESS_MODE_ALWAYS.

var is_open := false

var _controls_visible := false

@onready var _menu: Control = $Overlay/MenuCenter
@onready var _controls: Control = $Overlay/ControlsCenter


func _ready() -> void:
	visible = false
	$Overlay/MenuCenter/Menu/ResumeButton.pressed.connect(resume)
	$Overlay/MenuCenter/Menu/ControlsButton.pressed.connect(func() -> void: _show_controls(true))
	$Overlay/MenuCenter/Menu/RestartButton.pressed.connect(_on_restart)
	$Overlay/MenuCenter/Menu/QuitButton.pressed.connect(func() -> void: get_tree().quit())
	$Overlay/ControlsCenter/Panel/Lines/BackButton.pressed.connect(func() -> void: _show_controls(false))
	$Overlay/ControlsCenter/Panel/Lines/HintsContainer/HintsToggle.toggled.connect(_on_hints_toggled)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if is_open:
		if _controls_visible:
			_show_controls(false)
		else:
			resume()
		get_viewport().set_input_as_handled()
	elif not get_tree().paused:
		# If the tree is paused and it wasn't us, someone else (minigame,
		# end screen) owns the pause — don't stack the menu on top.
		open_menu()
		get_viewport().set_input_as_handled()


func open_menu() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	_show_controls(false)
	# Co-op never pauses the tree — the partner's world keeps running.
	if not NetworkSession.multiplayer_active:
		get_tree().paused = true


func resume() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	if not NetworkSession.multiplayer_active:
		get_tree().paused = false


func _show_controls(shown: bool) -> void:
	_controls_visible = shown
	_controls.visible = shown
	_menu.visible = not shown


func _on_restart() -> void:
	var gm: Node = get_node_or_null("../GameManager")
	if gm and gm.has_method("request_restart"):
		gm.request_restart()
	else:
		get_tree().paused = false
		get_tree().reload_current_scene()


func _on_hints_toggled(pressed: bool) -> void:
	GameSettings.hints_enabled = pressed
