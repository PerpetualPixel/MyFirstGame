class_name RotatingMirror
extends Interactable

## Slim brass standing mirror with free-angle mouse-swivel. Two kinds:
##  - FIXED: stands on its beam-route spot from the start; [E] enters
##    rotation mode (mouse swivels with ratchet clicks every 7.5°, [E] or
##    [ESC] exits and snaps to the nearest 15° detent). Silent — no
##    floating text — players discover the swivel.
##  - PUSHABLE: spawns somewhere along its room's walls with a glowing
##    floor ring marking where it belongs. [E] grabs it: WASD then hauls
##    the mirror around at a fixed grip offset (push or drag) while the
##    mouse swivels it; the player owns both. Once it comes within
##    `snap_radius` of the ring it seats itself with a clunk and becomes
##    a normal fixed mirror.
##  - FREE (the decoy): pushable with no ring — haul it anywhere, swivel
##    it while holding, let go wherever. It never seats. Useless as ever.
## Beams reflect off the live collision normal, so any angle works.

signal seated_changed

## Degrees of swivel per 100 px of mouse travel is sensitivity x 1.0
## (15.0 -> 0.15 deg/px: a ~300 px flick turns 45 degrees).
@export var mouse_sensitivity: float = 15.0
@export var snap_degrees: float = 15.0
## How close (m) the mirror must be hauled to its ring before it seats.
@export var snap_radius: float = 0.6

## Set by the generator via make_pushable()/make_free(); false = fixed.
var pushable := false
## False for a FREE mirror: nowhere to seat, no ring.
var has_target := false
## Where a pushable mirror belongs (world space, floor level).
var target_position := Vector3.ZERO
## True once a pushable mirror has been hauled onto its ring (fixed
## mirrors are born seated). Only seated mirrors can be swiveled.
var seated := true
## The player currently hauling this mirror (null when free).
var pusher: Node3D = null

@onready var _beam: LaserBeam = $Beam

var _powered_frame: int = -100
var _tween: Tween
var _seat_tween: Tween
var _ratchet_accum := 0.0
var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D
var _marker_time := 0.0


func _ready() -> void:
	_beam.add_exception(self)
	if pushable and has_target and not seated:
		_build_marker()


## Turn this mirror into a haul-to-target mirror. Call before add_child
## (co-op peers build identical layouts, so no netcode is needed here).
func make_pushable(target: Vector3) -> void:
	pushable = true
	has_target = true
	seated = false
	target_position = target


## Turn this mirror into a free-roaming one: haulable anywhere, no ring,
## never seats. Call before add_child.
func make_free() -> void:
	pushable = true
	has_target = false
	seated = false


## Glowing brass ring on the floor where the mirror belongs. top_level so
## it stays put while the mirror itself is hauled around.
func _build_marker() -> void:
	_marker = MeshInstance3D.new()
	_marker.top_level = true
	var torus := TorusMesh.new()
	torus.inner_radius = 0.34
	torus.outer_radius = 0.46
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.albedo_color = Color(1.0, 0.72, 0.25)
	_marker_mat.emission_enabled = true
	_marker_mat.emission = Color(1.0, 0.72, 0.25)
	_marker_mat.emission_energy_multiplier = 1.4
	torus.material = _marker_mat
	_marker.mesh = torus
	_marker.scale = Vector3(1, 0.25, 1)
	add_child(_marker)
	_marker.global_position = target_position + Vector3(0, 0.05, 0)


func can_interact(_by: Node3D) -> bool:
	# A mirror someone else is hauling can't be grabbed or swiveled.
	return pusher == null


func get_prompt(by: Node3D = null) -> String:
	if by != null and by.get("carried_item") != null:
		return "Hands full — set the battery down first"
	if pushable and not seated:
		return "[E] Push Mirror"
	# Silent: no floating text on seated mirrors — players discover the swivel.
	return ""


# --- Hauling -------------------------------------------------------------


## The player takes hold. Returns false if the mirror can't be hauled.
func begin_push(by: Node3D) -> bool:
	if not pushable or seated or pusher != null:
		return false
	pusher = by
	AudioSynthesizer.play_at("tick", global_position, -10.0, 0.7)
	if NetworkSession.multiplayer_active:
		_net_hold.rpc(by.get_path())
	return true


func end_push() -> void:
	pusher = null
	if NetworkSession.multiplayer_active:
		_net_release.rpc()


## Peers mark the mirror held so their player can't grab it too.
@rpc("any_peer", "call_remote", "reliable")
func _net_hold(by_path: NodePath) -> void:
	pusher = get_node_or_null(by_path)


@rpc("any_peer", "call_remote", "reliable")
func _net_release() -> void:
	pusher = null


## Owner-side placement while hauling: the player computes the new spot
## (grip offset + wall clearance) and streams it; every peer applies it
## through here so the snap check runs identically everywhere.
func set_hauled_position(pos: Vector3) -> void:
	global_position = Vector3(pos.x, global_position.y, pos.z)
	if has_target and not seated \
			and Vector2(pos.x - target_position.x, pos.z - target_position.z).length() <= snap_radius:
		_seat()


@rpc("any_peer", "call_remote", "unreliable")
func _net_set_position(pos: Vector3) -> void:
	if seated:
		return
	global_position = pos


@rpc("any_peer", "call_remote", "reliable")
func _net_seat() -> void:
	_seat()


## Slide the last few centimetres onto the ring and lock the position.
func _seat() -> void:
	if seated or not has_target:
		return
	seated = true
	pusher = null
	if _seat_tween and _seat_tween.is_running():
		_seat_tween.kill()
	_seat_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_seat_tween.tween_property(self, "global_position", target_position, 0.18)
	# Whatever angle it was hauled in at settles onto a detent.
	end_adjust()
	if _marker_mat:
		_marker_mat.albedo_color = Color(0.35, 1.0, 1.0)
		_marker_mat.emission = Color(0.35, 1.0, 1.0)
	AudioSynthesizer.play_at("plug", global_position, -8.0, 1.2)
	Player.shake(0.15, global_position)
	Door._dust_puff(target_position, 6)
	seated_changed.emit()


func _process(delta: float) -> void:
	if _pivot_ring != null and _pivot_ring.visible:
		# Pivot ring pulses gently while held.
		_pivot_time += delta
		_pivot_ring.scale = Vector3.ONE * (1.0 + 0.04 * sin(_pivot_time * 6.0))
		_pivot_ring.scale.y = 0.3
	if _marker == null or seated:
		return
	# The ring breathes until its mirror arrives.
	_marker_time += delta
	_marker_mat.emission_energy_multiplier = 1.0 + 0.7 * (0.5 + 0.5 * sin(_marker_time * 3.0))


# --- Swivel --------------------------------------------------------------

var _pivot_ring: MeshInstance3D
var _pivot_time := 0.0


## Start rotation mode: called by player when E is pressed on this mirror.
## Lights the pivot ring so it is unmistakable that the mirror, not the
## player, now follows the mouse.
func start_rotating() -> void:
	if _tween and _tween.is_running():
		_tween.kill()
	set_pivot_highlight(true)
	AudioSynthesizer.play_at("tick", global_position, -12.0, 1.3)


## Cyan ring at the base with a rotating tick: visible only while a
## player holds this mirror in pivot mode.
func set_pivot_highlight(on: bool) -> void:
	if on and _pivot_ring == null:
		_pivot_ring = MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.42
		torus.outer_radius = 0.52
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.35, 1.0, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.35, 1.0, 1.0)
		mat.emission_energy_multiplier = 1.8
		torus.material = mat
		_pivot_ring.mesh = torus
		_pivot_ring.scale = Vector3(1, 0.3, 1)
		_pivot_ring.position = Vector3(0, 0.06, 0)
		add_child(_pivot_ring)
		# A tick on the ring shows the swivel direction at a glance.
		var tick := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.06, 0.12, 0.2)
		box.material = mat
		tick.mesh = box
		tick.position = Vector3(0, 0.1, 0.5)
		add_child(tick)
		tick.name = "PivotTick"
	if _pivot_ring != null:
		_pivot_ring.visible = on
		var tick := get_node_or_null("PivotTick")
		if tick:
			tick.visible = on


## Adjust mirror angle by mouse delta in pixels (typically delta.x from motion event).
func adjust_by_mouse(delta_pixels: float) -> void:
	if _tween and _tween.is_running():
		_tween.kill()
	var step := deg_to_rad(-delta_pixels * mouse_sensitivity * 0.01)
	rotation.y += step
	_ratchet_accum += absf(step)
	if _ratchet_accum >= deg_to_rad(7.5):
		_ratchet_accum = 0.0
		AudioSynthesizer.play_at("ratchet", global_position, -10.0)


## Live angle stream from the adjusting peer (10 Hz while swiveling).
@rpc("any_peer", "call_remote", "unreliable")
func _net_set_angle(angle: float) -> void:
	if _tween and _tween.is_running():
		_tween.kill()
	rotation.y = angle


## Final angle on release: set exactly, then snap to the same detent.
@rpc("any_peer", "call_remote", "reliable")
func _net_finish_angle(angle: float) -> void:
	rotation.y = angle
	end_adjust()


## Settle onto the nearest detent when the hold is released.
func end_adjust() -> void:
	set_pivot_highlight(false)
	var detent := roundf(rad_to_deg(rotation.y) / snap_degrees) * snap_degrees
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "rotation:y", deg_to_rad(detent), 0.2)


# --- Beam ----------------------------------------------------------------


## Called by LaserBeam.dispatch() each physics frame a beam lands on us.
func reflect_beam(incoming: Vector3, point: Vector3, normal: Vector3, bounces_left: int) -> void:
	_powered_frame = Engine.get_physics_frames()
	if bounces_left <= 0:
		_beam.shut_off()
		return
	var out := incoming.bounce(normal).normalized()
	var hit := _beam.fire(point, out)
	LaserBeam.dispatch(hit, out, bounces_left - 1)


func _physics_process(_delta: float) -> void:
	# Power decays when no beam has refreshed it for over a frame.
	if Engine.get_physics_frames() - _powered_frame > 1:
		_beam.shut_off()
