extends Node3D
## Game root: wires together the arena, player spawning, and the echo
## system. Round/score decisions themselves live in GameManager; this
## script only connects the scene tree to that state.

const PLAYER_SCENE := preload("res://Scenes/Player/Player.tscn")

@onready var players_container: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var echo_recorder: EchoRecorder = $EchoSystem/EchoRecorder
@onready var echo_ghost: EchoGhost = $EchoSystem/EchoGhost


func _ready() -> void:
	GameManager.register_players_container(players_container)
	echo_ghost.recorder = echo_recorder

	spawner.spawned.connect(_on_node_spawned)
	GameManager.role_assigned.connect(_on_role_assigned)
	GameManager.round_started.connect(_on_round_started)

	if multiplayer.is_server():
		NetworkManager.player_connected.connect(_on_peer_connected_server)
		for id in NetworkManager.connected_peer_ids:
			_spawn_player(id)
		_try_start_round()


func _on_peer_connected_server(id: int) -> void:
	_spawn_player(id)
	_try_start_round()


func _try_start_round() -> void:
	if players_container.get_child_count() >= 2 and not GameManager.round_active:
		GameManager.start_round()


func _spawn_player(peer_id: int) -> void:
	if players_container.has_node(str(peer_id)):
		return
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	players_container.add_child(player)
	# MultiplayerSpawner's "spawned" signal only fires on peers that
	# *receive* the replicated node, not on the server that originates it
	# via add_child() — so the server must set authority on itself here.
	player.set_multiplayer_authority(peer_id)


## Runs on every peer whenever a player node appears under Players/,
## whether spawned locally or replicated from the server. This is what
## makes each *receiving* client agree on the same authority.
func _on_node_spawned(node: Node) -> void:
	var node_name := String(node.name)
	if node_name.is_valid_int():
		node.set_multiplayer_authority(node_name.to_int())


func _on_role_assigned(peer_id: int, role: GameManager.Role) -> void:
	if role != GameManager.Role.HIDER:
		return
	var hider_node := players_container.get_node_or_null(str(peer_id))
	if hider_node != null:
		echo_recorder.set_target(hider_node)


func _on_round_started() -> void:
	_move_local_player_to_spawn()


## Each peer only moves the body it has authority over; the synchronizer
## replicates that position to everyone else.
func _move_local_player_to_spawn() -> void:
	var local_id := multiplayer.get_unique_id()
	var player: Node3D = players_container.get_node_or_null(str(local_id))
	if player == null or not player.is_multiplayer_authority():
		return

	var group := "hider_spawn" if local_id == GameManager.hider_id else "hunter_spawn"
	var markers := get_tree().get_nodes_in_group(group)
	if markers.is_empty():
		return

	player.global_position = markers[0].global_position
	player.velocity = Vector3.ZERO
