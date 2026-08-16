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
var _adjusting_mirror: PrismTable = null
var _mirror_sync_accum := 0.0
## Mirror hauling: the grabbed mirror rides at a fixed world-space offset
## from the player (walk toward it = push, away = drag), streamed to
## peers at 10 Hz. Cleared when released or when the mirror seats.
var _pushing_mirror: PrismTable = null
var _push_offset := Vector3.ZERO
var _push_sync_accum := 0.0
## Hauling a full-height mirror is slow work.
@export var push_speed_factor: float = 0.55
var _step_accum := 0.6
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
## Unwrapped camera yaw for the [Q] quarter-turn swings. Node3D wraps
## rotation.y into (-PI, PI], so reading it back after a few turns
## disagrees with an accumulated target by full revolutions and sends
## the tween spinning the long way around — these shadows are the only
## source of truth, and the node is write-only.
var _yaw_current := 0.0
var _yaw_target := 0.0
var _rotate_tween: Tween


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
## interaction sites. [G] drops the most recently taken item.
const INVENTORY_SIZE := 3
var inventory: Array[Grabbable] = []
## Two-hand load held out in front (the Heavy Battery) — separate from
## the pack, one at a time, and it slows the carrier to a crawl.
var carried_item: Grabbable = null
@export var carry_speed_factor: float = 0.5
## drop_at() index meaning "the carried load", not a pack slot.
const CARRY_SLOT := -2
## HUD slot highlighted via the 1/2/3 keys; [G] drops it (else the
## newest item). Local-machine concept — never replicated.
var selected_slot := -1

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	add_to_group("players")
	# CameraPivot is top_level: it never inherits the body's rotation,
	# so snap it onto the player once at spawn.
	camera_pivot.global_position = global_position
	_camera_base_pos = _camera.position
	_yaw_current = camera_pivot.rotation.y
	_yaw_target = _yaw_current
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
	# Hauling a prism table plays a real push cycle.
	"push": {"path": "res://assets/sophie/Push.fbx", "loop": true},
	# Two-hand load (the Heavy Battery): lift it, then walk carrying it.
	"lift": {"path": "res://assets/sophie/Lifting Object.fbx", "loop": false},
	"carry": {"path": "res://assets/sophie/Carrying.fbx", "loop": true},
	"carry_turn": {"path": "res://assets/sophie/Carrying Turn.fbx", "loop": true},
	# Crouched pick-up for floor items.
	"pick_up_object": {"path": "res://assets/sophie/Picking Up Object.fbx", "loop": false},
	# Emote wheel.
	"dance": {"path": "res://assets/sophie/Dancing.fbx", "loop": true},
	"dance_locking": {"path": "res://assets/sophie/Locking Hip Hop Dance.fbx", "loop": true},
	"dance_wave": {"path": "res://assets/sophie/Wave Hip Hop Dance.fbx", "loop": true},
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
			if not ResourceLoader.exists(source["path"]):
				continue
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
		_update_footsteps(delta)
		return

	# Yaw before this frame's steering, so the carry-turn clip can tell
	# whether the body is actually swinging round.
	_last_facing = rotation.y

	if not is_on_floor():
		velocity.y -= _gravity * delta

	var input_dir := Vector2.ZERO if ui_locked else Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# Mirror rotation mode: mouse movement swivels; check distance and exit.
	if _adjusting_mirror:
		if global_position.distance_to(_adjusting_mirror.global_position) > 3.5:
			_finish_mirror_adjust()
		input_dir = Vector2.ZERO
		# Keep facing the frame while it swivels under our hands.
		if is_instance_valid(_adjusting_mirror):
			var to_mirror := _adjusting_mirror.global_position - global_position
			if to_mirror.length() > 0.05:
				rotation.y = lerp_angle(rotation.y, atan2(-to_mirror.x, -to_mirror.z), 1.0 - exp(-10.0 * delta))
	# Hauling: the mirror seated itself (or vanished) -> hands off.
	var speed_cap := max_speed
	if carried_item != null:
		if not is_instance_valid(carried_item):
			carried_item = null
		else:
			speed_cap = max_speed * carry_speed_factor
	if _pushing_mirror:
		if not is_instance_valid(_pushing_mirror) or _pushing_mirror.seated \
				or _pushing_mirror.pusher != self:
			_finish_push()
		else:
			speed_cap = max_speed * push_speed_factor
	# Rotate input by the camera yaw so "up" always moves away from the camera.
	var direction := camera_pivot.basis * Vector3(input_dir.x, 0.0, input_dir.y)

	var flat_velocity := Vector3(velocity.x, 0.0, velocity.z)
	if direction:
		flat_velocity = flat_velocity.move_toward(direction * speed_cap, acceleration * delta)
		# Face the movement direction (-Z is the body's forward).
		var target_angle := atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, target_angle, 1.0 - exp(-rotation_speed * delta))
	else:
		flat_velocity = flat_velocity.move_toward(Vector3.ZERO, deceleration * delta)
	# The hauled mirror must not be shoved through walls or furniture:
	# test its destination first and drop the blocked axis so the player
	# still slides along obstacles instead of freezing dead.
	if _pushing_mirror and flat_velocity.length_squared() > 0.0001:
		var step := flat_velocity * delta
		if not _push_destination_clear(step):
			if _push_destination_clear(Vector3(step.x, 0, 0)):
				flat_velocity.z = 0.0
			elif _push_destination_clear(Vector3(0, 0, step.z)):
				flat_velocity.x = 0.0
			else:
				flat_velocity = Vector3.ZERO
	velocity.x = flat_velocity.x
	velocity.z = flat_velocity.z

	move_and_slide()
	net_speed = Vector2(velocity.x, velocity.z).length()
	if _pushing_mirror:
		_update_pushed_mirror(delta)
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


## Footsteps land exactly when the animated feet do: each frame the two
## foot bones' heights are read off the skeleton, and a step fires the
## instant a foot comes down onto its floor level (adaptive running
## minimum + hysteresis, so any rig/scale works). Falls back to a
## stride-length counter when the model has no skeleton. Surface comes
## from where the player stands (see _surface_at). Runs for remote
## replicas too, so a co-op partner's steps are heard.
func _update_footsteps(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length() if is_local_player() else net_speed
	if is_local_player() and not is_on_floor():
		return
	var moving := speed > 0.3
	if _foot_bones.is_empty():
		_find_foot_bones()
	if _foot_skeleton != null and not _foot_bones.is_empty():
		for i in _foot_bones.size():
			var world := _foot_skeleton.global_transform * _foot_skeleton.get_bone_global_pose(_foot_bones[i]).origin
			var h := world.y - global_position.y
			# Track each foot's floor level; relax slowly so drift recovers.
			if h < _foot_floor[i]:
				_foot_floor[i] = h
			else:
				_foot_floor[i] = minf(_foot_floor[i] + delta * 0.03, h)
			# The walk cycle only lifts a foot a few cm on this rig, so the
			# bands are tight: planted within 2 cm of its floor, re-armed
			# once it has cleared 4.5 cm.
			var down := h <= _foot_floor[i] + 0.02
			var lifted := h > _foot_floor[i] + 0.045
			if down and not _foot_down[i]:
				if moving:
					_play_footstep(i, speed)
				_foot_down[i] = true
			elif lifted:
				_foot_down[i] = false
		return
	# No skeleton: cadence from distance travelled (~0.75 m per step).
	if not moving:
		_step_accum = 0.6
		return
	_step_accum += speed * delta
	if _step_accum >= 0.75:
		_step_accum = 0.0
		_step_parity = 1 - _step_parity
		_play_footstep(_step_parity, speed)


# --- Emotes --------------------------------------------------------------

## Wheel entries: [animation, label]. Anything registered in
## EXTRA_ANIM_SOURCES can be emoted; missing clips are filtered out.
const EMOTES := [
	["moves/dance", "Dance"],
	["moves/dance_locking", "Locking"],
	["moves/dance_wave", "Wave"],
]

## The emote currently playing on this player (replicated), or "".
var _emote_anim := ""


## Emotes the character actually shipped with.
func available_emotes() -> Array:
	var found: Array = []
	for entry in EMOTES:
		if _anim_player == null or _anim_player.has_animation(entry[0]):
			found.append(entry)
	return found


## Start an emote: replicated so partners see the dance too.
func request_emote(anim_name: String) -> void:
	if NetworkSession.multiplayer_active:
		_net_emote.rpc(anim_name)
	else:
		play_emote(anim_name)


@rpc("any_peer", "call_local", "reliable")
func _net_emote(anim_name: String) -> void:
	play_emote(anim_name)


func play_emote(anim_name: String) -> void:
	if _anim_player == null or not _anim_player.has_animation(anim_name):
		return
	_emote_anim = anim_name
	_action_anim = ""
	_anim_player.play(anim_name, 0.25)
	_anim_player.speed_scale = 1.0


func stop_emote() -> void:
	if _emote_anim.is_empty():
		return
	_emote_anim = ""
	if _anim_player and not _idle_anim.is_empty():
		_anim_player.play(_idle_anim, 0.2)
		_anim_player.speed_scale = 1.0


## Running count of footfalls fired (tests read this).
var footsteps_played := 0
## Yaw last frame, for choosing the carry-turn clip.
var _last_facing := 0.0
var _foot_skeleton: Skeleton3D
var _foot_bones: Array[int] = []
var _foot_floor: Array[float] = [INF, INF]
var _foot_down: Array[bool] = [false, false]
var _step_parity := 0


func _find_foot_bones() -> void:
	var stack: Array = [_visual]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Skeleton3D:
			var skel := node as Skeleton3D
			var left := -1
			var right := -1
			for b in skel.get_bone_count():
				var lower := skel.get_bone_name(b).to_lower()
				if left < 0 and lower.ends_with("leftfoot"):
					left = b
				elif right < 0 and lower.ends_with("rightfoot"):
					right = b
			if left >= 0 and right >= 0:
				_foot_skeleton = skel
				_foot_bones = [left, right]
				return
		stack.append_array(node.get_children())


## One footfall: surface-matched sample, one of three variants so no two
## steps are identical, left/right a hair apart in pitch, quieter at a
## shuffle than a stride.
func _play_footstep(foot: int, speed: float) -> void:
	footsteps_played += 1
	var surface := _surface_at(global_position)
	var variant := randi_range(0, 2)
	var stride := clampf(speed / max_speed, 0.0, 1.0)
	var volume := -26.0 + 7.0 * stride
	var pitch := 0.97 if foot == 0 else 1.03
	# Indoors the steps ring down the halls; outside they play dry.
	var outdoors := surface != "wood"
	AudioSynthesizer.play_at("step_%s_%d" % [surface, variant], global_position, volume, pitch, outdoors)


func _surface_at(p: Vector3) -> String:
	return surface_at(p)


## What stands at `p`, from the estate's fixed layout: the mansion floors
## are hardwood; the porch slab, cobble walkway, garage slab and its
## spur are stone; the driveway is gravel; the rest of the grounds are
## lawn. Static so items can ask what they landed on.
static func surface_at(p: Vector3) -> String:
	if absf(p.x) <= 15.2 and absf(p.z) <= 15.2:
		return "wood"
	if absf(p.x) <= 6.0 and p.z > 14.8 and p.z < 25.4:
		return "stone"      # front porch slab
	if absf(p.x) <= 1.3 and p.z >= 25.4 and p.z <= 33.2:
		return "stone"      # cobble walkway to the gate
	if p.x >= 6.75 and p.x <= 12.25 and p.z >= 24.25 and p.z <= 32.75:
		return "gravel"     # roadster pad
	if absf(p.x) <= 2.3 and p.z >= 33.2 and p.z <= 51.2:
		return "gravel"     # driveway out to the lane
	if p.x >= 18.8 and p.x <= 26.2 and p.z >= 17.3 and p.z <= 23.7:
		return "stone"      # garage slab
	if p.x >= 15.1 and p.x <= 19.5 and p.z >= 19.3 and p.z <= 21.7:
		return "stone"      # gravel spur is laid cobble
	if p.x >= 15.6 and p.x <= 26.6 and p.z >= 17.5 and p.z <= 23.5:
		return "stone"      # patio pad and side-door approach
	return "grass"


## Skeletal animations when the asset has them; otherwise a procedural
## gait: stride-synced bobbing, momentum lean, and breathing sway at rest.
func _animate_visual(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length() if is_local_player() else net_speed
	var stride := clampf(speed / max_speed, 0.0, 1.0)
	# Hauling a mirror: shoulders forward, weight into the load. With a
	# real push clip registered it drives the legs; otherwise the walk
	# cycle plays slow and heavy under the lean.
	var pushing := _pushing_mirror != null
	# A real push clip already leans; only the procedural fallback needs it.
	var lean := (0.24 + 0.1 * stride) if (pushing and not (_anim_player and _anim_player.has_animation("moves/push"))) else 0.0
	var lean_weight := 1.0 - exp(-8.0 * delta)

	if _anim_player and not _walk_anim.is_empty():
		_visual.rotation.x = lerpf(_visual.rotation.x, lean, lean_weight)
		# An emote owns the body until it is cancelled or the player moves.
		if not _emote_anim.is_empty():
			if speed > 0.3:
				stop_emote()
			else:
				if _anim_player.current_animation != _emote_anim or not _anim_player.is_playing():
					_anim_player.play(_emote_anim, 0.25)
					_anim_player.speed_scale = 1.0
				return
		# Hands on a mirror (pivoting, or hauling while standing still) or
		# under a carried load holds the reach pose. Walking releases it
		# into the gait — slow and heavy under the battery.
		var carrying := carried_item != null
		if _adjusting_mirror != null or ((pushing or carrying) and speed <= 0.1):
			_set_hold_pose(true)
			return
		_set_hold_pose(false)
		# One-shot action (pick up, open door) plays out unless the player
		# starts moving, which cancels straight back into the walk.
		if not _action_anim.is_empty():
			var action_running := _anim_player.is_playing() and _anim_player.current_animation == _action_anim
			if action_running and speed <= 0.1:
				return
			_action_anim = ""
		if speed > 0.1:
			_visual.position = _visual_base_pos
			var gait := _walk_anim
			if pushing and _anim_player.has_animation("moves/push"):
				gait = "moves/push"
			elif carrying:
				# Load in both hands: the carry walk, or its turning
				# variant while the body is swinging round.
				var turning := absf(wrapf(rotation.y - _last_facing, -PI, PI)) > 0.05
				if turning and _anim_player.has_animation("moves/carry_turn"):
					gait = "moves/carry_turn"
				elif _anim_player.has_animation("moves/carry"):
					gait = "moves/carry"
			if _anim_player.current_animation != gait or not _anim_player.is_playing():
				_anim_player.play(gait, 0.25)
			# Foot cadence follows actual movement speed (heavy when hauling
			# or under the battery).
			_anim_player.speed_scale = (0.45 + stride * 0.5) if (pushing or carrying) else (0.5 + stride * 0.9)
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
	_visual.rotation.x = lerpf(_visual.rotation.x, 0.1 * stride + lean, weight)
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
		# CSG walls expose .material; doors register theirs as metadata.
		var mat: StandardMaterial3D = wall.get("material")
		if mat == null and wall.has_meta("fade_material"):
			mat = wall.get_meta("fade_material")
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
	# Cast from the PLAYER toward the camera: the walls hiding the
	# character are the ones nearest the player, so they are found first
	# and can never be starved out of the hit budget by props and clutter
	# closer to the camera.
	for side_offset: Vector3 in [Vector3.ZERO, cam_right * 0.9, cam_right * -0.9]:
		var from := global_position + Vector3.UP + side_offset
		var exclude: Array[RID] = [get_rid()]
		for i in 8:
			var query := PhysicsRayQueryParameters3D.create(from, cam_pos + side_offset)
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
		var size_value: Variant = wall.get("size")
		if size_value == null:
			size_value = wall.get_meta("fade_size", Vector3.ZERO)
		var half: Vector3 = size_value * 0.5
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
## "[G] Drop" hint rides along (or floats over the held item if nothing
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
	# Mode prompts are live state, not hints — they always show. The
	# discovery prompts over idle interactables are what the Hints
	# setting turns off for a clean screen.
	if _adjusting_mirror and is_instance_valid(_adjusting_mirror):
		text = "PIVOT — [Mouse] Swivel   [E] Let Go"
		anchor = _adjusting_mirror
		height = _adjusting_mirror.prompt_height
	elif _pushing_mirror and is_instance_valid(_pushing_mirror):
		text = "HAULING — [WASD] Move  [Mouse] Swivel  [E] Let Go"
		anchor = _pushing_mirror
		height = _pushing_mirror.prompt_height
	elif not GameSettings.hints_enabled:
		pass
	elif target is Interactable:
		text = target.get_prompt(self)
		anchor = target
		height = target.prompt_height
	elif target:
		text = "[E] Use"
		anchor = target
	# No floating drop hint — the HUD's pack slots already show what's
	# carried, and [G] quietly drops the newest item. Silent
	# interactables (empty prompt, e.g. mirrors) show nothing at all.
	# Prompts name the player's own keys, not the defaults.
	if not text.is_empty():
		text = GameSettings.fmt(text)
	if anchor and not text.is_empty():
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

	# Any movement or interaction cancels a running emote.
	if not _emote_anim.is_empty() and (event.is_action_pressed("interact") \
			or event.is_action_pressed("ui_cancel") or event.is_action_pressed("drop")):
		stop_emote()

	# [Q]: swing the isometric camera a quarter turn — the scene rotates
	# 90 degrees clockwise on screen. Movement input is camera-relative
	# (see _physics_process), so the controls follow automatically.
	if event.is_action_pressed("rotate_camera"):
		# Allow at most ONE queued quarter-turn beyond the swing already
		# playing, so mashed presses can't bank extra spins.
		if _yaw_target - _yaw_current > PI * 0.75:
			get_viewport().set_input_as_handled()
			return
		_yaw_target += PI / 2.0
		if _rotate_tween and _rotate_tween.is_running():
			_rotate_tween.kill()
		_rotate_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_rotate_tween.tween_method(_set_camera_yaw, _yaw_current, _yaw_target, 0.35)
		AudioSynthesizer.play_ui("whoosh", -16.0)
		get_viewport().set_input_as_handled()
		return

	# Hauling a mirror: the mouse swivels it as it travels; [E] or [ESC]
	# lets go; nothing else interacts.
	if _pushing_mirror:
		if event is InputEventMouseMotion and is_instance_valid(_pushing_mirror):
			_pushing_mirror.adjust_by_mouse(event.relative.x)
		elif event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
			_finish_push()
			get_viewport().set_input_as_handled()
		return

	# [E] always interacts (valves, doors, mirrors work while carrying);
	# [G] is the dedicated drop key, so tools are never dropped by accident.
	if event.is_action_pressed("interact"):
		var target := get_nearest_interactable()
		if target is PrismTable:
			var mirror := target as PrismTable
			if carried_item != null:
				# Both hands are under the battery.
				AudioSynthesizer.play_at("tick", global_position, -12.0, 0.6)
			elif mirror.wants_prism_from(self):
				# Empty socket + prism in the pack: seat it (replicated).
				mirror.request_seat_prism(self)
				play_action("moves/pick_up")
			elif mirror.pushable and not mirror.seated:
				# Unseated pushable: take hold and haul it to its ring (no
				# grip step: the mirror rides the grip offset every frame,
				# so moving the player would drag it along).
				start_pushing(mirror)
			else:
				# Enter mirror rotation mode: step behind the frame, take
				# hold, and the mirror follows the mouse.
				_adjusting_mirror = mirror
				_adjusting_mirror.start_rotating()
				_step_to_grip(mirror, 0.85)
		elif target:
			request_interact(target)
	elif event.is_action_pressed("drop"):
		# A carried load always goes down first — it is what's in hand.
		var drop_index := CARRY_SLOT if carried_item != null \
			else (selected_slot if selected_slot >= 0 and selected_slot < inventory.size() else inventory.size() - 1)
		request_drop(drop_index)
		selected_slot = -1
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_1, KEY_2, KEY_3, KEY_KP_1, KEY_KP_2, KEY_KP_3]:
		# 1/2/3 select a pack slot (toggle off when re-pressed).
		var slot := 0
		match event.keycode:
			KEY_1, KEY_KP_1: slot = 0
			KEY_2, KEY_KP_2: slot = 1
			KEY_3, KEY_KP_3: slot = 2
		if slot < inventory.size():
			selected_slot = -1 if selected_slot == slot else slot
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ping"):
		var at := global_position - global_transform.basis.z * 1.5
		if NetworkSession.multiplayer_active:
			_net_ping.rpc(at)
		else:
			_spawn_ping(at)


# --- Mirror hauling ------------------------------------------------------


## Take hold of a pushable mirror. The grip offset is wherever the mirror
## stands relative to the player right now, clamped so the two bodies
## never overlap; from here on it rides that offset in WORLD space.
func start_pushing(mirror: PrismTable) -> bool:
	if _pushing_mirror != null or carried_item != null or not mirror.begin_push(self):
		return false
	_pushing_mirror = mirror
	var offset := mirror.global_position - global_position
	offset.y = 0.0
	if offset.length() < 0.05:
		offset = -global_transform.basis.z
	_push_offset = offset.normalized() * clampf(offset.length(), 0.95, 1.5)
	_push_sync_accum = 0.0
	# Floorboard drag: silent until the mirror actually moves.
	_drag_loop = AudioSynthesizer.create_loop("drag_wood", mirror, -60.0)
	return true


var _drag_loop: AudioStreamPlayer3D


func _finish_push() -> void:
	if _pushing_mirror == null:
		return
	if is_instance_valid(_drag_loop):
		_drag_loop.queue_free()
	_drag_loop = null
	if is_instance_valid(_pushing_mirror):
		var mirror := _pushing_mirror
		mirror.end_push()
		# Let go: the swivel settles onto its detent, peers get the final
		# angle and resting spot.
		mirror.end_adjust()
		if NetworkSession.multiplayer_active:
			mirror._net_finish_angle.rpc(mirror.rotation.y)
			if not mirror.seated:
				mirror._net_set_position.rpc(mirror.global_position)
	_pushing_mirror = null


## Move the hauled mirror onto its grip offset and stream it to peers.
## The mirror seats itself when it comes within its snap radius.
func _update_pushed_mirror(delta: float) -> void:
	if not is_instance_valid(_pushing_mirror):
		_pushing_mirror = null
		return
	var target := global_position + _push_offset
	var mirror := _pushing_mirror
	mirror.set_hauled_position(target)
	# The drag scrape swells with speed and dies when the mirror rests.
	if is_instance_valid(_drag_loop):
		var speed := Vector2(velocity.x, velocity.z).length()
		var goal := -60.0 if speed < 0.2 else lerpf(-26.0, -12.0, clampf(speed / (max_speed * push_speed_factor), 0.0, 1.0))
		_drag_loop.volume_db = lerpf(_drag_loop.volume_db, goal, 1.0 - exp(-12.0 * delta))
	if mirror.seated:
		# set_hauled_position snapped it home; the mirror already released us.
		if NetworkSession.multiplayer_active:
			mirror._net_seat.rpc()
		if is_instance_valid(_drag_loop):
			_drag_loop.queue_free()
		_drag_loop = null
		_pushing_mirror = null
		return
	if NetworkSession.multiplayer_active:
		_push_sync_accum += delta
		if _push_sync_accum >= 0.1:
			_push_sync_accum = 0.0
			mirror._net_set_position.rpc(mirror.global_position)
			mirror._net_set_angle.rpc(mirror.rotation.y)


## True when the hauled mirror can occupy (its position + step) without
## overlapping walls, furniture, doors, or other mirrors.
func _push_destination_clear(step: Vector3) -> bool:
	if not is_instance_valid(_pushing_mirror):
		return true
	var space := get_world_3d().direct_space_state
	var shape := CylinderShape3D.new()
	shape.radius = 0.42
	shape.height = 1.7
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY,
		global_position + _push_offset + step + Vector3(0, 0.9, 0))
	params.exclude = [get_rid(), _pushing_mirror.get_rid()]
	params.collide_with_areas = false
	return space.intersect_shape(params, 1).is_empty()


## Tween target for the [Q] swing: drives the pivot from the unwrapped
## shadow yaw (the node may wrap the value internally; we never read it).
func _set_camera_yaw(yaw: float) -> void:
	_yaw_current = yaw
	camera_pivot.rotation.y = yaw


## Slide the character to a grip spot `dist` behind the mirror (on the
## side the player approached from) facing it, so the model visibly
## takes hold of the frame's back. Physics still resolves overlaps.
func _step_to_grip(mirror: PrismTable, dist: float) -> void:
	var away := global_position - mirror.global_position
	away.y = 0.0
	if away.length() < 0.05:
		away = -global_transform.basis.z
	away = away.normalized()
	var grip := mirror.global_position + away * dist
	grip.y = global_position.y
	if _grip_tween and _grip_tween.is_running():
		_grip_tween.kill()
	_grip_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_grip_tween.tween_property(self, "global_position", grip, 0.22)
	# Face the mirror (-Z is the body's forward).
	rotation.y = atan2(away.x, away.z)
	velocity = Vector3.ZERO


var _grip_tween: Tween
var _holding_pose := false
## Frozen frame of the door-reach clip that reads as two hands on a frame.
const HOLD_POSE_TIME := 0.55


## Hold the "hands on the frame" pose (or release it back to locomotion).
func _set_hold_pose(on: bool) -> void:
	if _anim_player == null:
		return
	if on and not _holding_pose:
		_holding_pose = true
		if _anim_player.has_animation("moves/open_door"):
			_anim_player.play("moves/open_door", 0.15)
			_anim_player.seek(HOLD_POSE_TIME, true)
			_anim_player.pause()
	elif not on and _holding_pose:
		_holding_pose = false
		if not _idle_anim.is_empty():
			_anim_player.play(_idle_anim, 0.2)
		_anim_player.speed_scale = 1.0


func _finish_mirror_adjust() -> void:
	if _adjusting_mirror == null:
		return
	_set_hold_pose(false)
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
	if item.carried:
		# Two-hand load: one at a time, never into the pack.
		if carried_item != null or item == carried_item:
			return
		carried_item = item
		item.carry(self)
		play_action("moves/lift")
		return
	if inventory.has(item) or inventory.size() >= INVENTORY_SIZE:
		return
	inventory.append(item)
	item.stash(self)
	# Finding a loose prism is the one puzzle step with no fixture to
	# read: write it down so [Tab] remembers why you are carrying glass.
	if item.is_in_group("prisms"):
		PlayerNotes.add("A laser prism — one of the beam tables is missing its glass.")
	# Crouch for something off the floor, reach for anything higher.
	var low := item.global_position.y - global_position.y < 0.5
	play_action("moves/pick_up_object" if low else "moves/pick_up")


## [G]: set down the carried load if any, else drop the newest pack item.
func drop_held() -> void:
	if carried_item != null:
		drop_at(CARRY_SLOT)
	else:
		drop_at(inventory.size() - 1)


## Drop the pack item at `index` (from the HUD's selected slot or a
## drag out of the bar), or the carried load for CARRY_SLOT.
func drop_at(index: int) -> void:
	if index == CARRY_SLOT:
		if carried_item == null:
			return
		var load := carried_item
		carried_item = null
		load.release()
		return
	if index < 0 or index >= inventory.size():
		return
	var item: Grabbable = inventory[index]
	inventory.remove_at(index)
	item.release()
	if selected_slot == index:
		selected_slot = -1


func request_drop(index: int) -> void:
	if NetworkSession.multiplayer_active:
		_net_drop_at.rpc(index)
	else:
		drop_at(index)


@rpc("any_peer", "call_local", "reliable")
func _net_drop_at(index: int) -> void:
	if NetworkSession.multiplayer_active:
		var sender := multiplayer.get_remote_sender_id()
		if sender != 0 and sender != get_multiplayer_authority():
			return
	drop_at(index)


## Reorder pack slots (HUD drag). Replicated so slot indices stay in
## sync across peers — index-based drops depend on it.
func request_swap(a: int, b: int) -> void:
	if NetworkSession.multiplayer_active:
		_net_swap.rpc(a, b)
	else:
		swap_slots(a, b)


@rpc("any_peer", "call_local", "reliable")
func _net_swap(a: int, b: int) -> void:
	swap_slots(a, b)


func swap_slots(a: int, b: int) -> void:
	if a == b or a < 0 or b < 0 or a >= inventory.size() or b >= inventory.size():
		return
	var tmp := inventory[a]
	inventory[a] = inventory[b]
	inventory[b] = tmp


func inventory_full() -> bool:
	return inventory.size() >= INVENTORY_SIZE


## First held item belonging to `group` (the two-hand load counts), or null.
func inventory_find(group: String) -> Grabbable:
	if carried_item != null and is_instance_valid(carried_item) and carried_item.is_in_group(group):
		return carried_item
	for item in inventory:
		if is_instance_valid(item) and item.is_in_group(group):
			return item
	return null


## Forget a consumed/placed item (does not free or move the node).
func inventory_remove(item: Grabbable) -> void:
	if item == carried_item:
		carried_item = null
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
		# Walls hard-block interaction: no using the fuse panel (or
		# anything else) through solid geometry. Doors are exempt — they
		# sit flush in wall openings, where edge-grazing rays would
		# falsely block them.
		if not (node is Door) and not _has_line_of_sight(node):
			continue
		var dist: float = global_position.distance_squared_to(node.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = node
	return nearest


## True when nothing solid stands between the player's chest and the
## target (the target itself, its children, or its parent mechanism
## don't count as blockers).
func _has_line_of_sight(target: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.0, 0)
	var to := target.global_position + Vector3(0, 0.35, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider: Object = hit["collider"]
	if collider == target:
		return true
	if collider is Node:
		return target.is_ancestor_of(collider) or (collider as Node).is_ancestor_of(target)
	return false
