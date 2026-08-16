extends Node3D

## Entry scene. The MansionGenerator builds the (seed-shared) house in its
## own _ready; this script then spawns player bodies. Solo: one local
## player. Co-op: the host waits until every peer reports its scene loaded,
## then spawns one player per peer id — the MultiplayerSpawner replicates
## them to clients, and each node claims authority from its name.

const PLAYER_SCENE := preload("res://scenes/Player.tscn")

@onready var mansion: MansionGenerator = $MansionGenerator
@onready var players_root: Node3D = $Players

var _ready_peers := {}


func _ready() -> void:
	GameSettings.load_bindings()
	# Stop menu ambience (procedural audio) so it doesn't distract during gameplay
	_stop_menu_ambience()

	mansion.puzzle_solved.connect(_on_puzzle_solved)

	if not NetworkSession.multiplayer_active or multiplayer.multiplayer_peer == null:
		_spawn_player(1, 0)
		return
	if multiplayer.is_server():
		_ready_peers[1] = true
		multiplayer.peer_disconnected.connect(_on_peer_left)
		_try_spawn_all()
	else:
		_notify_loop()


## Client: keep telling the host we're loaded until our player appears
## (covers the race where the client's scene loads before the host's).
func _notify_loop() -> void:
	for i in 20:
		if players_root.get_child_count() > 0:
			return
		_notify_scene_ready.rpc_id(1)
		await get_tree().create_timer(0.5).timeout


@rpc("any_peer", "call_remote", "reliable")
func _notify_scene_ready() -> void:
	if not multiplayer.is_server():
		return
	_ready_peers[multiplayer.get_remote_sender_id()] = true
	_try_spawn_all()


func _try_spawn_all() -> void:
	if players_root.get_child_count() > 0:
		return
	var expected := 1 + multiplayer.get_peers().size()
	if _ready_peers.size() < expected:
		return
	var ids: Array = [1]
	ids.append_array(multiplayer.get_peers())
	ids.sort()
	for i in ids.size():
		_spawn_player(ids[i], i)


func _spawn_player(id: int, index: int) -> void:
	var player := PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.position = mansion.get_spawn_position() + Vector3(-0.9 + 1.8 * float(index), 0, 0)
	players_root.add_child(player)


func _on_peer_left(id: int) -> void:
	var node := players_root.get_node_or_null(str(id))
	if node:
		node.queue_free()


func _on_puzzle_solved() -> void:
	print("Puzzle solved: the Vault Study hums with light!")


func _stop_menu_ambience() -> void:
	# Stop the procedural ambience audio loops that play on menu
	for player in get_tree().get_nodes_in_group("ui_audio"):
		if player is AudioStreamPlayer:
			player.stop()
