class_name PauseMenu
extends CanvasLayer

## Global pause menu on [ESC]. The wiring minigame consumes ESC in _input
## (set_input_as_handled) before this node's _unhandled_input runs, so an
## open minigame always closes first instead of opening this menu. The menu
## also refuses to open when something else owns the pause (end screen or
## minigame), and it keeps working while paused via PROCESS_MODE_ALWAYS.

var is_open := false

var _controls_visible := false
## The action currently listening for its new key, or "" when idle.
var _rebinding := ""
var _bind_buttons := {}

@onready var _menu: Control = $Overlay/MenuCenter
@onready var _controls: Control = $Overlay/ControlsCenter
@onready var _bindings: VBoxContainer = $Overlay/ControlsCenter/Panel/Lines/Bindings


func _ready() -> void:
	visible = false
	_build_bindings()
	$Overlay/ControlsCenter/Panel/Lines/ResetBindsButton.pressed.connect(_on_reset_binds)
	$Overlay/MenuCenter/Menu/ResumeButton.pressed.connect(resume)
	$Overlay/MenuCenter/Menu/ControlsButton.pressed.connect(func() -> void: _show_controls(true))
	$Overlay/MenuCenter/Menu/RestartButton.pressed.connect(_on_restart)
	$Overlay/MenuCenter/Menu/QuitButton.pressed.connect(func() -> void: get_tree().quit())
	$Overlay/ControlsCenter/Panel/Lines/BackButton.pressed.connect(func() -> void: _show_controls(false))
	$Overlay/ControlsCenter/Panel/Lines/HintsContainer/HintsToggle.toggled.connect(_on_hints_toggled)
	var scale_slider: HSlider = $Overlay/ControlsCenter/Panel/Lines/ObjScaleContainer/ObjScaleSlider
	scale_slider.value = GameSettings.objectives_scale * 100.0
	scale_slider.value_changed.connect(
		func(value: float) -> void: GameSettings.objectives_scale = value / 100.0)


# --- Key rebinding -------------------------------------------------------


## One row per bindable action: name on the left, its key as a button on
## the right. Clicking the button listens for the next key/mouse press.
func _build_bindings() -> void:
	for entry in GameSettings.BINDABLE_ACTIONS:
		var action: String = entry[0]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_bindings.add_child(row)
		var label := Label.new()
		label.text = str(entry[1])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 17)
		row.add_child(label)
		var button := Button.new()
		button.custom_minimum_size = Vector2(132, 30)
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(_on_bind_pressed.bind(action))
		row.add_child(button)
		_bind_buttons[action] = button
	_refresh_bindings()


func _refresh_bindings() -> void:
	for action in _bind_buttons:
		var button: Button = _bind_buttons[action]
		button.text = "Press a key…" if _rebinding == action else GameSettings.key_label(action)


func _on_bind_pressed(action: String) -> void:
	_rebinding = action
	_refresh_bindings()


func _on_reset_binds() -> void:
	_rebinding = ""
	GameSettings.reset_bindings()
	_refresh_bindings()
	AudioSynthesizer.play_ui("tick", -14.0, 0.9)


## While listening, the very next key or mouse button becomes the binding
## (ESC cancels). Runs in _input so it beats every gameplay handler.
func _input(event: InputEvent) -> void:
	if _rebinding.is_empty() or not is_open or not _controls_visible:
		return
	var accept := false
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_rebinding = ""
			_refresh_bindings()
			get_viewport().set_input_as_handled()
			return
		accept = true
	elif event is InputEventMouseButton and event.pressed:
		accept = true
	if not accept:
		return
	GameSettings.rebind(_rebinding, event)
	_rebinding = ""
	_refresh_bindings()
	AudioSynthesizer.play_ui("tick", -12.0, 1.2)
	get_viewport().set_input_as_handled()


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
	if not shown:
		_rebinding = ""
	_refresh_bindings()


func _on_restart() -> void:
	var gm: Node = get_node_or_null("../GameManager")
	if gm and gm.has_method("request_restart"):
		gm.request_restart()
	else:
		get_tree().paused = false
		get_tree().reload_current_scene()


func _on_hints_toggled(pressed: bool) -> void:
	GameSettings.hints_enabled = pressed
