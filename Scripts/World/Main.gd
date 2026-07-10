extends Node3D
## Game root: wires together the arena, player spawning, and the echo
## system. Round/match decisions live in RoundManager/MatchStateManager;
## spawn placement logic lives in SpawnManager; this script only connects
## the scene tree to those systems.

const PLAYER_SCENE := preload("res://Scenes/Player/Player.tscn")

@onready var players_container: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var echo_recorder: EchoRecorder = $EchoSystem/EchoRecorder
@onready var echo_ghost: EchoGhost = $EchoSystem/EchoGhost


func _ready() -> void:
	RoundManager.register_players_container(players_container)
	echo_ghost.recorder = echo_recorder

	spawner.spawned.connect(_on_node_spawned)
	RoundManager.role_assigned.connect(_on_role_assigned)
	RoundManager.round_started.connect(_on_round_started)

	if multiplayer.is_server():
		NetworkManager.player_connected.connect(_on_peer_connected_server)
		NetworkManager.player_disconnected.connect(_on_peer_disconnected_server)
		for id in NetworkManager.connected_peer_ids:
			_spawn_player(id)
		_try_start_round()


func _on_peer_connected_server(id: int) -> void:
	_spawn_player(id)
	_try_start_round()


## A round can't continue with only one player left, and leaving the old
## round_active=true in place would permanently block start_round() the
## next time someone joins. Despawn their body and reset to a clean,
## restartable state instead.
func _on_peer_disconnected_server(id: int) -> void:
	var node := players_container.get_node_or_null(str(id))
	if node != null:
		node.queue_free()
	RoundManager.reset_state()


func _try_start_round() -> void:
	if players_container.get_child_count() >= 2 and not RoundManager.round_active:
		RoundManager.start_round()


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


func _on_role_assigned(peer_id: int, role: int) -> void:
	if role != Role.HIDER:
		return
	var hider_node := players_container.get_node_or_null(str(peer_id))
	if hider_node != null:
		echo_recorder.set_target(hider_node)


func _on_round_started() -> void:
	_respawn_local_player()


## Each peer only moves the body it has authority over; the synchronizer
## replicates that position to everyone else. Delegates the actual
## placement to SpawnManager (see Scripts/World/SpawnManager.gd).
func _respawn_local_player() -> void:
	var local_id := multiplayer.get_unique_id()
	var player: CharacterBody3D = players_container.get_node_or_null(str(local_id))
	if player == null or not player.is_multiplayer_authority():
		return

	var role := Role.HIDER if local_id == RoundManager.hider_id else Role.HUNTER
	SpawnManager.respawn_player(get_tree(), player, role)
