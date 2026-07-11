extends Node

signal room_created(code: String)
signal room_error(msg: String)
signal match_ready()
signal disconnected()

var ws: WebSocketPeer = null
var webrtc_mp: WebRTCMultiplayerPeer = null
var webrtc_conn: WebRTCPeerConnection = null

var is_host := false
var server_url := "wss://echo-relay.onrender.com"

var _pending_action := ""
var current_room_code := ""
var is_quick_play := false

func _ready():
	set_process(false)
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
			ws.put_packet(JSON.stringify({"type": "ping"}).to_utf8_buffer())
	)
	add_child(timer)

func _process(_delta):
	if ws != null:
		ws.poll()
		var state = ws.get_ready_state()
		
		if state == WebSocketPeer.STATE_OPEN:
			if _pending_action != "":
				ws.put_packet(_pending_action.to_utf8_buffer())
				_pending_action = ""
				
			while ws.get_available_packet_count() > 0:
				var packet = ws.get_packet().get_string_from_utf8()
				var msg = JSON.parse_string(packet)
				if msg:
					_handle_message(msg)
		elif state == WebSocketPeer.STATE_CLOSED:
			set_process(false)
			disconnected.emit()

	if webrtc_conn != null:
		webrtc_conn.poll()

func start_host():
	stop()
	ws = WebSocketPeer.new()
	webrtc_mp = WebRTCMultiplayerPeer.new()
	is_quick_play = false
	is_host = true
	webrtc_mp.create_server()
	multiplayer.multiplayer_peer = webrtc_mp
	_pending_action = JSON.stringify({"type": "create_room"})
	var err = ws.connect_to_url(server_url)
	if err == OK:
		set_process(true)

func start_client(room_code: String):
	stop()
	ws = WebSocketPeer.new()
	webrtc_mp = WebRTCMultiplayerPeer.new()
	is_quick_play = false
	is_host = false
	_pending_action = JSON.stringify({"type": "join_room", "room": room_code})
	var err = ws.connect_to_url(server_url)
	if err == OK:
		set_process(true)

func start_quick_play():
	stop()
	ws = WebSocketPeer.new()
	webrtc_mp = WebRTCMultiplayerPeer.new()
	is_quick_play = true
	is_host = false
	_pending_action = JSON.stringify({"type": "quick_play"})
	var err = ws.connect_to_url(server_url)
	if err == OK:
		set_process(true)

func stop():
	set_process(false)
	if ws != null:
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.put_packet(JSON.stringify({"type": "leave_room"}).to_utf8_buffer())
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
		if msg.get("is_public", false):
			is_host = true
			webrtc_mp.create_server()
			multiplayer.multiplayer_peer = webrtc_mp
			NetworkManager.enter_game_as_host()
		room_created.emit(msg.room)
	elif msg.type == "error":
		room_error.emit(msg.message)
	elif msg.type == "peer_connected":
		if msg.has("is_host"):
			is_host = msg.is_host
		_setup_webrtc()
	elif msg.type == "webrtc_signal":
		_handle_signal(msg.data)
	elif msg.type == "peer_disconnected":
		disconnected.emit()

func _setup_webrtc():
	webrtc_conn = WebRTCPeerConnection.new()
	var init_err = webrtc_conn.initialize({
		"iceServers": [ { "urls": ["stun:stun.l.google.com:19302"] } ]
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

func _on_sdo_created(type: String, sdp: String):
	webrtc_conn.set_local_description(type, sdp)
	var data = {"type": "sdp", "sdp": sdp, "sdp_type": type}
	ws.put_packet(JSON.stringify({"type": "webrtc_signal", "data": data}).to_utf8_buffer())

func _on_ice_candidate(media: String, index: int, name: String):
	var data = {"type": "ice", "media": media, "index": index, "name": name}
	ws.put_packet(JSON.stringify({"type": "webrtc_signal", "data": data}).to_utf8_buffer())

func _handle_signal(data: Dictionary):
	if data.type == "sdp":
		webrtc_conn.set_remote_description(data.sdp_type, data.sdp)
	elif data.type == "ice":
		webrtc_conn.add_ice_candidate(data.media, data.index, data.name)
