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

## Fired on every peer whenever the identity registries (display names
## AND skins — both travel in the same sync RPC) change: a peer
## registering, or a peer disconnecting. Mid-session changes aren't
## supported for either. See PLAYER_NAME_SYSTEM.md for the full design.
signal player_names_changed

var connected_peer_ids: Array[int] = []

## Server-authoritative peer_id -> display name registry, kept identical
## on every peer via the _sync_player_names RPC. Deliberately NOT
## grouped with the "Server-only bookkeeping" vars below — unlike
## _peer_sessions/_disconnected_sessions (which only the server ever
## needs), every peer reads this locally to render every OTHER player's
## name tag with zero per-frame network cost.
var peer_display_names: Dictionary = {} # peer_id (int) -> String

## Same lifecycle and sync path as peer_display_names: each peer's
## chosen character skin, validated server-side against the skins this
## build actually ships (SkinRegistry.valid_id) before being stored or
## broadcast — a peer can never replicate a skin id another build can't
## instantiate.
var peer_skins: Dictionary = {} # peer_id (int) -> String (SkinRegistry id)

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
	# Handshake never completed within WebRTCSignaler.HANDSHAKE_TIMEOUT_SEC
	# (e.g. no ICE candidate pair found) — reuse the same failure path as
	# ENet's own connection_failed so MainMenu doesn't need any new wiring.
	get_node("/root/WebRTCSignaler").connection_timed_out.connect(_on_connection_failed)
	randomize()
	local_session_id = "%d-%d" % [Time.get_ticks_usec(), randi()]


## Only starts the signaling handshake — the actual scene transition now
## happens once the server confirms the room was created
## (WebRTCSignaler._handle_message's room_created branch calls
## enter_game_as_host() below), not eagerly here. Previously this called
## enter_game_as_host() immediately, before the WebSocket had even
## connected, racing the "Generating code..." connecting-screen label
## against a scene change that had already happened.
func host_game() -> Error:
	get_node("/root/WebRTCSignaler").start_host()
	return OK

func enter_game_as_host() -> void:
	connected_peer_ids = [1] # the host is always peer id 1
	# TEMP DEBUG: this is a direct local function call, NOT an RPC/network
	# packet — the host registering itself never touches the wire. Logged
	# as such so it isn't mistaken for a real send in PACKET_TRACE.md.
	PacketTrace.sent("register_session", "HOST(self)", "HOST(self)", "session_id=%s preferred_role=%d display_name=%s skin=%s" % [local_session_id, GameSettings.preferred_role, GameSettings.display_name, GameSettings.skin_id], "_register_session (direct call, not RPC -- no packet actually sent)")
	_register_session(local_session_id, GameSettings.preferred_role, GameSettings.display_name, GameSettings.skin_id)
	TransitionScreen.cover("Entering %s..." % MapManager.get_map_name(MapManager.selected_map_id))
	get_tree().change_scene_to_file(GAME_SCENE)

func quick_play() -> Error:
	get_node("/root/WebRTCSignaler").start_quick_play()
	return OK


## Also used to *reconnect*: call this again (same running process, so
## local_session_id is unchanged) after a dropped connection and the
## server will recognize the session if called within
## RECONNECT_GRACE_PERIOD of the original disconnect.
func join_game(room_code: String) -> Error:
	if room_code.is_empty():
		return ERR_INVALID_PARAMETER
	get_node("/root/WebRTCSignaler").start_client(room_code)
	return OK

func cancel_connection() -> void:
	get_node("/root/WebRTCSignaler").stop()
	multiplayer.multiplayer_peer = null
	connected_peer_ids.clear()


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
	# Dictionary.erase() returns true only if the key was actually present,
	# so this never sends a pointless broadcast for a peer that had no
	# registered identity yet (e.g. it dropped mid-handshake). Two
	# separate statements on purpose: `or` short-circuits, and both
	# erases must always run.
	var had_name := peer_display_names.erase(id)
	var had_skin := peer_skins.erase(id)
	if multiplayer.is_server() and (had_name or had_skin):
		_sync_player_names.rpc(peer_display_names, peer_skins)
	player_disconnected.emit(id, session_id)


func _on_connected_to_server() -> void:
	connected_peer_ids = [1, multiplayer.get_unique_id()]
	PacketTrace.sent("register_session", multiplayer.get_unique_id(), 1, "session_id=%s preferred_role=%d display_name=%s skin=%s" % [local_session_id, GameSettings.preferred_role, GameSettings.display_name, GameSettings.skin_id], "_register_session") # TEMP DEBUG
	_register_session.rpc_id(1, local_session_id, GameSettings.preferred_role, GameSettings.display_name, GameSettings.skin_id)
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
	peer_display_names.clear()
	peer_skins.clear()
	# Without this, a stale round_active=true from the lost session would
	# block the next start_round() call after re-hosting/re-joining,
	# silently freezing the game until the app was fully restarted.
	RoundManager.reset_state()
	last_disconnect_reason = "Host disconnected."
	TransitionScreen.cover("Returning to menu...")
	get_tree().change_scene_to_file(MENU_SCENE)

func kick_peer(id: int) -> void:
	if multiplayer.is_server() and id != 1:
		PacketTrace.sent("receive_kick", multiplayer.get_unique_id(), id, "reason=You were kicked by the host.", "_receive_kick") # TEMP DEBUG
		_receive_kick.rpc_id(id, "You were kicked by the host.")

@rpc("authority", "call_remote", "reliable")
func _receive_kick(reason: String) -> void:
	# TEMP DEBUG: "authority"+"call_remote" means this can only ever run on
	# the actual target peer, never locally on the sender -- so unlike
	# _register_session below, there's no guard-clause "ignored" path here;
	# if this function runs at all, it's always a genuine network receive.
	PacketTrace.received("receive_kick", multiplayer.get_remote_sender_id(), multiplayer.get_unique_id(), "reason=%s" % reason, "_receive_kick", "_receive_kick (handled, no guard)")
	get_node("/root/WebRTCSignaler").stop()
	multiplayer.multiplayer_peer = null
	connected_peer_ids.clear()
	peer_display_names.clear()
	peer_skins.clear()
	RoundManager.reset_state()
	last_disconnect_reason = reason
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
	peer_display_names.clear()
	peer_skins.clear()
	RoundManager.reset_state()
	UIKit.block_mouse_capture = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	TransitionScreen.cover("Returning to menu...")
	get_tree().change_scene_to_file(MENU_SCENE)


## Called by every peer right after connecting (fresh join or reconnect).
## Only the server acts on it; harmless no-op on the caller's own machine
## otherwise (call_local fires this locally too, guarded below).
@rpc("any_peer", "call_local", "reliable")
func _register_session(session_id: String, preferred_role: int = 0, display_name: String = "", skin_id: String = "") -> void:
	# TEMP DEBUG: "call_local" means this always also runs locally on
	# whoever called .rpc_id(1, ...), even though the RPC target was only
	# peer 1 -- so a joining client sees this fire on its OWN machine too,
	# not just the server's. get_remote_sender_id() returns 0 for that
	# local invocation (it wasn't actually a received network packet at
	# all), which is exactly the guard below relies on.
	var is_local_call := multiplayer.get_remote_sender_id() == 0
	if not multiplayer.is_server():
		PacketTrace.received("register_session", ("LOCAL_CALL" if is_local_call else multiplayer.get_remote_sender_id()), multiplayer.get_unique_id(), "session_id=%s preferred_role=%d display_name=%s" % [session_id, preferred_role, display_name], "_register_session", "IGNORED (not server) -- expected for call_local's own-machine echo on a non-host peer")
		return
	PacketTrace.received("register_session", ("LOCAL_CALL(self)" if is_local_call else multiplayer.get_remote_sender_id()), multiplayer.get_unique_id(), "session_id=%s preferred_role=%d display_name=%s" % [session_id, preferred_role, display_name], "_register_session", "_register_session (handled)") # TEMP DEBUG
	var sender_id := multiplayer.get_remote_sender_id()
	var peer_id := sender_id if sender_id != 0 else 1
	_peer_sessions[peer_id] = session_id
	peer_preferred_roles[peer_id] = preferred_role
	_apply_display_name(peer_id, display_name, skin_id)

	if not _disconnected_sessions.has(session_id):
		return # a fresh join, not a reconnect — nothing more to do

	var record: Dictionary = _disconnected_sessions[session_id]
	_disconnected_sessions.erase(session_id)
	reconnect_grace_ended.emit(record["role"], true)
	player_reconnected.emit(peer_id, record["role"])


## Server-only. Registers peer_id's requested display name — falling back
## to a deterministic "Player N" if left blank or whitespace-only — and
## rebroadcasts the WHOLE registry (not just the changed entry) to every
## connected peer. Sending the full snapshot every time, rather than a
## diff, is what makes this trivial to reason about: every peer's
## peer_display_names is always a complete, self-consistent copy, never
## a partial update that could arrive out of order relative to another
## peer's own registration. See PLAYER_NAME_SYSTEM.md.
func _apply_display_name(peer_id: int, requested_name: String, requested_skin: String = "") -> void:
	var trimmed := requested_name.strip_edges().left(20)
	peer_display_names[peer_id] = trimmed if trimmed != "" else _default_display_name(peer_id)
	# Skins ride the same registration: validated against what THIS
	# build actually ships ("" when the build has no skin models at all,
	# which every consumer treats as "keep the stock capsule").
	peer_skins[peer_id] = SkinRegistry.valid_id(requested_skin)
	PacketTrace.sent("sync_player_names", multiplayer.get_unique_id(), "ALL (broadcast + call_local)", "names=%s skins=%s" % [peer_display_names, peer_skins], "_sync_player_names") # TEMP DEBUG
	_sync_player_names.rpc(peer_display_names, peer_skins)


## "Player 1" for the lowest connected peer id, "Player 2" for the next,
## and so on — the same stable, repeatable notion of "who's who" that
## RoleManager.assign_roles already uses (sorted peer id order), so the
## fallback name and the deterministic host-is-always-Player-1 ordering
## agree with each other without either system knowing about the other.
func _default_display_name(peer_id: int) -> String:
	var ids := connected_peer_ids.duplicate()
	ids.sort()
	var idx := ids.find(peer_id)
	return "Player %d" % (idx + 1 if idx != -1 else ids.size() + 1)


## Local-only lookup every PlayerController calls to render a name tag —
## zero network cost, since peer_display_names is already fully synced.
## Falls back to the same deterministic default the server would compute,
## so a tag is never blank even in the brief window before the real
## registry RPC has arrived (e.g. the instant a body first spawns).
func get_display_name(peer_id: int) -> String:
	return peer_display_names.get(peer_id, _default_display_name(peer_id))


## Local-only lookup, same contract as get_display_name(). "" means "no
## skin known (yet) for this peer" — PlayerController keeps the stock
## capsule until a later registry sync fills it in.
func get_peer_skin(peer_id: int) -> String:
	return peer_skins.get(peer_id, "")


@rpc("authority", "call_local", "reliable")
func _sync_player_names(names: Dictionary, skins: Dictionary = {}) -> void:
	PacketTrace.received("sync_player_names", multiplayer.get_remote_sender_id(), multiplayer.get_unique_id(), "names=%s skins=%s" % [names, skins], "_sync_player_names", "_sync_player_names (handled, no guard)") # TEMP DEBUG
	peer_display_names = names
	peer_skins = skins
	player_names_changed.emit()


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
