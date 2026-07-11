extends Control
## The menu shell: a router over five screens — Title, Host (with map
## selection), Join, Settings, Credits — all built in code from UIKit
## pieces so every screen shares the same theme, spacing, and button
## feel. Only one screen is visible at a time; ESC returns to the title
## from anywhere. See UI_GUIDE.md.

var _screens: Dictionary = {}
var _current_screen := ""

# Title screen notice (e.g. "Host disconnected." after being dropped).
var _notice_label: Label
var _server_stats_label: Label

# Host screen state.
var _selected_map_id: String = MapManager.DEFAULT_MAP_ID
var _map_description: Label

# Join screen state.
var _ip_field: LineEdit
var _join_button: Button
var _join_status: Label
var _room_code_label: Label


func _ready() -> void:
	theme = UIKit.theme()
	# Arriving here from a game (leave/disconnect) with the mouse still
	# captured would leave the menu unclickable.
	UIKit.block_mouse_capture = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var background := ColorRect.new()
	background.color = UIKit.COLOR_BACKGROUND
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	_screens["title"] = _build_title_screen()
	_screens["host"] = _build_host_screen()
	_screens["join"] = _build_join_screen()
	_screens["browser"] = _build_browser_screen()
	_screens["settings"] = _build_settings_screen()
	_screens["credits"] = _build_credits_screen()
	for screen: Control in _screens.values():
		add_child(screen)
	_show_screen("title")

	NetworkManager.connection_failed.connect(_on_connection_failed)
	get_node("/root/WebRTCSignaler").room_created.connect(_on_room_created)

	# Explains why the player landed back here instead of silently
	# dumping them at the menu — e.g. after the host disconnected. This
	# is the practical stand-in for host migration: no seamless handoff,
	# but a clear reason plus an immediate one-click path to a fresh
	# session (see NETWORKING_REPORT.md).
	if NetworkManager.last_disconnect_reason != "":
		_notice_label.text = NetworkManager.last_disconnect_reason
		NetworkManager.last_disconnect_reason = ""


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _current_screen != "title":
		AudioManager.play_click()
		_show_screen("title")


func _show_screen(name: String) -> void:
	_current_screen = name
	for key: String in _screens:
		_screens[key].visible = key == name


# ---------------------------------------------------------------------------
# Screens
# ---------------------------------------------------------------------------

func _build_title_screen() -> Control:
	var root := CenterContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(vbox)

	vbox.add_child(UIKit.make_title("ECHO HUNT", 58))
	vbox.add_child(UIKit.make_paragraph("Every move you make becomes a living echo.\nHunt by sound and ghost trails — or use your own past to deceive.", 15))
	vbox.add_child(_spacer(18))

	var buttons := {
		"Quick Play (Public)": func() -> void: _on_quick_play_pressed(),
		"Server Browser": func() -> void: _show_screen("browser"),
		"Host Private Game": func() -> void: _show_screen("host"),
		"Join Private Game": func() -> void: _show_screen("join"),
		"Settings": func() -> void: _show_screen("settings"),
		"Credits": func() -> void: _show_screen("credits"),
	}
	for label: String in buttons:
		var button := UIKit.make_button(label)
		button.pressed.connect(buttons[label])
		vbox.add_child(button)

	var quit := UIKit.make_button("Quit")
	quit.pressed.connect(func() -> void: get_tree().quit())
	vbox.add_child(quit)

	vbox.add_child(_spacer(10))
	vbox.add_child(UIKit.make_title("Preferred Role", 14, UIKit.COLOR_MUTED))
	var role_group := ButtonGroup.new()
	var role_hbox := HBoxContainer.new()
	role_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	role_hbox.add_theme_constant_override("separation", 10)
	
	var roles = ["Any", "Hider", "Hunter"]
	for i in range(roles.size()):
		var btn := UIKit.make_button(roles[i])
		btn.toggle_mode = true
		btn.button_group = role_group
		btn.button_pressed = (GameSettings.preferred_role == i)
		btn.pressed.connect(func(): GameSettings.set_preferred_role(i))
		role_hbox.add_child(btn)
	vbox.add_child(role_hbox)

	vbox.add_child(_spacer(10))
	_notice_label = UIKit.make_title("", 15, UIKit.COLOR_GOLD)
	vbox.add_child(_notice_label)
	
	_server_stats_label = UIKit.make_title("Server Stats: Connecting...", 13, UIKit.COLOR_MUTED)
	vbox.add_child(_server_stats_label)
	
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var data = JSON.parse_string(body.get_string_from_utf8())
			if data and typeof(data) == TYPE_DICTIONARY:
				_server_stats_label.text = "Public Server: %d Active Matches | %d Players Waiting" % [data.get("active_matches", 0), data.get("waiting_players", 0)]
			else:
				_server_stats_label.text = "Public Server: Online"
		else:
			_server_stats_label.text = "Public Server: Offline"
		http.queue_free()
	)
	http.request(get_node("/root/WebRTCSignaler").server_url.replace("wss://", "https://").replace("ws://", "http://") + "/api/stats")

	var sig = get_node("/root/WebRTCSignaler")
	if not sig.room_error.is_connected(_on_room_error):
		sig.room_error.connect(_on_room_error)

	vbox.add_child(UIKit.make_title("Global Multiplayer  •  built with Godot", 12, UIKit.COLOR_MUTED))
	return root

func _on_room_error(msg: String) -> void:
	_notice_label.text = "Error: " + msg
	_show_screen("title")


func _build_host_screen() -> Control:
	var screen := _build_dialog_screen("HOST A MATCH")
	var content: VBoxContainer = screen["content"]

	content.add_child(UIKit.make_title("Choose the arena", 15, UIKit.COLOR_MUTED))

	# Radio-style map list driven entirely by MapManager's registry — a
	# future map appears here with no menu changes.
	var group := ButtonGroup.new()
	for map_id: String in MapManager.get_map_ids():
		var map_button := UIKit.make_button(MapManager.get_map_name(map_id))
		map_button.toggle_mode = true
		map_button.button_group = group
		map_button.button_pressed = map_id == _selected_map_id
		map_button.pressed.connect(func() -> void:
			_selected_map_id = map_id
			_map_description.text = MapManager.get_map_description(map_id))
		content.add_child(map_button)

	_map_description = UIKit.make_paragraph(MapManager.get_map_description(_selected_map_id), 14)
	content.add_child(_map_description)
	content.add_child(_spacer(6))
	content.add_child(UIKit.make_title("Your opponent joins with the Room Code", 13, UIKit.COLOR_MUTED))
	
	_room_code_label = UIKit.make_title("", 24, UIKit.COLOR_GOLD)
	content.add_child(_room_code_label)

	var start := UIKit.make_button("Start Hosting")
	start.pressed.connect(_on_start_hosting_pressed)
	content.add_child(start)
	content.add_child(_make_back_button())
	return screen["root"]


func _build_join_screen() -> Control:
	var screen := _build_dialog_screen("JOIN A MATCH")
	var content: VBoxContainer = screen["content"]

	content.add_child(UIKit.make_title("Enter the Room Code", 15, UIKit.COLOR_MUTED))

	_ip_field = LineEdit.new()
	_ip_field.text = GameSettings.last_join_code
	_ip_field.placeholder_text = "e.g. ABCD"
	_ip_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ip_field.custom_minimum_size = Vector2(280, 44)
	_ip_field.text_submitted.connect(func(_text: String) -> void: _on_join_pressed())
	_ip_field.text_changed.connect(func(new_text: String) -> void:
		_ip_field.text = new_text.to_upper()
		_ip_field.caret_column = _ip_field.text.length()
	)
	_ip_field.visibility_changed.connect(func() -> void:
		if _ip_field.is_visible_in_tree():
			_ip_field.grab_focus()
	)
	content.add_child(_ip_field)

	_join_button = UIKit.make_button("Join")
	_join_button.pressed.connect(_on_join_pressed)
	content.add_child(_join_button)

	_join_status = UIKit.make_title("", 14, UIKit.COLOR_GOLD)
	content.add_child(_join_status)
	content.add_child(_make_back_button())
	return screen["root"]

var _browser_list: VBoxContainer

func _build_browser_screen() -> Control:
	var screen := _build_dialog_screen("PUBLIC SERVERS")
	var content: VBoxContainer = screen["content"]
	
	_browser_list = VBoxContainer.new()
	_browser_list.add_theme_constant_override("separation", 8)
	content.add_child(_browser_list)

	var refresh := UIKit.make_button("Refresh")
	refresh.pressed.connect(_refresh_browser)
	content.add_child(refresh)

	content.add_child(_make_back_button())
	return screen["root"]

func _refresh_browser() -> void:
	for child in _browser_list.get_children():
		child.queue_free()
	_browser_list.add_child(UIKit.make_title("Searching...", 16, UIKit.COLOR_MUTED))
	
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
		for child in _browser_list.get_children():
			child.queue_free()
		
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var data = JSON.parse_string(body.get_string_from_utf8())
			if data and typeof(data) == TYPE_ARRAY:
				if data.is_empty():
					_browser_list.add_child(UIKit.make_title("No public servers found.", 16, UIKit.COLOR_MUTED))
				else:
					for room in data:
						var btn := UIKit.make_button("Join Room: " + room.get("code", "Unknown"))
						btn.pressed.connect(func():
							_show_screen("title")
							_notice_label.text = "Connecting..."
							NetworkManager.join_game(room.get("code", ""))
						)
						_browser_list.add_child(btn)
			else:
				_browser_list.add_child(UIKit.make_title("Failed to parse rooms.", 16, UIKit.COLOR_MUTED))
		else:
			_browser_list.add_child(UIKit.make_title("Cannot reach server.", 16, UIKit.COLOR_MUTED))
		http.queue_free()
	)
	http.request(get_node("/root/WebRTCSignaler").server_url.replace("wss://", "https://").replace("ws://", "http://") + "/api/rooms")


func _build_settings_screen() -> Control:
	var screen := _build_dialog_screen("SETTINGS")
	var content: VBoxContainer = screen["content"]
	content.add_child(SettingsPanel.new())
	content.add_child(_spacer(6))
	content.add_child(_make_back_button())
	return screen["root"]


func _build_credits_screen() -> Control:
	var screen := _build_dialog_screen("CREDITS")
	var content: VBoxContainer = screen["content"]
	content.add_child(UIKit.make_paragraph("Echo Hunt — a 3D multiplayer hide-and-seek game where every player's past movements become living echoes.", 15, UIKit.COLOR_TEXT))
	content.add_child(_spacer(4))
	content.add_child(UIKit.make_title("ENVIRONMENT PROPS", 13, UIKit.COLOR_ACCENT))
	content.add_child(UIKit.make_paragraph("\"Nature Kit\" by Kenney (kenney.nl) — CC0, via OpenGameArt.org", 14))
	content.add_child(UIKit.make_title("AUDIO", 13, UIKit.COLOR_ACCENT))
	content.add_child(UIKit.make_paragraph("All music and sound effects are synthesized at runtime — no recorded assets.", 14))
	content.add_child(UIKit.make_title("MADE WITH", 13, UIKit.COLOR_ACCENT))
	content.add_child(UIKit.make_paragraph("Godot Engine 4 — godotengine.org", 14))
	content.add_child(_spacer(4))
	content.add_child(_make_back_button())
	return screen["root"]


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

func _on_start_hosting_pressed() -> void:
	MapManager.set_selected_map(_selected_map_id)
	_room_code_label.text = "Generating code..."
	var err := NetworkManager.host_game()
	if err != OK:
		_notice_label.text = "Could not host (error %d)." % err
		_show_screen("title")

func _on_quick_play_pressed() -> void:
	_notice_label.text = "Searching for public match..."
	var err := NetworkManager.quick_play()
	if err != OK:
		_notice_label.text = "Quick Play failed (error %d)." % err

func _on_room_created(code: String) -> void:
	DisplayServer.clipboard_set(code)
	_room_code_label.text = "Room Code: " + code + "\n(Copied to clipboard!)\nWaiting for opponent..."


func _on_join_pressed() -> void:
	var address := _ip_field.text.strip_edges().to_upper()
	GameSettings.set_last_join_code(address)
	_join_status.text = "Connecting to room %s..." % address
	_join_button.disabled = true
	var err := NetworkManager.join_game(address)
	if err != OK:
		_join_status.text = "Could not start connecting (error %d)." % err
		_join_button.disabled = false


func _on_connection_failed() -> void:
	_join_status.text = "Connection failed. Check the IP and that the host is running."
	_join_button.disabled = false


# ---------------------------------------------------------------------------
# Shared pieces
# ---------------------------------------------------------------------------

## Every non-title screen is the same shape: a centered themed panel with
## a heading and a content column.
func _build_dialog_screen(title: String) -> Dictionary:
	var panel := UIKit.make_panel(12)
	var content: VBoxContainer = panel["content"]
	content.add_child(UIKit.make_title(title, 30))
	content.add_child(_spacer(4))
	return {"root": panel["root"], "content": content}


func _make_back_button() -> Button:
	var back := UIKit.make_button("Back")
	back.pressed.connect(func() -> void: _show_screen("title"))
	return back


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer
