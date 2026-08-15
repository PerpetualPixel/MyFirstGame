class_name Player
extends CharacterBody3D

## Isometric player controller: 8-direction camera-relative WASD movement
## with smooth acceleration/rotation, a smoothly following isometric camera,
## and an [E] interaction probe in front of the body.

@export_group("Movement")
@export var max_speed: float = 6.0
@export var acceleration: float = 30.0
@export var deceleration: float = 40.0
## How quickly the body turns to face its movement direction.
@export var rotation_speed: float = 12.0

@export_group("Camera")
@export var camera_follow_speed: float = 8.0
## Orthographic size bounds: smaller = closer. The camera is orthographic,
## so zoom means changing Camera3D.size — moving it only slides the frame.
@export var camera_zoom_min: float = 7.0
@export var camera_zoom_max: float = 16.0
@export var camera_zoom_speed: float = 1.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var _camera: Camera3D = $CameraPivot/Camera3D
@onready var interaction_area: Area3D = $InteractionArea
@onready var hold_point: Node3D = $HoldPoint
@onready var _prompt: Label3D = $InteractPrompt
@onready var _visual: Node3D = $CharacterVisual

var _anim_player: AnimationPlayer
var _idle_anim := ""
var _walk_anim := ""
var _action_anim := ""
var _visual_base_pos := Vector3.ZERO
var _gait_phase := 0.0
var _adjusting_mirror: RotatingMirror = null
var _mirror_sync_accum := 0.0
var _step_accum := 0.9
var _last_mouse_x := 0.0
var _fade_walls: Array = []
var _wall_blocking := {}
var _fade_frame := 0
var _prompt_frame := 0

## Replicated by the MultiplayerSynchronizer: remote peers drive the walk
## animation from this instead of simulated velocity.
var net_speed := 0.0
## True while a fullscreen UI (wiring minigame in co-op) owns the input.
var ui_locked := false

## The player this machine controls (for camera shake and QoL helpers).
static var local_instance: Player

var _trauma := 0.0
var _camera_base_pos := Vector3.ZERO
var _zoom_tween: Tween


func _enter_tree() -> void:
	# Spawned players are named after their peer id ("1" = host).
	if str(name).is_valid_int():
		set_multiplayer_authority(str(name).to_int())


func _exit_tree() -> void:
	if local_instance == self:
		local_instance = null


func is_local_player() -> bool:
	return not NetworkSession.multiplayer_active or is_multiplayer_authority()


func player_id() -> int:
	return str(name).to_int() if str(name).is_valid_int() else 1


func player_color() -> Color:
	return Color(1.0, 0.72, 0.25) if player_id() == 1 else Color(0.3, 0.9, 1.0)


## Camera trauma with distance falloff; safe to call from anywhere.
static func shake(amount: float, at: Vector3) -> void:
	if local_instance == null:
		return
	var falloff := 1.0 / (1.0 + local_instance.global_position.distance_to(at) * 0.12)
	local_instance._trauma = clampf(local_instance._trauma + amount * falloff, 0.0, 1.0)

## Small Resident Evil-style pack: up to 3 items ride along (hidden,
## frozen, parented to the player) and get used or consumed at
## interaction sites. [Q] drops the most recently taken item.
const INVENTORY_SIZE := 3
var inventory: Array[Grabbable] = []

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	add_to_group("players")
	# CameraPivot is top_level: it never inherits the body's rotation,
	# so snap it onto the player once at spawn.
	camera_pivot.global_position = global_position
	_camera_base_pos = _camera.position
	_camera.current = is_local_player()
	if is_local_player():
		local_instance = self
	_setup_character_visual()
	_add_identity_ring()


## Colored identity ring at the feet: Host/P1 amber, partner cyan.
func _add_identity_ring() -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.4
	torus.outer_radius = 0.5
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = player_color()
	mat.emission_enabled = true
	mat.emission = player_color()
	mat.emission_energy_multiplier = 1.6
	torus.material = mat
	ring.mesh = torus
	ring.position = Vector3(0, 0.06, 0)
	ring.scale = Vector3(1, 0.3, 1)
	add_child(ring)


## Normalize the imported character model no matter how it was authored:
## uniform-scale to 1.8 m tall, feet on y = 0, centered on the body origin,
## rotated to face -Z (glTF models front +Z). Also picks up any built-in
## AnimationPlayer so rigged assets drive themselves.
func _setup_character_visual() -> void:
	var aabb := _merged_visual_aabb()
	if aabb.size.y > 0.001:
		var s := 1.8 / aabb.size.y
		var center := aabb.get_center()
		_visual.scale = Vector3.ONE * s
		_visual.rotation.y = PI
		# Rotation by PI maps (x, z) -> (-x, -z), so offsetting by the
		# scaled center re-centers the model on the origin.
		_visual.position = Vector3(s * center.x, -s * aabb.position.y, s * center.z)
	_visual_base_pos = _visual.position

	_anim_player = _find_anim_player(_visual)
	if _anim_player:
		_register_external_animations()
		if _anim_player.has_animation("moves/walk"):
			_walk_anim = "moves/walk"
		if _anim_player.has_animation("moves/idle"):
			_idle_anim = "moves/idle"
		for anim_name in _anim_player.get_animation_list():
			var lower: String = anim_name.to_lower()
			if _idle_anim.is_empty() and "idle" in lower:
				_idle_anim = anim_name
			if _walk_anim.is_empty() and ("walk" in lower or "run" in lower):
				_walk_anim = anim_name


## Mixamo ships one clip per FBX (always named "mixamo_com"), so the extra
## animation files are loaded once and their clips transplanted into an
## animation library on the model's own AnimationPlayer. The rigs are
## identical, so the track paths (Skeleton3D:mixamorig_*) line up. Each
## clip is looped and converted to in-place (horizontal hip travel removed)
## so the character never slides away from her collision body.
const EXTRA_ANIM_SOURCES := {
	"walk": {"path": "res://assets/sophie/Standard Walk.fbx", "loop": true},
	"walk_start": {"path": "res://assets/sophie/Female Start Walking.fbx", "loop": true},
	"turn_180": {"path": "res://assets/sophie/Walking Turn 180.fbx", "loop": true},
	"idle": {"path": "res://assets/sophie/Idle.fbx", "loop": true},
	"pick_up": {"path": "res://assets/sophie/Picking Up.fbx", "loop": false},
	"open_door": {"path": "res://assets/sophie/Opening Door Inwards.fbx", "loop": false},
}


## Extracted once per process and cached: instantiating three ~50 MB FBX
## scenes just to steal their clips is far too slow to repeat on every
## restart ([R] reloads the whole scene).
static var _shared_anim_lib: AnimationLibrary


func _register_external_animations() -> void:
	if _shared_anim_lib == null:
		_shared_anim_lib = AnimationLibrary.new()
		for anim_name in EXTRA_ANIM_SOURCES:
			var source: Dictionary = EXTRA_ANIM_SOURCES[anim_name]
			var scene: PackedScene = load(source["path"])
			if scene == null:
				continue
			var inst := scene.instantiate()
			var src := _find_anim_player(inst)
			if src and src.has_animation("mixamo_com"):
				var anim: Animation = src.get_animation("mixamo_com").duplicate()
				if source["loop"]:
					anim.loop_mode = Animation.LOOP_LINEAR
				_make_in_place(anim)
				_shared_anim_lib.add_animation(anim_name, anim)
			inst.free()
	if not _shared_anim_lib.get_animation_list().is_empty():
		_anim_player.add_animation_library("moves", _shared_anim_lib)


## Strip horizontal root/hip travel from a clip, keeping vertical bounce.
static func _make_in_place(anim: Animation) -> void:
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		if not str(anim.track_get_path(i)).to_lower().contains("hips"):
			continue
		var key_count := anim.track_get_key_count(i)
		if key_count == 0:
			continue
		var first: Vector3 = anim.track_get_key_value(i, 0)
		var last: Vector3 = anim.track_get_key_value(i, key_count - 1)
		if Vector2(last.x - first.x, last.z - first.z).length() < 0.1:
			continue  # already an in-place cycle
		for k in key_count:
			var v: Vector3 = anim.track_get_key_value(i, k)
			anim.track_set_key_value(i, k, Vector3(first.x, v.y, first.z))


func _merged_visual_aabb() -> AABB:
	var merged := AABB()
	var first := true
	var inv := _visual.global_transform.affine_inverse()
	var stack: Array = [_visual]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and node.mesh != null:
			var rel: Transform3D = inv * (node as MeshInstance3D).global_transform
			var box: AABB = rel * (node as MeshInstance3D).get_aabb()
			merged = box if first else merged.merge(box)
			first = false
		stack.append_array(node.get_children())
	return merged


## Play a short one-shot clip (e.g. "moves/pick_up") over the locomotion;
## it finishes on its own or is cancelled by movement. Slightly sped up so
## flavor animations never hold up gameplay.
func play_action(anim_name: String) -> void:
	if _anim_player == null or not _anim_player.has_animation(anim_name):
		return
	_action_anim = anim_name
	_anim_player.play(anim_name, 0.15)
	_anim_player.speed_scale = 1.4


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_anim_player(child)
		if found:
			return found
	return null


## Instantly move the player somewhere, bringing the camera along instead of
## letting it lerp across the whole map.
func teleport(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	camera_pivot.global_position = pos


func _physics_process(delta: float) -> void:
	# Remote replicas: position/rotation arrive via the synchronizer; only
	# the walk animation runs locally, driven by the replicated speed.
	if not is_local_player():
		_animate_visual(delta)
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta

	var input_dir := Vector2.ZERO if ui_locked else Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# Mirror rotation mode: mouse movement swivels; check distance and exit.
	if _adjusting_mirror:
		if global_position.distance_to(_adjusting_mirror.global_position) > 3.5:
			_finish_mirror_adjust()
		input_dir = Vector2.ZERO
	# Rotate input by the camera yaw so "up" always moves away from the camera.
	var direction := camera_pivot.basis * Vector3(input_dir.x, 0.0, input_dir.y)

	var flat_velocity := Vector3(velocity.x, 0.0, velocity.z)
	if direction:
		flat_velocity = flat_velocity.move_toward(direction * max_speed, acceleration * delta)
		# Face the movement direction (-Z is the body's forward).
		var target_angle := atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, target_angle, 1.0 - exp(-rotation_speed * delta))
	else:
		flat_velocity = flat_velocity.move_toward(Vector3.ZERO, deceleration * delta)
	velocity.x = flat_velocity.x
	velocity.z = flat_velocity.z

	move_and_slide()
	net_speed = Vector2(velocity.x, velocity.z).length()
	_update_wall_fade(delta)
	_animate_visual(delta)
	_update_footsteps(delta)
	_update_camera_shake(delta)


## Trauma-based shake: squared falloff, random offsets on the camera.
func _update_camera_shake(delta: float) -> void:
	if _trauma <= 0.0:
		return
	_trauma = maxf(_trauma - delta * 1.4, 0.0)
	var intensity := _trauma * _trauma
	_camera.position = _camera_base_pos + Vector3(
		randf_range(-1, 1) * 0.35 * intensity,
		randf_range(-1, 1) * 0.3 * intensity,
		0.0)
	if _trauma <= 0.0:
		_camera.position = _camera_base_pos


## Stride-timed footsteps; stone on the porch/yard, hardwood indoors.
func _update_footsteps(delta: float) -> void:
	if not is_on_floor():
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.5:
		_step_accum = 0.9  # primed so the first step lands immediately
		return
	_step_accum += speed * delta
	if _step_accum >= 1.5:
		_step_accum = 0.0
		var sound := "footstep_stone" if global_position.z > 14.9 else "footstep_wood"
		AudioSynthesizer.play_at(sound, global_position, -16.0)


## Skeletal animations when the asset has them; otherwise a procedural
## gait: stride-synced bobbing, momentum lean, and breathing sway at rest.
func _animate_visual(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length() if is_local_player() else net_speed
	var stride := clampf(speed / max_speed, 0.0, 1.0)

	if _anim_player and not _walk_anim.is_empty():
		# One-shot action (pick up, open door) plays out unless the player
		# starts moving, which cancels straight back into the walk.
		if not _action_anim.is_empty():
			var action_running := _anim_player.is_playing() and _anim_player.current_animation == _action_anim
			if action_running and speed <= 0.1:
				return
			_action_anim = ""
		if speed > 0.1:
			_visual.position = _visual_base_pos
			if _anim_player.current_animation != _walk_anim or not _anim_player.is_playing():
				_anim_player.play(_walk_anim, 0.25)
			# Foot cadence follows actual movement speed.
			_anim_player.speed_scale = 0.5 + stride * 0.9
		elif not _idle_anim.is_empty():
			if _anim_player.current_animation != _idle_anim:
				_anim_player.play(_idle_anim, 0.25)
			_anim_player.speed_scale = 1.0
		else:
			# No idle clip shipped: hold the stance frame, breathe gently.
			if _anim_player.is_playing():
				_anim_player.seek(0.0, true)
				_anim_player.pause()
			_gait_phase += delta
			_visual.position = _visual_base_pos + Vector3(0, sin(_gait_phase * 2.2) * 0.008, 0)
		return

	_gait_phase += delta * (2.0 + speed * 2.4)
	var bob := absf(sin(_gait_phase)) * 0.06 * stride
	var breathe := sin(_gait_phase * 0.35) * 0.012 * (1.0 - stride)
	_visual.position = _visual_base_pos + Vector3(0, bob + breathe, 0)
	var weight := 1.0 - exp(-8.0 * delta)
	_visual.rotation.x = lerpf(_visual.rotation.x, 0.1 * stride, weight)
	_visual.rotation.z = sin(_gait_phase * 0.5) * 0.02 * stride


## Any wall (group "fade_walls") that blocks the camera's view of the player
## — or stands close by on the camera side — eases to 20% opacity so the
## character and doorways are never hidden.
## Perf: the wall list is cached (walls only change on scene reload), the
## ray/proximity test runs at 20 Hz, converged materials are not rewritten,
## and fully-opaque walls render in the OPAQUE pass — transparency is only
## enabled while a wall is actually mid-fade.
func _update_wall_fade(delta: float) -> void:
	if _fade_walls.is_empty():
		_fade_walls = get_tree().get_nodes_in_group("fade_walls")
		if _fade_walls.is_empty():
			return
	_fade_frame += 1
	if _fade_frame >= 3:
		_fade_frame = 0
		_wall_blocking = _compute_blocking_walls()

	var weight := 1.0 - exp(-10.0 * delta)
	for wall in _fade_walls:
		if not is_instance_valid(wall):
			continue
		var mat: StandardMaterial3D = wall.material
		if mat == null:
			continue
		var target := 0.5 if _wall_blocking.has(wall) else 1.0
		var alpha: float = mat.albedo_color.a
		if absf(alpha - target) < 0.004:
			if target >= 1.0 and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				mat.albedo_color.a = 1.0
				mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			continue
		if mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = lerpf(alpha, target, weight)


func _compute_blocking_walls() -> Dictionary:
	var blocking := {}
	var space := get_world_3d().direct_space_state
	var cam_pos := _camera.global_position
	var cam_right := _camera.global_transform.basis.x

	# Three rays (center + both shoulders) catch walls a single ray misses.
	for side_offset: Vector3 in [Vector3.ZERO, cam_right * 0.9, cam_right * -0.9]:
		var to := global_position + Vector3.UP + side_offset
		var exclude: Array[RID] = [get_rid()]
		for i in 4:
			var query := PhysicsRayQueryParameters3D.create(cam_pos + side_offset, to)
			query.exclude = exclude
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				break
			var collider: Object = hit["collider"]
			if collider is Node3D and (collider as Node3D).is_in_group("fade_walls"):
				blocking[collider] = true
			exclude.append(hit["rid"])

	# Proximity: fade walls whose nearest point is very close (reveals
	# doorways when approaching from any side, e.g. the porch entrance) or
	# within 3 m on the camera side (south/east walls hiding the character).
	var cam_side := cam_pos - global_position
	cam_side.y = 0.0
	cam_side = cam_side.normalized()
	for wall in _fade_walls:
		if blocking.has(wall) or not is_instance_valid(wall):
			continue
		var half: Vector3 = wall.size * 0.5
		var local: Vector3 = global_position - wall.global_position
		var closest := Vector3(
			clampf(local.x, -half.x, half.x), 0.0, clampf(local.z, -half.z, half.z))
		var away := Vector3(local.x - closest.x, 0.0, local.z - closest.z)
		var dist := away.length()
		if dist < 2.0:
			blocking[wall] = true
		elif dist < 3.0 and -away.normalized().dot(cam_side) > 0.3:
			blocking[wall] = true
	return blocking


func _process(delta: float) -> void:
	if not is_local_player():
		return
	# Exponential smoothing keeps the follow frame-rate independent.
	var weight := 1.0 - exp(-camera_follow_speed * delta)
	camera_pivot.global_position = camera_pivot.global_position.lerp(global_position, weight)
	_update_prompt()


## Floats prompt text above the nearest interactable; while carrying, a
## "[Q] Drop" hint rides along (or floats over the held item if nothing
## else is in reach).
func _update_prompt() -> void:
	# 20 Hz is plenty for prompt tracking; skip the overlap scan otherwise.
	_prompt_frame += 1
	if _prompt_frame < 3:
		return
	_prompt_frame = 0
	var text := ""
	var anchor: Node3D = null
	var height := 1.6
	var target := get_nearest_interactable()
	if target is Interactable:
		text = target.get_prompt(self)
		anchor = target
		height = target.prompt_height
	elif target:
		text = "[E] Use"
		anchor = target
	if not inventory.is_empty():
		var last: Grabbable = inventory.back()
		var drop_hint := "[Q] Drop %s (%d/%d)" % [last.display_name, inventory.size(), INVENTORY_SIZE]
		if anchor:
			text += "\n" + drop_hint
		else:
			text = drop_hint
			anchor = self
			height = 2.3
	if anchor:
		if _prompt.text != text:
			_prompt.text = text  # Label3D rebuilds its mesh on text set
		_prompt.global_position = anchor.global_position + Vector3(0, height, 0)
		_prompt.visible = true
	else:
		_prompt.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not is_local_player() or ui_locked:
		return
	# Scroll wheel zoom: the camera is orthographic, so zoom by tweening
	# its projection size (position is owned by the follow/shake logic).
	if event is InputEventMouseButton and event.pressed:
		var zoom_dir := 0.0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_dir = -1.0
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_dir = 1.0
		if zoom_dir != 0.0:
			var target_size := clampf(_camera.size + zoom_dir * camera_zoom_speed, camera_zoom_min, camera_zoom_max)
			if _zoom_tween and _zoom_tween.is_running():
				_zoom_tween.kill()
			_zoom_tween = create_tween()
			_zoom_tween.tween_property(_camera, "size", target_size, 0.12)
			get_viewport().set_input_as_handled()
	# Mirror rotation: mouse motion swivels; E or ESC exits.
	if _adjusting_mirror:
		if event is InputEventMouseMotion:
			_adjusting_mirror.adjust_by_mouse(event.relative.x)
			# Stream the live angle to the partner at 10 Hz.
			_mirror_sync_accum += 0.016  # approximate delta
			if NetworkSession.multiplayer_active and _mirror_sync_accum >= 0.1:
				_mirror_sync_accum = 0.0
				_adjusting_mirror._net_set_angle.rpc(_adjusting_mirror.rotation.y)
		elif event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
			_finish_mirror_adjust()
			get_viewport().set_input_as_handled()
		return

	# [E] always interacts (valves, doors, mirrors work while carrying);
	# [Q] is the dedicated drop key, so tools are never dropped by accident.
	if event.is_action_pressed("interact"):
		var target := get_nearest_interactable()
		if target is RotatingMirror:
			# Enter mirror rotation mode.
			_adjusting_mirror = target
			_adjusting_mirror.start_rotating()
		elif target:
			request_interact(target)
	elif event.is_action_pressed("drop"):
		if NetworkSession.multiplayer_active:
			_net_drop.rpc()
		else:
			drop_held()
	elif event.is_action_pressed("ping"):
		var at := global_position - global_transform.basis.z * 1.5
		if NetworkSession.multiplayer_active:
			_net_ping.rpc(at)
		else:
			_spawn_ping(at)


func _finish_mirror_adjust() -> void:
	if _adjusting_mirror == null:
		return
	_adjusting_mirror.end_adjust()
	if NetworkSession.multiplayer_active:
		_adjusting_mirror._net_finish_angle.rpc(_adjusting_mirror.rotation.y)
	_adjusting_mirror = null
	_mirror_sync_accum = 0.0


## Route an interaction: in co-op it executes on EVERY peer via an RPC on
## this player node, so `self` resolves to the correct replica everywhere
## and world state (doors, valves, gears, carried items) stays consistent.
func request_interact(target: Node) -> void:
	if NetworkSession.multiplayer_active:
		_net_interact.rpc(target.get_path())
	else:
		_do_interact_target(target)


@rpc("any_peer", "call_local", "reliable")
func _net_interact(path: NodePath) -> void:
	if NetworkSession.multiplayer_active:
		var sender := multiplayer.get_remote_sender_id()
		if sender != 0 and sender != get_multiplayer_authority():
			return
	var target := get_node_or_null(path)
	if target and target.has_method("interact"):
		_do_interact_target(target)


func _do_interact_target(target: Node) -> void:
	target.interact(self)
	if target is Door and not (target as Door).locked:
		play_action("moves/open_door")


@rpc("any_peer", "call_local", "reliable")
func _net_drop() -> void:
	if NetworkSession.multiplayer_active:
		var sender := multiplayer.get_remote_sender_id()
		if sender != 0 and sender != get_multiplayer_authority():
			return
	drop_held()


@rpc("any_peer", "call_local", "reliable")
func _net_ping(at: Vector3) -> void:
	_spawn_ping(at)


## Glowing 4-second ping beacon in this player's color, with a chime.
func _spawn_ping(at: Vector3) -> void:
	var beacon := Node3D.new()
	var column := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.3
	cyl.height = 2.6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tint := player_color()
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.45)
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 2.0
	cyl.material = mat
	column.mesh = cyl
	column.position = Vector3(0, 1.3, 0)
	beacon.add_child(column)
	var label := Label3D.new()
	label.text = "Player %d pinged here!" % player_id()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 40
	label.outline_size = 10
	label.pixel_size = 0.007
	label.modulate = tint
	label.position = Vector3(0, 2.9, 0)
	beacon.add_child(label)
	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = 1.2
	light.omni_range = 4.0
	light.position = Vector3(0, 1.2, 0)
	beacon.add_child(light)
	beacon.position = at
	var parent_node: Node = get_tree().current_scene
	if parent_node == null:
		parent_node = get_parent()
	parent_node.add_child(beacon)
	AudioSynthesizer.play_at("chime", at, -12.0, 1.5)
	get_tree().create_timer(4.0).timeout.connect(beacon.queue_free)


## Called by Grabbable.interact(); stows the item in the pack.
func pick_up(item: Grabbable) -> void:
	if inventory.has(item) or inventory.size() >= INVENTORY_SIZE:
		return
	inventory.append(item)
	item.stash(self)
	play_action("moves/pick_up")


## [Q]: drop the most recently taken item back into the world.
func drop_held() -> void:
	if inventory.is_empty():
		return
	var item: Grabbable = inventory.pop_back()
	item.release()


func inventory_full() -> bool:
	return inventory.size() >= INVENTORY_SIZE


## First carried item belonging to `group`, or null.
func inventory_find(group: String) -> Grabbable:
	for item in inventory:
		if is_instance_valid(item) and item.is_in_group(group):
			return item
	return null


## Forget a consumed/placed item (does not free or move the node).
func inventory_remove(item: Grabbable) -> void:
	inventory.erase(item)


## Returns the closest overlapping node that exposes an interact() method,
## or null when nothing is in reach.
func get_nearest_interactable() -> Node3D:
	var candidates: Array = []
	candidates.append_array(interaction_area.get_overlapping_bodies())
	candidates.append_array(interaction_area.get_overlapping_areas())

	var nearest: Node3D = null
	var nearest_dist := INF
	for node in candidates:
		if node == self or not node.has_method("interact"):
			continue
		if node is Interactable and not node.can_interact(self):
			continue
		var dist: float = global_position.distance_squared_to(node.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = node
	return nearest
