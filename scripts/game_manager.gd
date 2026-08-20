class_name GameManager
extends Node

## Runs the game loop. PREGAME on the porch with the timer frozen at 4:00;
## powering the breaker starts PLAYING. Win: crack the vault strongbox,
## then carry the Will into the porch exit zone — which cuts to a short
## victory cinematic (cinematic camera on the idle character) and an
## RE-style S/A/B/C/D rank screen graded on elapsed time. Loss: timer
## hits zero. In co-op the HOST owns the countdown and win/loss verdicts
## and replicates them; each peer's HUD objectives update from
## locally-replicated puzzle events. Also drives the countdown tension
## layer (amber/red timer, heartbeat, vignette pulse), milestone banners,
## Mrs. Puddle's event radio lines, and the off-screen partner tracker.

enum State { PREGAME, PLAYING, WON, LOST }

## Countdown once the breaker powers the mansion (the crowbar/fuse hunt
## before that is untimed). Matches the menu art's billed pitch ("A
## 4-Minute Co-op Puzzle Heist").
@export var run_time: float = 240.0

## Playtest switch: uncheck on the GameManager node to run without a
## clock — the countdown freezes, the tension layer stays quiet and
## the run can never be lost on time, so a level can be explored at
## leisure. Everything else (puzzles, the win, the rank screen) is
## untouched. MUST be back on for a real build.
@export var timer_enabled: bool = true

@onready var _mansion: MansionGenerator = $"../MansionGenerator"
@onready var _hud: HUD = $"../HUD"
@onready var _timer_label: Label = $"../HUD/TimerLabel"
@onready var _obj_breaker: Label = $"../HUD/Objectives/BreakerObjective"
@onready var _obj_clock: Label = $"../HUD/Objectives/ClockObjective"  # now the puzzle box
@onready var _obj_wrench: Label = $"../HUD/Objectives/WrenchObjective"
@onready var _obj_steam: Label = $"../HUD/Objectives/SteamObjective"
@onready var _obj_light: Label = $"../HUD/Objectives/LightObjective"
@onready var _obj_strongbox: Label = $"../HUD/Objectives/StrongboxObjective"
@onready var _obj_will: Label = $"../HUD/Objectives/WillObjective"
@onready var _end_screen: Control = $"../HUD/EndScreen"
@onready var _end_title: Label = $"../HUD/EndScreen/Center/VBox/Title"
@onready var _end_rank: Label = $"../HUD/EndScreen/Center/VBox/Rank"
@onready var _end_flavor: Label = $"../HUD/EndScreen/Center/VBox/Flavor"
@onready var _end_subtitle: Label = $"../HUD/EndScreen/Center/VBox/Subtitle"
@onready var _end_dim: ColorRect = $"../HUD/EndScreen/Dim"
@onready var _banner: Label = $"../HUD/Banner"
@onready var _partner_arrow: Label = $"../HUD/PartnerArrow"
@onready var _vignette: ColorRect = $"../HUD/Vignette"

var state := State.PREGAME
var time_left: float

var _breaker_done := false
var _puzzle_box_done := false
var _small_wrench_found := false
var _big_wrench_found := false
var _light_done := false
var _pressure_done := false
var _lockbox_done := false
var _warned_last_minute := false
var _cine_cam: Camera3D
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
	for wrench in get_tree().get_nodes_in_group("small_wrenches"):
		wrench.grabbed.connect(_on_small_wrench_grabbed)
	for wrench in get_tree().get_nodes_in_group("big_wrenches"):
		wrench.grabbed.connect(_on_big_wrench_grabbed)
	for box in get_tree().get_nodes_in_group("puzzle_boxes"):
		box.puzzle_unlocked.connect(_on_puzzle_box_unlocked)
	for lockbox in get_tree().get_nodes_in_group("lock_boxes"):
		lockbox.unlocked.connect(_on_lockbox_unlocked)
	for vault in get_tree().get_nodes_in_group("vault_doors"):
		vault.opened.connect(func() -> void:
			show_banner("VAULT GATE UNLOCKED!")
			_hud.say(Story.RADIO["vault"]))
	for will in get_tree().get_nodes_in_group("will_items"):
		will.grabbed.connect(_on_will_grabbed)
	for press in get_tree().get_nodes_in_group("pressure_puzzles"):
		press.puzzle_solved.connect(_on_pressure_solved)
	_exit_zones = get_tree().get_nodes_in_group("exit_zones")

	_timer_label.text = _format_time(time_left) if timer_enabled else "--:--"
	if not timer_enabled:
		_timer_label.modulate = Color(0.55, 0.85, 1.0)
		print("[GameManager] timer_enabled = false: playtest mode, no time limit")
	_refresh_objectives()


func _process(delta: float) -> void:
	if state == State.WON or state == State.LOST:
		return  # end chrome owns the screen (and the victory cinematic the camera)
	_update_partner_arrow()
	if state != State.PLAYING or get_tree().paused:
		return
	if timer_enabled:
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
	if timer_enabled and NetworkSession.multiplayer_active and multiplayer.is_server():
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
	if not _warned_last_minute:
		_warned_last_minute = true
		_hud.say(Story.RADIO["last_minute"])
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
	_hud.say(Story.RADIO["power"])
	_refresh_objectives()


func _on_small_wrench_grabbed(_by: Node3D) -> void:
	_small_wrench_found = true
	_refresh_objectives()


func _on_big_wrench_grabbed(_by: Node3D) -> void:
	_big_wrench_found = true
	_refresh_objectives()


func _on_will_grabbed(_by: Node3D) -> void:
	show_banner("THE WILL SECURED — ESCAPE TO THE PORCH!")
	_hud.say(Story.RADIO["will"])


func _on_puzzle_box_unlocked() -> void:
	_puzzle_box_done = true
	show_banner("THE PUZZLE BOX UNLOCKS!")
	_hud.say(Story.RADIO["puzzle_box"])
	_refresh_objectives()


func _on_lockbox_unlocked() -> void:
	_lockbox_done = true
	show_banner("THE STRONGBOX OPENS!")
	_hud.say(Story.RADIO["strongbox"])
	_refresh_objectives()


func _on_light_puzzle_solved() -> void:
	_light_done = true
	_hud.say(Story.RADIO["safe"])
	_refresh_objectives()


func _on_pressure_solved() -> void:
	_pressure_done = true
	show_banner("HYDRAULIC PRESSURE BALANCED!")
	_hud.say(Story.RADIO["pressure"])
	_refresh_objectives()


func _check_win() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.has_method("inventory_find") or p.inventory_find("will_items") == null:
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
	_begin_victory_sequence(elapsed)


## RE-style finish. The tree is deliberately NOT paused (that would
## freeze the character's AnimationPlayer): input is locked instead, a
## perspective cinematic camera pushes in on the idling character, the
## fanfare plays, and after a beat the rank screen fades over the shot.
## Runs per-machine (each peer frames its own local character).
func _begin_victory_sequence(elapsed: float) -> void:
	_close_open_modals()
	_timer_label.visible = false
	_partner_arrow.visible = false
	_vignette.visible = false
	if _banner_tween:
		_banner_tween.kill()
	_banner.modulate.a = 0.0
	_hud.hide_gameplay_chrome()
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_local_player():
			p.ui_locked = true
			p.set("_trauma", 0.0)
	AudioSynthesizer.play_ui("fanfare", -4.0)
	var me := _get_local_player()
	if me != null:
		_cine_cam = Camera3D.new()
		_cine_cam.fov = 38.0
		add_child(_cine_cam)
		# The body's forward is -Z: frame the shot from where the character
		# faces, slightly above eye height, easing in slowly. Interior rooms
		# are only 10 m across, so a character facing a wall would put the
		# camera inside it (nothing fades for a camera that isn't the
		# player's own) — _pick_cine_angle finds one with line of sight.
		var focus: Vector3 = me.global_position + Vector3(0, 1.25, 0)
		var shot: Vector3 = _pick_cine_angle(me, focus)
		var from: Vector3 = me.global_position + shot + Vector3(0, 1.8, 0)
		var to: Vector3 = me.global_position + shot * 0.64 + Vector3(0, 1.45, 0)
		_cine_cam.global_position = from
		_cine_cam.look_at(focus)
		_cine_cam.current = true
		var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_method(func(t: float) -> void:
			if not is_instance_valid(_cine_cam):
				return
			_cine_cam.global_position = from.lerp(to, t)
			_cine_cam.look_at(focus), 0.0, 1.0, 6.0)
	# Node-bound, so [R] during this beat kills it with the scene
	# instead of resuming the coroutine on a freed GameManager.
	var beat := create_tween()
	beat.tween_interval(1.4)
	await beat.finished
	if not is_instance_valid(self) or state != State.WON:
		return
	_show_victory_screen(elapsed)


## Camera offset for the victory shot: a direction with real line of
## sight, scaled to the room actually available. Prefers where the
## character is facing, then sweeps around them, and finally takes the
## least-blocked angle pulled in to just short of whatever it hit — so
## the shot is never framed from inside a wall.
const CINE_DISTANCE := 3.6
const CINE_MIN_DISTANCE := 1.5


func _pick_cine_angle(me: Node3D, focus: Vector3) -> Vector3:
	var facing: Vector3 = -me.global_transform.basis.z
	var space := me.get_world_3d().direct_space_state
	var best: Vector3 = facing * CINE_MIN_DISTANCE
	var best_room := -1.0
	for step in [0.0, 40.0, -40.0, 80.0, -80.0, 130.0, -130.0, 180.0]:
		var dir: Vector3 = Basis(Vector3.UP, deg_to_rad(step)) * facing
		var probe := PhysicsRayQueryParameters3D.create(
			focus, focus + dir * (CINE_DISTANCE + 0.3))
		probe.exclude = [me.get_rid()]
		var hit := space.intersect_ray(probe)
		if hit.is_empty():
			return dir * CINE_DISTANCE
		# Blocked: remember how much room this angle really offers.
		var room: float = focus.distance_to(hit["position"]) - 0.35
		if room > best_room:
			best_room = room
			best = dir * clampf(room, CINE_MIN_DISTANCE, CINE_DISTANCE)
	return best


func _show_victory_screen(elapsed: float) -> void:
	_hud.end_run_chrome()
	var rank := Story.rank_for(elapsed)
	_end_title.text = "THE WILL IS YOURS"
	_end_rank.text = str(rank["letter"])
	_end_rank.modulate = rank["color"]
	_end_rank.visible = true
	_end_flavor.text = str(rank["flavor"])
	_end_flavor.visible = true
	_end_subtitle.text = "Sole heir of the Gearhart estate — %s — Press [R] to restart" % _format_time(elapsed)
	# Lighter dim than defeat: the character stays visible mid-frame.
	_end_dim.color.a = 0.45
	_end_screen.visible = true


func _lose() -> void:
	if state != State.PLAYING:
		return
	state = State.LOST
	_close_open_modals()
	_hud.end_run_chrome()
	_end_title.text = "Mansion Sealed Forever!"
	_end_rank.visible = false
	_end_flavor.visible = false
	_end_dim.color.a = 0.78
	_end_subtitle.text = "“Suits at the door. We're done here.” — Press [R] to restart"
	_end_screen.visible = true
	if not NetworkSession.multiplayer_active:
		get_tree().paused = true


## A verdict can land while someone sits inside a minigame overlay:
## co-op never pauses the tree, and the victory cinematic no longer
## pauses it in solo either. Those overlays are CanvasLayers at layer
## 10 and would bury the end screen (HUD is layer 1) — worse, closing
## one afterwards runs _set_local_lock(false) and hands movement back
## mid-cinematic. Shut them all before the end chrome goes up.
func _close_open_modals() -> void:
	for node in get_tree().get_nodes_in_group("modal_ui").duplicate():
		if not is_instance_valid(node):
			continue
		if not _try_close_modal(node):
			_try_close_modal(node.get_parent())


## Panels are reached either directly (the panel node carries the
## script) or through their owning Interactable, and each generation
## of them named its closer differently.
func _try_close_modal(n: Node) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	if n is EmoteWheel:
		(n as EmoteWheel).close(false)
		return true
	for method in ["_close_panel", "_close_ui", "close"]:
		if n.has_method(method):
			n.call(method)
			return true
	return false


func _refresh_objectives() -> void:
	var done_color := Color(0.55, 1.0, 0.65)
	var wrenches_ok := _small_wrench_found and _big_wrench_found
	var will_ok := state == State.WON

	_obj_breaker.text = "%s Restore Power" % _checkbox(_breaker_done)
	_obj_breaker.modulate = done_color if _breaker_done else Color.WHITE
	_obj_clock.text = "%s Crack the Puzzle Box" % _checkbox(_puzzle_box_done)
	_obj_clock.modulate = done_color if _puzzle_box_done else Color.WHITE
	_obj_wrench.text = "%s Gather the Two Wrenches" % _checkbox(wrenches_ok)
	_obj_wrench.modulate = done_color if wrenches_ok else Color.WHITE
	_obj_steam.text = "%s Balance the Hydraulic Press" % _checkbox(_pressure_done)
	_obj_steam.modulate = done_color if _pressure_done else Color.WHITE
	_obj_light.text = "%s Aim the Laser at the Wall Safe" % _checkbox(_light_done)
	_obj_light.modulate = done_color if _light_done else Color.WHITE
	_obj_strongbox.text = "%s Open the Vault Strongbox" % _checkbox(_lockbox_done)
	_obj_strongbox.modulate = done_color if _lockbox_done else Color.WHITE
	_obj_will.text = "%s Escape with the Will" % _checkbox(will_ok)
	_obj_will.modulate = done_color if will_ok else Color.WHITE


func _checkbox(done: bool) -> String:
	return "[X]" if done else "[ ]"


@warning_ignore("integer_division")
func _format_time(seconds: float) -> String:
	var total := ceili(seconds)
	return "%d:%02d" % [total / 60, total % 60]
