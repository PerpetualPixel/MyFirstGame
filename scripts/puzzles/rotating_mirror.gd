class_name RotatingMirror
extends Interactable

## Brass mirror on a pedestal with free-angle mouse-swivel. Press [E] to
## enter rotation mode; move mouse left/right to swivel smoothly with
## ratchet clicks every 7.5°; press [E] or [ESC] to exit and snap to
## nearest 15-degree detent. No on-screen text — the ratchet clicks and
## the mirror itself are the feedback. Beams reflect off the live
## collision normal, so any angle works.

## Degrees of swivel per 100 px of mouse travel is sensitivity x 1.0
## (15.0 -> 0.15 deg/px: a ~300 px flick turns 45 degrees).
@export var mouse_sensitivity: float = 15.0
@export var snap_degrees: float = 15.0

@onready var _beam: LaserBeam = $Beam

var _powered_frame: int = -100
var _tween: Tween
var _ratchet_accum := 0.0


func _ready() -> void:
	_beam.add_exception(self)


## Silent: no floating text on mirrors — players discover the swivel.
func get_prompt(_by: Node3D = null) -> String:
	return ""


## Start rotation mode: called by player when E is pressed on this mirror.
func start_rotating() -> void:
	if _tween and _tween.is_running():
		_tween.kill()


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
	var detent := roundf(rad_to_deg(rotation.y) / snap_degrees) * snap_degrees
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "rotation:y", deg_to_rad(detent), 0.2)


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
