extends Node3D
## Game root: wires together the map, player spawning, and the echo
## system. Round/match decisions live in RoundManager/MatchStateManager;
## spawn placement logic lives in SpawnManager; which map to load lives
## in MapManager — this script only connects the scene tree to those
## systems.

var PLAYER_SCENE: PackedScene = load("res://Scenes/Player/Player.tscn")
const CAPTURE_COLOR := Color(1.0, 0.75, 0.3) # warm gold — distinct from the echo system's cyan

@onready var map_container: Node3D = $MapContainer
@onready var players_container: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var echo_system: EchoSystem = $EchoSystem


func _ready() -> void:
	# The server always knows its own map choice immediately; a client
	# might still be waiting on MapManager's sync RPC (which is
	# deliberately independent of scene-load timing — see MapManager.
	# is_map_ready() and NETWORKING_REPORT.md). Either way, map *content*
	# loading never blocks the rest of this scene from being ready
	# (Players/MultiplayerSpawner must exist immediately regardless, so
	# Godot's own spawner replication for already-spawned nodes has
	# somewhere to land).
	if MapManager.is_map_ready():
		_load_map()
	else:
		MapManager.map_selected.connect(_on_map_ready, CONNECT_ONE_SHOT)

	RoundManager.register_players_container(players_container)

	spawner.spawned.connect(_on_node_spawned)
	RoundManager.role_assigned.connect(_on_role_assigned)
	RoundManager.round_started.connect(_on_round_started)
	RoundManager.round_ended.connect(_on_round_ended)

	if multiplayer.is_server():
		NetworkManager.player_connected.connect(_on_peer_connected_server)
		NetworkManager.player_disconnected.connect(_on_peer_disconnected_server)
		NetworkManager.player_reconnected.connect(_on_player_reconnected_server)
		NetworkManager.reconnect_grace_ended.connect(_on_reconnect_grace_ended_server)
		for id in NetworkManager.connected_peer_ids:
			_spawn_player(id)


func _load_map() -> void:
	map_container.add_child(MapManager.instantiate_selected_map())


func _on_map_ready(_map_id: String) -> void:
	_load_map()
	# A round may already have started (round_started arrived) while we
	# were still waiting on the map sync — SpawnManager needs the map's
	# spawn markers to exist, so retry the respawn now that they do.
	if RoundManager.round_active:
		_respawn_local_player()


## Rounds are no longer auto-started here when the second player arrives
## — players land in a warm-up lobby and the host presses Start Match
## (HUD -> RoundManager.start_match). See UI_GUIDE.md.
func _on_peer_connected_server(id: int) -> void:
	_spawn_player(id)


## Despawns the departed player's body immediately either way (a stale
## body left standing in the arena would be confusing and could still
## trip WinConditions lookups by name collision on reconnect). If a round
## was in progress, though, don't reset yet — hold their role open for a
## short window in case they reconnect (see NetworkManager.
## hold_reconnect_slot / NETWORKING_REPORT.md). If no round was active,
## there's no state worth preserving, so reset immediately as before.
func _on_peer_disconnected_server(id: int, session_id: String) -> void:
	var node := players_container.get_node_or_null(str(id))
	if node != null:
		node.queue_free()

	if RoundManager.round_active and session_id != "":
		var role := Role.HIDER if id == RoundManager.hider_id else Role.HUNTER
		NetworkManager.hold_reconnect_slot(session_id, role)
	else:
		RoundManager.reset_state()


## A returning session within the grace window: bring their body back
## and restore their role under their new peer id.
func _on_player_reconnected_server(peer_id: int, role: int) -> void:
	_spawn_player(peer_id)
	RoundManager.reassign_role(peer_id, role)


## The grace window ran out without a reconnect — now it's safe to reset,
## same as the old immediate-reset behavior.
func _on_reconnect_grace_ended_server(_role: int, reconnected: bool) -> void:
	if not reconnected:
		RoundManager.reset_state()


func _spawn_player(peer_id: int) -> void:
	if players_container.has_node(str(peer_id)):
		return
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	# Staggered lobby positions — never let two bodies spawn coincident.
	# Overlapping capsules each depenetrate upward out of the *other
	# peer's replicated* collider, which replicates the new height back,
	# and the pair ratchet-climb into the sky (observed at y=56 within
	# seconds). Fixed offsets rather than the map's spawn markers because
	# a joining client's map content loads after its player body arrives;
	# round-start placement still comes from SpawnManager as before.
	player.position = Vector3(-2.0 + 4.0 * players_container.get_child_count(), 0.1, 4.0)
	players_container.add_child(player)
	# Authority is set AFTER add_child on purpose: the server must still
	# be the synchronizer's authority at the moment the spawner captures
	# spawn state, or the placed position above never reaches the owning
	# client (verified: reordering these sent the joiner a corrupt spawn
	# position). MultiplayerSpawner's "spawned" signal only fires on
	# *receiving* peers, so the server handles its own nodes here — and
	# because _ready therefore ran with default authority, re-apply the
	# controller's authority-dependent state (camera.current, mouse
	# capture) now that the real owner is known, exactly as
	# _on_node_spawned does on clients.
	player.set_multiplayer_authority(peer_id)
	player.apply_authority_state()


## Runs on every receiving peer whenever a player node appears under
## Players/ via replication. Replicated nodes necessarily run _ready
## before this fires, with default authority — so after correcting the
## authority, re-run the controller's authority-dependent setup (camera
## current, mouse capture); without that, the local player's own camera
## never becomes current on a client (the "stuck in first person" bug).
func _on_node_spawned(node: Node) -> void:
	var node_name := String(node.name)
	if node_name.is_valid_int():
		node.set_multiplayer_authority(node_name.to_int())
		if node.has_method("apply_authority_state"):
			node.apply_authority_state()


func _on_role_assigned(peer_id: int, role: int) -> void:
	if role != Role.HIDER:
		return
	var hider_node := players_container.get_node_or_null(str(peer_id))
	if hider_node != null:
		echo_system.set_target(hider_node)


func _on_round_started() -> void:
	# If the map hasn't loaded yet (client still waiting on MapManager's
	# sync RPC), _on_map_ready() will retry this once it has — spawn
	# markers wouldn't exist to place the player at yet anyway.
	if MapManager.is_map_ready():
		_respawn_local_player()


## Stops the echo(es) the instant the round ends, rather than letting a
## ghost keep trailing (and humming) over the round-end screen. Also marks
## an actual capture (winner_role == HUNTER; a timeout has no such moment)
## with a one-shot burst at the hider's position — every peer runs this
## independently off the same replicated round_ended RPC, so the flourish
## appears in the same place for both players without needing its own
## network message.
func _on_round_ended(winner_role: int) -> void:
	echo_system.clear()
	if winner_role == Role.HUNTER:
		_spawn_capture_burst()


func _spawn_capture_burst() -> void:
	var hider_node := players_container.get_node_or_null(str(RoundManager.hider_id))
	if hider_node == null:
		return
	var burst := MapKit.make_burst_particles(CAPTURE_COLOR, 28, "CaptureBurst")
	map_container.add_child(burst)
	burst.global_position = hider_node.global_position + Vector3(0, 1.0, 0)
	burst.restart()


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
