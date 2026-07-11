extends Node
## Autoload: owns the ENet connection lifecycle (hosting, joining, and
## reacting to connection loss) plus lightweight reconnect support.
## Gameplay state (roles, timer, score) lives in RoundManager /
## MatchStateManager, not here — this only decides *whether* a returning
## connection should be treated as the same player, not what to do about
## it (that's Main.gd/RoundManager's job, driven by the signals below).
## See NETWORKING_REPORT.md for the full design writeup.

const PORT := 7777
const MAX_PLAYERS := 2
const GAME_SCENE := "res://Scenes/Main.tscn"
const MENU_SCENE := "res://Scenes/UI/MainMenu.tscn"

## How long the server holds a disconnected player's role open, waiting
## for them to reconnect, before giving up and resetting the round.
const RECONNECT_GRACE_PERIOD := 20.0

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int, session_id: String)
signal connection_failed

## Server-only: fired the instant a mid-round disconnect starts a grace
## window (so the surviving peer's HUD can show "waiting to reconnect").
signal reconnect_grace_started(role: int)
## Server-only: fired when a grace window ends, either because the peer
## came back (`reconnected = true`) or the window expired.
signal reconnect_grace_ended(role: int, reconnected: bool)
## Server-only: fired when a returning session is recognized and should
## be restored to `role` under its new peer id.
signal player_reconnected(peer_id: int, role: int)

var connected_peer_ids: Array[int] = []

## Generated once per running process and sent to the server on every
## connection attempt. This is what lets the server recognize "this is
## the same player as before" across a dropped-then-restored connection
## — ENet itself never reuses peer ids, so peer id alone can't do this.
var local_session_id: String

## Set right before returning to the menu after a lost connection, so
## MainMenu can explain why the player ended up back there. Cleared once
## shown.
var last_disconnect_reason := ""

# Server-only bookkeeping.
var _peer_sessions: Dictionary = {} # peer_id -> session_id
var _disconnected_sessions: Dictionary = {} # session_id -> {role, expires_at}
var peer_preferred_roles: Dictionary = {} # peer_id -> preferred_role (0: Any, 1: Hider, 2: Hunter)


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	WebRTCSignaler.match_ready.connect(_on_webrtc_match_ready)
	randomize()
	local_session_id = "%d-%d" % [Time.get_ticks_usec(), randi()]

func _on_webrtc_match_ready() -> void:
	if not WebRTCSignaler.is_host:
		pass # We wait for connected_to_server instead for clients


func host_game() -> Error:
	WebRTCSignaler.start_host()
	enter_game_as_host()
	return OK

func enter_game_as_host() -> void:
	connected_peer_ids = [1] # the host is always peer id 1
	_register_session(local_session_id, GameSettings.preferred_role)
	TransitionScreen.cover("Entering %s..." % MapManager.get_map_name(MapManager.selected_map_id))
	get_tree().change_scene_to_file(GAME_SCENE)

func quick_play() -> Error:
	WebRTCSignaler.start_quick_play()
	return OK


## Also used to *reconnect*: call this again (same running process, so
## local_session_id is unchanged) after a dropped connection and the
## server will recognize the session if called within
## RECONNECT_GRACE_PERIOD of the original disconnect.
func join_game(room_code: String) -> Error:
	if room_code.is_empty():
		return ERR_INVALID_PARAMETER
	WebRTCSignaler.start_client(room_code)
	return OK


func _on_peer_connected(id: int) -> void:
	if not connected_peer_ids.has(id):
		connected_peer_ids.append(id)
	if multiplayer.is_server():
		# Tell them which map is active *before* they load the game scene,
		# so Main.gd never has to guess or race a late-arriving sync.
		MapManager.sync_to_peer(id)
	player_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	connected_peer_ids.erase(id)
	var session_id: String = _peer_sessions.get(id, "")
	_peer_sessions.erase(id)
	player_disconnected.emit(id, session_id)


func _on_connected_to_server() -> void:
	connected_peer_ids = [1, multiplayer.get_unique_id()]
	_register_session.rpc_id(1, local_session_id, GameSettings.preferred_role)
	# Load immediately rather than waiting for MapManager's sync RPC —
	# Godot's own MultiplayerSpawner replication for already-spawned
	# nodes (e.g. the host's own player) can arrive as soon as the ENet
	# connection completes, and needs Main.tscn's MultiplayerSpawner to
	# already exist to receive it. Main.gd itself waits for the map sync
	# before instantiating map *content*, which nothing else depends on.
	# The loading cover paints over this load; it never delays it (see
	# TransitionScreen.gd).
	TransitionScreen.cover("Joining match...")
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
	last_disconnect_reason = "Host disconnected."
	TransitionScreen.cover("Returning to menu...")
	get_tree().change_scene_to_file(MENU_SCENE)


## Deliberately leaving (pause menu -> Leave Match), as opposed to losing
## the connection: close the peer cleanly, reset session state, and go
## back to the menu with no "disconnected" explanation banner — the
## player chose this.
func leave_game() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	connected_peer_ids.clear()
	_peer_sessions.clear()
	_disconnected_sessions.clear()
	peer_preferred_roles.clear()
	RoundManager.reset_state()
	UIKit.block_mouse_capture = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	TransitionScreen.cover("Returning to menu...")
	get_tree().change_scene_to_file(MENU_SCENE)


## Called by every peer right after connecting (fresh join or reconnect).
## Only the server acts on it; harmless no-op on the caller's own machine
## otherwise (call_local fires this locally too, guarded below).
@rpc("any_peer", "call_local", "reliable")
func _register_session(session_id: String, preferred_role: int = 0) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var peer_id := sender_id if sender_id != 0 else 1
	_peer_sessions[peer_id] = session_id
	peer_preferred_roles[peer_id] = preferred_role

	if not _disconnected_sessions.has(session_id):
		return # a fresh join, not a reconnect — nothing more to do

	var record: Dictionary = _disconnected_sessions[session_id]
	_disconnected_sessions.erase(session_id)
	reconnect_grace_ended.emit(record["role"], true)
	player_reconnected.emit(peer_id, record["role"])


## Server-only. Called by Main.gd when a peer disconnects mid-round:
## holds their role open instead of immediately resetting, so a quick
## reconnect (same running client, same local_session_id) can resume
## the match instead of ending it.
func hold_reconnect_slot(session_id: String, role: int) -> void:
	var expires_at := Time.get_ticks_msec() / 1000.0 + RECONNECT_GRACE_PERIOD
	_disconnected_sessions[session_id] = {"role": role, "expires_at": expires_at}
	reconnect_grace_started.emit(role)
	get_tree().create_timer(RECONNECT_GRACE_PERIOD).timeout.connect(
		_on_grace_window_elapsed.bind(session_id)
	)


func _on_grace_window_elapsed(session_id: String) -> void:
	if not _disconnected_sessions.has(session_id):
		return # they reconnected in time; nothing to do
	var record: Dictionary = _disconnected_sessions[session_id]
	_disconnected_sessions.erase(session_id)
	reconnect_grace_ended.emit(record["role"], false)
