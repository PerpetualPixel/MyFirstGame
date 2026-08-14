class_name Lobby
extends Control

## LAN co-op lobby. Host opens an ENet server on port 8910; a client joins
## by IP. When the host presses Start (allowed solo for testing), it rolls
## the shared seed and RPCs it to every peer, so both machines generate an
## identical mansion before gameplay begins.

const PORT := 8910
const MAIN_SCENE := "res://scenes/Main.tscn"
const MENU_SCENE := "res://scenes/MainMenu.tscn"

@onready var _status: Label = $Center/Panel/VBox/Status
@onready var _ip_edit: LineEdit = $Center/Panel/VBox/IPEdit
@onready var _host_btn: Button = $Center/Panel/VBox/HostButton
@onready var _join_btn: Button = $Center/Panel/VBox/JoinButton
@onready var _start_btn: Button = $Center/Panel/VBox/StartButton


func _ready() -> void:
	_host_btn.pressed.connect(host_game)
	_join_btn.pressed.connect(join_game)
	_start_btn.pressed.connect(_on_start_pressed)
	$Center/Panel/VBox/BackButton.pressed.connect(_on_back)
	_start_btn.disabled = true

	multiplayer.peer_connected.connect(_on_peers_changed)
	multiplayer.peer_disconnected.connect(_on_peers_changed)
	multiplayer.connected_to_server.connect(
		func() -> void: _status.text = "Connected! Waiting for the host to start...")
	multiplayer.connection_failed.connect(
		func() -> void:
			_status.text = "Connection failed."
			_reset_peer())

	if NetworkSession.lobby_mode == "host":
		host_game()


func host_game() -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, 2) != OK:
		_status.text = "Could not open port %d." % PORT
		return
	multiplayer.multiplayer_peer = peer
	_status.text = "Hosting on %s : %d  —  explorers: 1/2" % [_local_ip(), PORT]
	_host_btn.disabled = true
	_join_btn.disabled = true
	_start_btn.disabled = false  # solo start allowed for testing


func join_game() -> void:
	var text := _ip_edit.text.strip_edges()
	if text.is_empty():
		text = "127.0.0.1:%d" % PORT
	var parts := text.split(":")
	var ip := parts[0]
	var port := PORT
	if parts.size() > 1 and parts[1].is_valid_int():
		port = parts[1].to_int()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, port) != OK:
		_status.text = "Invalid address."
		return
	multiplayer.multiplayer_peer = peer
	_status.text = "Connecting to %s..." % ip
	_host_btn.disabled = true
	_join_btn.disabled = true
	_start_btn.visible = false  # only the host starts the run


func _on_peers_changed(_id: int) -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_status.text = "Hosting on %s : %d  —  explorers: %d/2" % [
			_local_ip(), PORT, 1 + multiplayer.get_peers().size()]


func _on_start_pressed() -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	var seed_value := (randi() % 2147483646) + 1
	_net_start.rpc(seed_value)


@rpc("authority", "call_local", "reliable")
func _net_start(seed_value: int) -> void:
	NetworkSession.run_seed = seed_value
	NetworkSession.multiplayer_active = multiplayer.multiplayer_peer != null
	get_tree().change_scene_to_file(MAIN_SCENE)


func _on_back() -> void:
	_reset_peer()
	NetworkSession.reset()
	get_tree().change_scene_to_file(MENU_SCENE)


func _reset_peer() -> void:
	multiplayer.multiplayer_peer = null
	_host_btn.disabled = false
	_join_btn.disabled = false
	_start_btn.visible = true
	_start_btn.disabled = true


func _local_ip() -> String:
	var fallback := "127.0.0.1"
	for address in IP.get_local_addresses():
		if address.begins_with("192.") or address.begins_with("10."):
			return address
		if not address.contains(":") and not address.begins_with("127."):
			fallback = address
	return fallback
