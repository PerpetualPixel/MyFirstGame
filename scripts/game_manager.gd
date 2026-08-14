class_name GameManager
extends Node

## Runs the game loop. The run starts in PREGAME on the porch with the
## timer frozen at 4:00; powering the breaker starts PLAYING and the
## countdown. Win: carry the Will into the porch exit zone. Loss: timer
## reaches zero. [R] restarts with a freshly generated layout.

enum State { PREGAME, PLAYING, WON, LOST }

@export var run_time: float = 240.0

@onready var _mansion: MansionGenerator = $"../MansionGenerator"
@onready var _player: Player = $"../Player"
@onready var _timer_label: Label = $"../HUD/TimerLabel"
@onready var _obj_breaker: Label = $"../HUD/Objectives/BreakerObjective"
@onready var _obj_clock: Label = $"../HUD/Objectives/ClockObjective"
@onready var _obj_wrench: Label = $"../HUD/Objectives/WrenchObjective"
@onready var _obj_steam: Label = $"../HUD/Objectives/SteamObjective"
@onready var _obj_light: Label = $"../HUD/Objectives/LightObjective"
@onready var _obj_will: Label = $"../HUD/Objectives/WillObjective"
@onready var _end_screen: Control = $"../HUD/EndScreen"
@onready var _end_title: Label = $"../HUD/EndScreen/Center/VBox/Title"
@onready var _end_subtitle: Label = $"../HUD/EndScreen/Center/VBox/Subtitle"

var state := State.PREGAME
var time_left: float

var _breaker_done := false
var _clock_done := false
var _gears_placed := 0
var _wrench_found := false
var _light_done := false
var _valves_done := 0
var _valves: Array = []
var _exit_zones: Array = []
var _last_timer_text := ""


func _ready() -> void:
	# Keep processing while the tree is paused so end screens and [R] work.
	process_mode = Node.PROCESS_MODE_ALWAYS
	time_left = run_time
	_end_screen.visible = false

	_mansion.puzzle_solved.connect(_on_light_puzzle_solved)
	for breaker in get_tree().get_nodes_in_group("power_breakers"):
		breaker.powered.connect(_on_breaker_powered)
	for wrench in get_tree().get_nodes_in_group("wrenches"):
		wrench.grabbed.connect(_on_wrench_grabbed)
	for clock in get_tree().get_nodes_in_group("clockworks"):
		clock.gear_inserted.connect(_on_gears_changed)
		clock.clock_completed.connect(_on_clock_completed)
	_valves = get_tree().get_nodes_in_group("steam_valves")
	for valve in _valves:
		valve.valve_activated.connect(_on_valves_changed)
		valve.valve_reset.connect(_on_valves_changed)
	_exit_zones = get_tree().get_nodes_in_group("exit_zones")

	_timer_label.text = _format_time(time_left)
	_refresh_objectives()


func _process(delta: float) -> void:
	# This node processes while paused (so [R] works on end screens), but
	# the countdown must freeze whenever anything pauses the tree — the
	# pause menu or the wiring minigame.
	if state != State.PLAYING or get_tree().paused:
		return
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_lose()
	# The label only re-renders when the visible second actually changes.
	var text := _format_time(time_left)
	if text != _last_timer_text:
		_last_timer_text = text
		_timer_label.text = text
	_check_win()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().paused = false
		get_tree().reload_current_scene()


func _on_breaker_powered() -> void:
	_breaker_done = true
	if state == State.PREGAME:
		state = State.PLAYING
	_refresh_objectives()


func _on_wrench_grabbed(_by: Node3D) -> void:
	_wrench_found = true
	_refresh_objectives()


func _on_gears_changed(placed: int) -> void:
	_gears_placed = placed
	_refresh_objectives()


func _on_clock_completed() -> void:
	_clock_done = true
	_refresh_objectives()


func _on_light_puzzle_solved() -> void:
	_light_done = true
	_refresh_objectives()


func _on_valves_changed() -> void:
	_valves_done = 0
	for valve in _valves:
		if valve.activated:
			_valves_done += 1
	_refresh_objectives()


func _check_win() -> void:
	var held := _player.held_item
	if held == null or not held.is_in_group("will_items"):
		return
	for zone in _exit_zones:
		if zone.overlaps_body(_player):
			_win()
			return


func _win() -> void:
	if state != State.PLAYING:
		return
	state = State.WON
	_refresh_objectives()
	var elapsed := run_time - time_left
	_end_title.text = "Inheritance Secured!"
	_end_subtitle.text = "Completed in %s — Press [R] to restart" % _format_time(elapsed)
	_end_screen.visible = true
	get_tree().paused = true


func _lose() -> void:
	if state != State.PLAYING:
		return
	state = State.LOST
	_end_title.text = "Mansion Sealed Forever!"
	_end_subtitle.text = "The clockwork lock clicks shut. Press [R] to restart"
	_end_screen.visible = true
	get_tree().paused = true


func _refresh_objectives() -> void:
	var done_color := Color(0.55, 1.0, 0.65)
	var valves_ok := _valves.size() > 0 and _valves_done >= _valves.size()
	var will_ok := state == State.WON

	_obj_breaker.text = "%s Power the Front Breakers" % _checkbox(_breaker_done)
	_obj_breaker.modulate = done_color if _breaker_done else Color.WHITE
	_obj_clock.text = "%s Restore the Grandfather Clock (%d/3 gears)" % [_checkbox(_clock_done), _gears_placed]
	_obj_clock.modulate = done_color if _clock_done else Color.WHITE
	_obj_wrench.text = "%s Find the Brass Wrench" % _checkbox(_wrench_found)
	_obj_wrench.modulate = done_color if _wrench_found else Color.WHITE
	_obj_steam.text = "%s Synchronize Steam Pressure (%d/%d - 25s window)" % [_checkbox(valves_ok), _valves_done, _valves.size()]
	_obj_steam.modulate = done_color if valves_ok else Color.WHITE
	_obj_light.text = "%s Align Laser Circuit" % _checkbox(_light_done)
	_obj_light.modulate = done_color if _light_done else Color.WHITE
	_obj_will.text = "%s Retrieve Will & Escape" % _checkbox(will_ok)
	_obj_will.modulate = done_color if will_ok else Color.WHITE


func _checkbox(done: bool) -> String:
	return "[X]" if done else "[ ]"


@warning_ignore("integer_division")
func _format_time(seconds: float) -> String:
	var total := ceili(seconds)
	return "%d:%02d" % [total / 60, total % 60]
