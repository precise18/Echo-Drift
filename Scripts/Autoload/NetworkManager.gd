extends Node
## Autoload: owns the ENet connection lifecycle (hosting, joining, and
## reacting to connection loss). Gameplay state (roles, timer, score)
## lives in RoundManager / MatchStateManager, not here.

const PORT := 7777
const MAX_PLAYERS := 2
const GAME_SCENE := "res://Scenes/Main.tscn"
const MENU_SCENE := "res://Scenes/UI/MainMenu.tscn"

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed

var connected_peer_ids: Array[int] = []


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host_game() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	connected_peer_ids = [1] # the host is always peer id 1
	get_tree().change_scene_to_file(GAME_SCENE)
	return OK


func join_game(address: String) -> Error:
	if address.is_empty():
		address = "127.0.0.1"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func _on_peer_connected(id: int) -> void:
	if not connected_peer_ids.has(id):
		connected_peer_ids.append(id)
	player_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	connected_peer_ids.erase(id)
	player_disconnected.emit(id)


func _on_connected_to_server() -> void:
	connected_peer_ids = [1, multiplayer.get_unique_id()]
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	RoundManager.reset_state()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	connected_peer_ids.clear()
	# Without this, a stale round_active=true from the lost session would
	# block the next start_round() call after re-hosting/re-joining,
	# silently freezing the game until the app was fully restarted.
	RoundManager.reset_state()
	get_tree().change_scene_to_file(MENU_SCENE)
