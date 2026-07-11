extends Node

signal room_created(code: String)
signal room_error(msg: String)
signal match_ready()
signal disconnected()
## Fired when a WebRTC handshake was started (match_ready already emitted)
## but never actually completed within HANDSHAKE_TIMEOUT_SEC — e.g. no ICE
## candidate pair could be found (NAT traversal failure). Distinct from
## `disconnected`, which is about the signaling socket, not the P2P
## transport it was brokering.
signal connection_timed_out()

var ws: WebSocketPeer = null
var webrtc_mp: WebRTCMultiplayerPeer = null
var webrtc_conn: WebRTCPeerConnection = null

var is_host := false
var server_url := "wss://echo-relay.onrender.com"

var _pending_action := ""
var current_room_code := ""
var is_quick_play := false

## Set once webrtc_mp.create_server() has actually been called for the
## current attempt, so the room_created handler (which every hosting path
## now funnels through — see _handle_message) never calls it twice.
var _server_created := false

## How long to wait after match_ready for the underlying transport to
## actually report a connected peer before giving up (see
## connection_timed_out above). Modeled on NetworkManager's
## RECONNECT_GRACE_PERIOD timer pattern.
const HANDSHAKE_TIMEOUT_SEC := 15.0
var _handshake_confirmed := false

## Bounded auto-retry for the *signaling* WebSocket only, and only while
## still mid room-setup (before _setup_webrtc has run) — a drop after ICE
## signaling has started isn't safely resumable against a server we don't
## control the source of, so that case still falls straight through to
## `disconnected`.
const _WS_MAX_RETRIES := 3
const _WS_RETRY_BACKOFF := [1.0, 2.0, 4.0]
var _ws_retry_count := 0
var _ws_generation := 0
var _last_action_json := ""

# --- TEMP DEBUG: WebSocket lifecycle audit (see SOCKET_DEBUG.md) -----------
# Grep "[WS-DEBUG]" to find/remove every line added for this audit.
var _last_ws_state := WebSocketPeer.STATE_CLOSED
var _ws_connect_started_at := 0
var _ws_timeout_logged := false
const _WS_CONNECT_TIMEOUT_MSEC := 10000

func _debug_log_socket_event(event: String, detail: String = "") -> void:
	if detail != "":
		print("[WS-DEBUG][%d] %s — %s" % [Time.get_ticks_msec(), event, detail])
	else:
		print("[WS-DEBUG][%d] %s" % [Time.get_ticks_msec(), event])
# ----------------------------------------------------------------------------

func _ready():
	set_process(false)
	# Real confirmation the WebRTC transport actually connected (not just
	# that signaling finished) — cancels the handshake-timeout watchdog
	# started in _setup_webrtc(). Host sees peer_connected; joiner sees
	# connected_to_server.
	multiplayer.peer_connected.connect(_on_handshake_confirmed)
	multiplayer.connected_to_server.connect(_on_handshake_confirmed)

	# Wake up the free Render server immediately when the game launches
	var http = HTTPRequest.new()
	add_child(http)
	var http_url = server_url.replace("wss://", "https://").replace("ws://", "http://")
	http.request(http_url)

	var timer = Timer.new()
	timer.wait_time = 30.0
	timer.autostart = true
	timer.timeout.connect(func():
		if ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			var ping_packet := JSON.stringify({"type": "ping"})
			ws.put_packet(ping_packet.to_utf8_buffer())
			_debug_log_socket_event("PING", ping_packet) # TEMP DEBUG
			PacketTrace.sent("ping", "CLIENT", "RELAY", ping_packet, "relay server (source not in this repo) -- no \"pong\" ever observed in return, see PACKET_TRACE.md") # TEMP DEBUG
	)
	add_child(timer)

func _process(_delta):
	if ws != null:
		ws.poll()
		var state = ws.get_ready_state()

		# TEMP DEBUG: log every state transition exactly once, not per-frame.
		if state != _last_ws_state:
			match state:
				WebSocketPeer.STATE_OPEN:
					_debug_log_socket_event("CONNECTED", "handshake complete, awaiting server ack")
				WebSocketPeer.STATE_CLOSING:
					_debug_log_socket_event("CLOSING", "close handshake started")
				WebSocketPeer.STATE_CLOSED:
					_debug_log_socket_event("DISCONNECTED", "close_code=%d reason=%s" % [ws.get_close_code(), ws.get_close_reason()])
			_last_ws_state = state

		# TEMP DEBUG: flag a connect attempt that never reaches STATE_OPEN.
		if state == WebSocketPeer.STATE_CONNECTING and not _ws_timeout_logged:
			if Time.get_ticks_msec() - _ws_connect_started_at > _WS_CONNECT_TIMEOUT_MSEC:
				_ws_timeout_logged = true
				_debug_log_socket_event("TIMEOUT", "still CONNECTING after %dms" % _WS_CONNECT_TIMEOUT_MSEC)

		if state == WebSocketPeer.STATE_OPEN:
			if _pending_action != "":
				ws.put_packet(_pending_action.to_utf8_buffer())
				_debug_log_socket_event("MESSAGE_SENT", _pending_action) # TEMP DEBUG
				var action_type := "?"
				var parsed_action = JSON.parse_string(_pending_action)
				if typeof(parsed_action) == TYPE_DICTIONARY:
					action_type = str(parsed_action.get("type", "?"))
				PacketTrace.sent(action_type, "CLIENT", "RELAY", _pending_action, "relay server (source not in this repo)") # TEMP DEBUG
				_pending_action = ""

			while ws.get_available_packet_count() > 0:
				var packet = ws.get_packet().get_string_from_utf8()
				_debug_log_socket_event("MESSAGE_RECEIVED", packet) # TEMP DEBUG
				var msg = JSON.parse_string(packet)
				# TEMP DEBUG: previously a malformed/non-dict packet was
				# silently dropped here with zero trace of any kind — the
				# only way to "identify packets with invalid format" is to
				# actually check for this instead of letting `if msg:` eat
				# it silently.
				if msg == null or typeof(msg) != TYPE_DICTIONARY or not msg.has("type"):
					PacketTrace.received("UNKNOWN", "RELAY", "CLIENT", packet, "_handle_message (any known type)", "INVALID_FORMAT — dropped (not a dict, or missing \"type\")")
					continue
				_handle_message(msg)
		elif state == WebSocketPeer.STATE_CLOSED:
			set_process(false)
			# Only retry while still purely in room-setup (no WebRTC
			# signaling has started yet) — once _setup_webrtc() has run,
			# blindly resending create_room/join_room against a fresh
			# socket isn't well-defined for a server we don't control.
			if webrtc_conn == null and _ws_retry_count < _WS_MAX_RETRIES:
				_schedule_ws_retry()
			else:
				disconnected.emit()
				if _ws_retry_count >= _WS_MAX_RETRIES:
					room_error.emit("Lost connection to the matchmaking server. Please try again.")

	if webrtc_conn != null:
		webrtc_conn.poll()

func _debug_arm_connect_watchdog() -> void: # TEMP DEBUG
	_ws_connect_started_at = Time.get_ticks_msec()
	_ws_timeout_logged = false
	_last_ws_state = WebSocketPeer.STATE_CONNECTING

## Bounded, backed-off retry of the signaling socket only (see the
## _WS_MAX_RETRIES doc comment above). `gen` guards against a stale retry
## firing after the user cancelled or a fresh start_*() call superseded
## this attempt in the meantime.
func _schedule_ws_retry() -> void:
	var gen := _ws_generation
	var delay: float = _WS_RETRY_BACKOFF[_ws_retry_count]
	_ws_retry_count += 1
	_debug_log_socket_event("RECONNECTING", "attempt %d/%d in %.0fs" % [_ws_retry_count, _WS_MAX_RETRIES, delay])
	get_tree().create_timer(delay).timeout.connect(func():
		if gen != _ws_generation:
			return
		ws = WebSocketPeer.new()
		_pending_action = _last_action_json
		_debug_arm_connect_watchdog() # TEMP DEBUG
		var err := ws.connect_to_url(server_url)
		if err == OK:
			set_process(true)
			_debug_log_socket_event("CONNECTING", "url=%s action=%s (retry %d/%d)" % [server_url, _last_action_json, _ws_retry_count, _WS_MAX_RETRIES])
		else:
			_debug_log_socket_event("CONNECT_ERROR", "retry connect_to_url returned err=%d" % err)
	)

func start_host():
	stop()
	ws = WebSocketPeer.new()
	webrtc_mp = WebRTCMultiplayerPeer.new()
	is_quick_play = false
	is_host = true
	webrtc_mp.create_server()
	_server_created = true
	multiplayer.multiplayer_peer = webrtc_mp
	_pending_action = JSON.stringify({"type": "create_room"})
	_last_action_json = _pending_action
	_ws_retry_count = 0
	_ws_generation += 1
	_debug_arm_connect_watchdog() # TEMP DEBUG
	var err = ws.connect_to_url(server_url)
	if err == OK:
		set_process(true)
		_debug_log_socket_event("CONNECTING", "url=%s action=create_room" % server_url) # TEMP DEBUG
	else:
		_debug_log_socket_event("CONNECT_ERROR", "connect_to_url returned err=%d" % err) # TEMP DEBUG

func start_client(room_code: String):
	stop()
	ws = WebSocketPeer.new()
	webrtc_mp = WebRTCMultiplayerPeer.new()
	is_quick_play = false
	is_host = false
	_pending_action = JSON.stringify({"type": "join_room", "room": room_code})
	_last_action_json = _pending_action
	_ws_retry_count = 0
	_ws_generation += 1
	_debug_arm_connect_watchdog() # TEMP DEBUG
	var err = ws.connect_to_url(server_url)
	if err == OK:
		set_process(true)
		_debug_log_socket_event("CONNECTING", "url=%s action=join_room room=%s" % [server_url, room_code]) # TEMP DEBUG
	else:
		_debug_log_socket_event("CONNECT_ERROR", "connect_to_url returned err=%d" % err) # TEMP DEBUG

func start_quick_play():
	stop()
	ws = WebSocketPeer.new()
	webrtc_mp = WebRTCMultiplayerPeer.new()
	is_quick_play = true
	is_host = false
	_pending_action = JSON.stringify({"type": "quick_play"})
	_last_action_json = _pending_action
	_ws_retry_count = 0
	_ws_generation += 1
	_debug_arm_connect_watchdog() # TEMP DEBUG
	var err = ws.connect_to_url(server_url)
	if err == OK:
		set_process(true)
		_debug_log_socket_event("CONNECTING", "url=%s action=quick_play" % server_url) # TEMP DEBUG
	else:
		_debug_log_socket_event("CONNECT_ERROR", "connect_to_url returned err=%d" % err) # TEMP DEBUG

func stop():
	set_process(false)
	_ws_generation += 1 # invalidate any pending retry timer scheduled by _schedule_ws_retry
	_server_created = false
	if ws != null:
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			var leave_packet := JSON.stringify({"type": "leave_room"})
			ws.put_packet(leave_packet.to_utf8_buffer())
			_debug_log_socket_event("MESSAGE_SENT", leave_packet) # TEMP DEBUG
			PacketTrace.sent("leave_room", "CLIENT", "RELAY", leave_packet, "relay server (source not in this repo)") # TEMP DEBUG
		_debug_log_socket_event("DISCONNECTED", "local stop() called") # TEMP DEBUG
		ws.close()
		ws = null
	if webrtc_mp != null:
		webrtc_mp.close()
		webrtc_mp = null
	if webrtc_conn != null:
		webrtc_conn.close()
		webrtc_conn = null
	multiplayer.multiplayer_peer = null
	current_room_code = ""

func _handle_message(msg: Dictionary):
	if msg.type == "room_created":
		current_room_code = msg.room
		# TEMP DEBUG: this protocol has no credential/token exchange — the
		# first application-level ack from the server (room_created) is the
		# closest equivalent to "authenticated" this socket has.
		_debug_log_socket_event("AUTHENTICATED", "room=%s is_public=%s (no real auth handshake exists — see SOCKET_DEBUG.md)" % [msg.room, msg.get("is_public", false)])
		if msg.get("is_public", false):
			is_host = true
		# Every hosting path (private "Host Private Game" via start_host(),
		# and public/quick-play winning the host coin-flip here) now funnels
		# through this single spot, gated on the actual server ack rather
		# than transitioning scenes eagerly before the room is confirmed to
		# exist. _server_created guards against calling create_server()
		# twice for the private-host case, which already called it in
		# start_host() before the room was confirmed.
		if is_host:
			if not _server_created:
				webrtc_mp.create_server()
				_server_created = true
			multiplayer.multiplayer_peer = webrtc_mp
			NetworkManager.enter_game_as_host()
		room_created.emit(msg.room)
		PacketTrace.received("room_created", "RELAY", "CLIENT", JSON.stringify(msg), "_handle_message/room_created", "_handle_message/room_created (handled)") # TEMP DEBUG
	elif msg.type == "error":
		_debug_log_socket_event("ERROR", str(msg.get("message", ""))) # TEMP DEBUG
		room_error.emit(msg.message)
		PacketTrace.received("error", "RELAY", "CLIENT", JSON.stringify(msg), "_handle_message/error", "_handle_message/error (handled)") # TEMP DEBUG
	elif msg.type == "peer_connected":
		_debug_log_socket_event("PEER_CONNECTED", "is_host=%s" % str(msg.get("is_host", null))) # TEMP DEBUG
		if msg.has("is_host"):
			is_host = msg.is_host
		_setup_webrtc()
		PacketTrace.received("peer_connected", "RELAY", "CLIENT", JSON.stringify(msg), "_handle_message/peer_connected", "_handle_message/peer_connected (handled)") # TEMP DEBUG
	elif msg.type == "webrtc_signal":
		_handle_signal(msg.data)
		# TEMP DEBUG: sub-type (sdp/ice) resolved inside _handle_signal — see
		# its own trace calls for whether that inner dispatch actually matched.
		PacketTrace.received("webrtc_signal/%s" % str(msg.data.get("type", "?")), "RELAY", "CLIENT", JSON.stringify(msg).left(200), "_handle_message/webrtc_signal -> _handle_signal", "_handle_message/webrtc_signal (dispatched)")
	elif msg.type == "peer_disconnected":
		# TEMP DEBUG: this is the *remote peer* leaving, not our own socket
		# closing — our WS to the relay is still open at this point.
		_debug_log_socket_event("REMOTE_PEER_LEFT", "our socket is still open; this is peer_disconnected, not DISCONNECTED")
		disconnected.emit()
		PacketTrace.received("peer_disconnected", "RELAY", "CLIENT", JSON.stringify(msg), "_handle_message/peer_disconnected", "_handle_message/peer_disconnected (handled) -- but disconnected signal itself has ZERO listeners, see PACKET_TRACE.md") # TEMP DEBUG
	elif msg.type == "pong":
		# TEMP DEBUG: no "pong" message type has ever been observed from the
		# live server during this audit — kept here so a reply becomes
		# visible immediately if the server ever sends one.
		_debug_log_socket_event("PONG", "heartbeat acknowledged by server")
		PacketTrace.received("pong", "RELAY", "CLIENT", JSON.stringify(msg), "_handle_message/pong", "_handle_message/pong (handled)") # TEMP DEBUG
	else:
		# TEMP DEBUG: well-formed JSON with a "type" field, but one this
		# client has no case for at all — previously fell through the whole
		# if/elif chain with zero trace, indistinguishable from a message
		# that was never sent in the first place.
		PacketTrace.received(str(msg.type), "RELAY", "CLIENT", JSON.stringify(msg), "(none — no matching branch in _handle_message)", "UNHANDLED — no case matches this type")

func _setup_webrtc():
	if webrtc_conn != null:
		return # already set up for this attempt — peer_connected shouldn't fire twice, but don't recreate if it does

	webrtc_conn = WebRTCPeerConnection.new()
	# STUN alone only works when both peers can find a direct UDP path —
	# it fails silently (no candidate pair, connection just never
	# completes) behind symmetric NAT/CGNAT/restrictive firewalls, which is
	# common for two strangers matchmaking over a public relay. TURN is the
	# relay-of-last-resort for exactly that case. A TURN config was added
	# once (commit 7b48cec) and reverted (37853ca) after initialize() was
	# blamed for a failure — empirically re-verified this pass (actual
	# add_peer()/create_offer() cycle, not just initialize()'s return code)
	# that a *single* URL per iceServers entry with no `?transport=tcp`
	# suffix (unsupported by this build's libjuice ICE agent — confirmed
	# via the shipped addons/webrtc_native binary) initializes and offers
	# cleanly. Two TURN entries (80 and 443) since some networks block one.
	var init_err = webrtc_conn.initialize({
		"iceServers": [
			{ "urls": ["stun:stun.l.google.com:19302"] },
			{ "urls": ["turn:openrelay.metered.ca:80"], "username": "openrelayproject", "credential": "openrelayproject" },
			{ "urls": ["turn:openrelay.metered.ca:443"], "username": "openrelayproject", "credential": "openrelayproject" }
		]
	})
	if init_err != OK: push_error("WebRTC initialize failed: ", init_err)

	webrtc_conn.session_description_created.connect(_on_sdo_created)
	webrtc_conn.ice_candidate_created.connect(_on_ice_candidate)

	if is_host:
		# If we are host of a private game, create_server is already called in start_host
		# If we are host of a public game, create_server is already called in room_created
		var err = webrtc_mp.add_peer(webrtc_conn, 2) # Client is peer 2
		if err != OK: push_error("Host add_peer failed: ", err)
		webrtc_conn.create_offer()
	else:
		webrtc_mp.create_client(2)
		var err = webrtc_mp.add_peer(webrtc_conn, 1) # Server is peer 1
		if err != OK: push_error("Client add_peer failed: ", err)

	if multiplayer.multiplayer_peer != webrtc_mp:
		multiplayer.multiplayer_peer = webrtc_mp
	match_ready.emit()

	# match_ready only means signaling/offer setup is done locally — it says
	# nothing about whether the P2P transport actually connects (that's
	# exactly what a missing TURN server used to break silently). Give it
	# HANDSHAKE_TIMEOUT_SEC to report a real peer_connected/connected_to_server
	# before giving up and surfacing a failure instead of hanging forever.
	# Captures the specific webrtc_conn instance for this attempt so a stale
	# timer left over from a cancelled-then-retried attempt can never fire
	# against a *different*, newer attempt (compares identity, not nullness).
	_handshake_confirmed = false
	var conn_ref := webrtc_conn
	get_tree().create_timer(HANDSHAKE_TIMEOUT_SEC).timeout.connect(func(): _on_handshake_timeout(conn_ref))

func _on_handshake_confirmed(_id = null) -> void:
	_handshake_confirmed = true

func _on_handshake_timeout(conn_ref: WebRTCPeerConnection) -> void:
	if _handshake_confirmed or webrtc_conn != conn_ref:
		return # this attempt already succeeded, or a newer attempt replaced it
	_debug_log_socket_event("HANDSHAKE_TIMEOUT", "no peer_connected/connected_to_server within %.0fs" % HANDSHAKE_TIMEOUT_SEC)
	stop()
	connection_timed_out.emit()

func _on_sdo_created(type: String, sdp: String):
	webrtc_conn.set_local_description(type, sdp)
	var data = {"type": "sdp", "sdp": sdp, "sdp_type": type}
	ws.put_packet(JSON.stringify({"type": "webrtc_signal", "data": data}).to_utf8_buffer())
	# TEMP DEBUG: SDP body elided (large/noisy), only the kind is logged.
	_debug_log_socket_event("MESSAGE_SENT", "webrtc_signal/sdp sdp_type=%s" % type)
	PacketTrace.sent("webrtc_signal/sdp", "CLIENT", "RELAY (-> remote peer)", "sdp_type=%s (body elided)" % type, "remote peer's _handle_signal") # TEMP DEBUG

func _on_ice_candidate(media: String, index: int, name: String):
	var data = {"type": "ice", "media": media, "index": index, "name": name}
	ws.put_packet(JSON.stringify({"type": "webrtc_signal", "data": data}).to_utf8_buffer())
	_debug_log_socket_event("MESSAGE_SENT", "webrtc_signal/ice media=%s index=%d" % [media, index]) # TEMP DEBUG
	PacketTrace.sent("webrtc_signal/ice", "CLIENT", "RELAY (-> remote peer)", "media=%s index=%d" % [media, index], "remote peer's _handle_signal") # TEMP DEBUG

func _handle_signal(data: Dictionary):
	if data.type == "sdp":
		webrtc_conn.set_remote_description(data.sdp_type, data.sdp)
		PacketTrace.received("webrtc_signal/sdp", "remote peer (via RELAY)", "CLIENT", "sdp_type=%s (body elided)" % str(data.sdp_type), "_handle_signal/sdp", "_handle_signal/sdp (handled)") # TEMP DEBUG
	elif data.type == "ice":
		webrtc_conn.add_ice_candidate(data.media, data.index, data.name)
		PacketTrace.received("webrtc_signal/ice", "remote peer (via RELAY)", "CLIENT", "media=%s index=%s" % [str(data.media), str(data.index)], "_handle_signal/ice", "_handle_signal/ice (handled)") # TEMP DEBUG
	else:
		# TEMP DEBUG: a webrtc_signal envelope with a data.type this client
		# never sends and has no case for — never observed in testing, but
		# nothing previously would have reported it if the relay (or a
		# future protocol change) ever produced one.
		PacketTrace.received(str(data.get("type", "?")), "remote peer (via RELAY)", "CLIENT", JSON.stringify(data).left(200), "(none — no matching branch in _handle_signal)", "UNHANDLED — no case matches this sub-type")
