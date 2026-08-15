class_name ClockworkMechanism
extends Interactable

## Ornate grandfather clock — mahogany case, gold columns, scrolled
## crown — with three gear sockets behind the waist glass. [E] opens the
## fullscreen ClockPanel overlay (first-person view of the gear train):
## click a carried gear, then a socket, to seat it; click a seated gear
## to take it back. Seat the correct gear (by engraved tooth count) in
## every socket and the pendulum starts, the clock ticks and chimes, and
## the rosette compartment slides open to release whatever the generator
## stashed inside (the Brass Wrench). Wrong gears simply fail to mesh:
## the clock stays dead until the arrangement matches the engravings.

signal gear_inserted(placed: int)
signal clock_completed

const PANEL_SCENE := preload("res://scenes/Puzzles/ClockPanel.tscn")

var is_running := false
var minigame: ClockPanel

var _stashed: Node3D
var _time := 0.0
var _tick_accum := 0.0

@onready var _sockets: Array = [$SocketA, $SocketB, $SocketC]
@onready var _pendulum: Node3D = $PendulumPivot
@onready var _compartment: MeshInstance3D = $CompartmentDoor


func _ready() -> void:
	add_to_group("clockworks")
	for socket in _sockets:
		socket.gear_changed.connect(_on_gear_changed)
	minigame = PANEL_SCENE.instantiate()
	add_child(minigame)
	minigame.setup(self)


## RE-style: [E] always inspects; gears are seated and removed from
## inside the overlay. It only opens on the interacting machine.
func interact(by: Node3D) -> void:
	if by == null or not by.has_method("is_local_player") or by.is_local_player():
		minigame.open()
	super.interact(by)


## Park an item (frozen, collision off) inside the lower cabinet until the
## clock runs. Call before the item is added anywhere else. Uses set() for
## the rigid-body properties because Grabbable's declared base class is
## CollisionObject3D (the node itself is a RigidBody3D at runtime).
func stash_item(item: Node3D) -> void:
	_stashed = item
	item.set("freeze", true)
	item.set("collision_layer", 0)
	item.set("collision_mask", 0)
	add_child(item)
	item.position = Vector3(0, 0.5, 0.12)


func _on_gear_changed() -> void:
	var placed := 0
	var correct := 0
	for socket in _sockets:
		if socket.gear != null:
			placed += 1
			if socket.is_correct():
				correct += 1
	gear_inserted.emit(placed)
	if correct == _sockets.size() and not is_running:
		_start_running()


func _start_running() -> void:
	is_running = true
	for socket in _sockets:
		socket.lock()
	AudioSynthesizer.play_at("chime", global_position, -2.0)
	var tween := create_tween()
	tween.tween_property(_compartment, "position:y", _compartment.position.y - 0.45, 0.8).set_delay(0.6)
	tween.tween_callback(_release_stash)
	clock_completed.emit()


func _release_stash() -> void:
	if _stashed == null:
		return
	var item := _stashed
	_stashed = null
	item.reparent(get_parent())
	# Out the FRONT of the case (local +Z: face, glass, rosette door), onto
	# the floor before the clock. The case stands against a wall, so the
	# rear is solid masonry.
	item.global_position = global_position + global_transform.basis.z * 0.9 + Vector3(0, 0.5, 0)
	item.set("freeze", false)
	item.set("collision_layer", 1)
	item.set("collision_mask", 1)


func _process(delta: float) -> void:
	if not is_running:
		return
	_time += delta
	_pendulum.rotation.z = sin(_time * 2.4) * 0.32
	for socket in _sockets:
		if socket.gear:
			socket.gear.rotation.z += delta * (8.0 / maxf(1.0, float(socket.required_teeth)))
	_tick_accum += delta
	if _tick_accum >= 0.8:
		_tick_accum = 0.0
		AudioSynthesizer.play_at("tick", global_position, -10.0)
