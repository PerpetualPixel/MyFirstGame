class_name GameManager
extends Node

## Runs the game loop. PREGAME on the porch with the timer frozen at 4:00;
## powering the breaker starts PLAYING. Win: carry the Will into the porch
## exit zone. Loss: timer hits zero. In co-op the HOST owns the countdown
## and win/loss verdicts and replicates them; each peer's HUD objectives
## update from locally-replicated puzzle events. Also drives the countdown
## tension layer (amber/red timer, heartbeat, vignette pulse), milestone
## banners, and the off-screen partner tracker.

enum State { PREGAME, PLAYING, WON, LOST }

@export var run_time: float = 240.0

@onready var _mansion: MansionGenerator = $"../MansionGenerator"
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
@onready var _banner: Label = $"../HUD/Banner"
@onready var _partner_arrow: Label = $"../HUD/PartnerArrow"
@onready var _vignette: ColorRect = $"../HUD/Vignette"

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
var _local_player: Player
var _time_sync_accum := 0.0
var _heartbeat_accum := 0.0
var _pulse_time := 0.0
var _banner_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	time_left = run_time
	_end_screen.visible = false
	_banner.modulate.a = 0.0
	_partner_arrow.visible = false

	_mansion.puzzle_solved.connect(_on_light_puzzle_solved)
	for breaker in get_tree().get_nodes_in_group("power_breakers"):
		breaker.powered.connect(_on_breaker_powered)
	for wrench in get_tree().get_nodes_in_group("wrenches"):
		wrench.grabbed.connect(_on_wrench_grabbed)
	for clock in get_tree().get_nodes_in_group("clockworks"):
		clock.gear_inserted.connect(_on_gears_changed)
		clock.clock_completed.connect(_on_clock_completed)
	for vault in get_tree().get_nodes_in_group("vault_doors"):
		vault.opened.connect(func() -> void: show_banner("VAULT GATE UNLOCKED!"))
	for will in get_tree().get_nodes_in_group("will_items"):
		will.grabbed.connect(_on_will_grabbed)
	_valves = get_tree().get_nodes_in_group("steam_valves")
	for valve in _valves:
		valve.valve_activated.connect(_on_valves_changed)
		valve.valve_reset.connect(_on_valves_changed)
	_exit_zones = get_tree().get_nodes_in_group("exit_zones")

	_timer_label.text = _format_time(time_left)
	_refresh_objectives()


func _process(delta: float) -> void:
	_update_partner_arrow()
	if state != State.PLAYING or get_tree().paused:
		return
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		if _is_verdict_authority():
			_trigger_lose()
	var text := _format_time(time_left)
	if text != _last_timer_text:
		_last_timer_text = text
		_timer_label.text = text
	_update_tension(delta)
	# Host streams the authoritative clock to the client at 1 Hz.
	if NetworkSession.multiplayer_active and multiplayer.is_server():
		_time_sync_accum += delta
		if _time_sync_accum >= 1.0:
			_time_sync_accum = 0.0
			_net_time.rpc(time_left)
	if _is_verdict_authority():
		_check_win()


func _is_verdict_authority() -> bool:
	return not NetworkSession.multiplayer_active or multiplayer.is_server()


@rpc("authority", "call_remote", "unreliable")
func _net_time(t: float) -> void:
	time_left = t


## Countdown tension: amber pulse under 60 s, red flash + vignette pulse +
## faster, higher-pitched heartbeat under 30 s.
func _update_tension(delta: float) -> void:
	if time_left > 60.0:
		return
	_pulse_time += delta
	var urgent := time_left <= 30.0
	var pulse := 0.5 + 0.5 * sin(_pulse_time * (10.0 if urgent else 6.0))
	if urgent:
		_timer_label.modulate = Color(1.0, 0.25, 0.2).lerp(Color(1.0, 0.7, 0.6), pulse)
		_vignette.material.set_shader_parameter("tint", Color(0.5, 0.02, 0.02))
		_vignette.material.set_shader_parameter("pulse", 0.12 + 0.1 * pulse)
	else:
		_timer_label.modulate = Color(1.0, 0.72, 0.25).lerp(Color(1.0, 0.9, 0.6), pulse)
		_vignette.material.set_shader_parameter("pulse", 0.0)
	_timer_label.scale = Vector2.ONE * (1.0 + 0.06 * pulse)
	_heartbeat_accum += delta
	var interval := 0.65 if urgent else 1.0  # ~92 BPM when urgent
	if _heartbeat_accum >= interval:
		_heartbeat_accum = 0.0
		AudioSynthesizer.play_ui("heartbeat", -16.0, 1.15 if urgent else 1.0)


## Off-screen partner tracker: clamp an arrow label to the screen edge in
## the partner's color, pointing toward their live position.
func _update_partner_arrow() -> void:
	if not NetworkSession.multiplayer_active:
		return
	var me := _get_local_player()
	if me == null:
		return
	var partner: Player = null
	for p in get_tree().get_nodes_in_group("players"):
		if p != me:
			partner = p
			break
	if partner == null:
		_partner_arrow.visible = false
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var screen_pos := camera.unproject_position(partner.global_position + Vector3(0, 1.2, 0))
	var vp_size := Vector2(get_viewport().get_visible_rect().size)
	var margin := 46.0
	var on_screen := screen_pos.x > margin and screen_pos.x < vp_size.x - margin \
		and screen_pos.y > margin and screen_pos.y < vp_size.y - margin
	if on_screen:
		_partner_arrow.visible = false
		return
	_partner_arrow.visible = true
	_partner_arrow.modulate = partner.player_color()
	_partner_arrow.position = Vector2(
		clampf(screen_pos.x, margin, vp_size.x - margin) - 40.0,
		clampf(screen_pos.y, margin, vp_size.y - margin) - 16.0)


## Animated milestone banner at top-center.
func show_banner(text: String) -> void:
	_banner.text = text
	if _banner_tween:
		_banner_tween.kill()
	_banner.modulate.a = 0.0
	_banner.scale = Vector2(0.8, 0.8)
	_banner_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.3)
	_banner_tween.tween_property(_banner, "scale", Vector2.ONE, 0.35)
	_banner_tween.chain().tween_interval(2.4)
	_banner_tween.chain().tween_property(_banner, "modulate:a", 0.0, 0.5)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		request_restart()


## Solo: instant reload. Co-op: only the host may restart; it rolls a new
## shared seed and reloads every peer in lockstep.
func request_restart() -> void:
	if NetworkSession.multiplayer_active:
		if multiplayer.is_server():
			_net_restart.rpc((randi() % 2147483646) + 1)
	else:
		get_tree().paused = false
		get_tree().reload_current_scene()


@rpc("authority", "call_local", "reliable")
func _net_restart(new_seed: int) -> void:
	NetworkSession.run_seed = new_seed
	get_tree().paused = false
	get_tree().reload_current_scene()


func _get_local_player() -> Player:
	if is_instance_valid(_local_player):
		return _local_player
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_local_player():
			_local_player = p
			return p
	return null


func _on_breaker_powered() -> void:
	_breaker_done = true
	if state == State.PREGAME:
		state = State.PLAYING
	show_banner("MANSION POWER RESTORED!")
	_refresh_objectives()


func _on_wrench_grabbed(_by: Node3D) -> void:
	_wrench_found = true
	_refresh_objectives()


func _on_will_grabbed(_by: Node3D) -> void:
	show_banner("THE WILL SECURED — ESCAPE TO THE PORCH!")


func _on_gears_changed(placed: int) -> void:
	_gears_placed = placed
	_refresh_objectives()


func _on_clock_completed() -> void:
	_clock_done = true
	show_banner("THE GRANDFATHER CLOCK AWAKENS!")
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
	for p in get_tree().get_nodes_in_group("players"):
		var held: Node = p.held_item
		if held == null or not held.is_in_group("will_items"):
			continue
		for zone in _exit_zones:
			if zone.overlaps_body(p):
				_trigger_win()
				return


func _trigger_win() -> void:
	if state != State.PLAYING:
		return
	if NetworkSession.multiplayer_active:
		_net_win.rpc(run_time - time_left)
	else:
		_win(run_time - time_left)


func _trigger_lose() -> void:
	if state != State.PLAYING:
		return
	if NetworkSession.multiplayer_active:
		_net_lose.rpc()
	else:
		_lose()


@rpc("authority", "call_local", "reliable")
func _net_win(elapsed: float) -> void:
	_win(elapsed)


@rpc("authority", "call_local", "reliable")
func _net_lose() -> void:
	_lose()


func _win(elapsed: float) -> void:
	if state != State.PLAYING:
		return
	state = State.WON
	_refresh_objectives()
	_end_title.text = "Inheritance Secured!"
	_end_subtitle.text = "Completed in %s — Press [R] to restart" % _format_time(elapsed)
	_end_screen.visible = true
	if not NetworkSession.multiplayer_active:
		get_tree().paused = true


func _lose() -> void:
	if state != State.PLAYING:
		return
	state = State.LOST
	_end_title.text = "Mansion Sealed Forever!"
	_end_subtitle.text = "The clockwork lock clicks shut. Press [R] to restart"
	_end_screen.visible = true
	if not NetworkSession.multiplayer_active:
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
