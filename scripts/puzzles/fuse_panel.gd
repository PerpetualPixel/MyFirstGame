class_name FusePanel
extends CanvasLayer

## Fullscreen fuse-panel overlay over the painted breaker art. Every house
## circuit has its cartridge fuse except FRONT DOOR and LIVING ROOM — those
## sockets sit empty. The player finds the estate's two spare ceramic fuses
## and installs them by interacting with the breaker box while holding one
## (BreakerBox owns that world-side logic and calls mark_installed here).
## This overlay is the readable "what's missing" view: empty sockets pulse,
## installed ones show a seated cartridge. [ESC] or the close button exits.

signal closed

const BACKDROP_PATH := "res://assets/puzzles/Puzzle1Revamped.jpg"

## Board-space (1056x576) centers of the two empty sockets in the art.
const SOCKET_POS := [Vector2(453, 284), Vector2(453, 320)]
const SOCKET_NAMES := ["FRONT DOOR", "LIVING ROOM"]

var is_open := false

var _socket_markers: Array[Control] = []
var _fuse_sprites: Array[Control] = []
var _pulse_time := 0.0

@onready var _board: Control = $Overlay/Board
@onready var _backdrop: TextureRect = $Overlay/Board/Backdrop
@onready var _hotspots: Control = $Overlay/Board/Hotspots
@onready var _hint: Label = $Overlay/Hint


func _ready() -> void:
	visible = false
	if ResourceLoader.exists(BACKDROP_PATH):
		_backdrop.texture = load(BACKDROP_PATH)
	$Overlay/Board/CloseButton.pressed.connect(close)
	_build_sockets()


func _process(delta: float) -> void:
	if not is_open:
		return
	# Empty sockets breathe gently so the missing spots read at a glance.
	_pulse_time += delta
	var pulse := 0.45 + 0.3 * (0.5 + 0.5 * sin(_pulse_time * 3.0))
	for i in _socket_markers.size():
		if not _fuse_sprites[i].visible:
			_socket_markers[i].modulate.a = pulse


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func open() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	add_to_group("modal_ui")
	# Solo pauses the whole tree; in co-op the world must keep running for
	# the partner, so only lock this machine's player input.
	if NetworkSession.multiplayer_active:
		_set_local_lock(true)
	else:
		get_tree().paused = true


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	remove_from_group("modal_ui")
	if NetworkSession.multiplayer_active:
		_set_local_lock(false)
	else:
		get_tree().paused = false
	closed.emit()


func _set_local_lock(locked: bool) -> void:
	for player in get_tree().get_nodes_in_group("players"):
		if player.is_local_player():
			player.ui_locked = locked


func _on_socket_clicked() -> void:
	var local := _local_player()
	if local == null:
		return
	var breaker := get_parent() as BreakerBox
	if breaker == null or breaker.is_powered:
		return
	if local.inventory_find("fuses") == null:
		_hint.text = "No spare fuse in your pack — search the toy crates and the garage.  [ESC] steps away."
		AudioSynthesizer.play_ui("tick", -14.0, 0.8)
		return
	breaker.request_install(local)


func _local_player() -> Node:
	for player in get_tree().get_nodes_in_group("players"):
		if player.is_local_player():
			return player
	return null


## Called by BreakerBox as fuses are installed (count = fuses so far).
func mark_installed(count: int) -> void:
	for i in mini(count, _fuse_sprites.size()):
		_fuse_sprites[i].visible = true
		_socket_markers[i].modulate.a = 0.0
	_update_hint(count)


func _update_hint(count: int) -> void:
	match count:
		0:
			_hint.text = "Two fuses missing — FRONT DOOR and LIVING ROOM circuits are dead. Search the estate.  [ESC] steps away."
		1:
			_hint.text = "One socket still empty. Bring the second ceramic fuse.  [ESC] steps away."
		_:
			_hint.text = "All circuits seated — power restored!"


func _build_sockets() -> void:
	for i in SOCKET_POS.size():
		# Pulsing clickable ring marking an empty socket: click with a
		# fuse in the pack to seat it (RE-style select-and-use).
		var marker := Button.new()
		marker.focus_mode = Control.FOCUS_NONE
		var ring := StyleBoxFlat.new()
		ring.bg_color = Color(1.0, 0.75, 0.25, 0.12)
		ring.border_color = Color(1.0, 0.75, 0.25, 0.9)
		ring.set_border_width_all(2)
		ring.set_corner_radius_all(6)
		var ring_hover := ring.duplicate() as StyleBoxFlat
		ring_hover.bg_color = Color(1.0, 0.85, 0.4, 0.3)
		marker.add_theme_stylebox_override("normal", ring)
		marker.add_theme_stylebox_override("hover", ring_hover)
		marker.add_theme_stylebox_override("pressed", ring_hover)
		marker.add_theme_stylebox_override("focus", ring)
		marker.size = Vector2(108, 30)
		marker.position = SOCKET_POS[i] - marker.size / 2.0
		marker.pressed.connect(_on_socket_clicked)
		_hotspots.add_child(marker)
		_socket_markers.append(marker)

		# Seated cartridge fuse, hidden until installed. The sprite is a
		# straight crop of an intact cartridge from the SAME painting
		# (the DINING ROOM row), so it matches its neighbors exactly.
		var sprite: Control
		if ResourceLoader.exists("res://assets/ui/FuseCartridge.png"):
			var tex := TextureRect.new()
			tex.texture = load("res://assets/ui/FuseCartridge.png")
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_SCALE
			tex.size = Vector2(103, 34)
			sprite = tex
		else:
			var block := ColorRect.new()
			block.color = Color(0.78, 0.85, 0.88)
			block.size = Vector2(103, 34)
			sprite = block
		sprite.position = SOCKET_POS[i] - sprite.size / 2.0
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sprite.visible = false
		_hotspots.add_child(sprite)
		_fuse_sprites.append(sprite)
	_update_hint(0)
