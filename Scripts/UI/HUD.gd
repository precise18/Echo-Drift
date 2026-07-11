extends CanvasLayer
## The whole in-game interface, built from UIKit pieces: the top status
## bar (role / timer / score), the warm-up lobby panel, the round-start
## banner, the between-rounds transition, the game-over screen, and the
## pause menu. One rule keeps the mouse sane: whenever any interactive
## overlay is open (lobby, pause, game over) the cursor is visible and
## PlayerController is blocked from re-capturing it; the moment none is,
## the mouse belongs to the camera again. See UI_GUIDE.md.

var _root: Control

# Top bar.
var _role_chip: Label
var _timer_label: Label

# Lobby.
var _lobby_panel: Control
var _lobby_players_label: Label
var _lobby_start_button: Button
var _lobby_kick_button: Button
var _lobby_waiting_label: Label
var _lobby_room_code_label: Label

# Round banner (fades on its own).
var _banner: VBoxContainer
var _banner_round: Label
var _banner_role: Label
var _banner_hint: Label
var _banner_tween: Tween

# Between-rounds transition.
var _round_end_panel: Control
var _round_end_headline: Label
var _round_end_detail: Label
var _round_end_countdown: Label
var _round_end_started_at := 0.0

# Game over.
var _game_over_panel: Control
var _game_over_headline: Label
var _game_over_headline_reflection: Label
var _game_over_detail: Label

# Pause.
var _pause_panel: Control
var _pause_main: VBoxContainer
var _pause_settings: VBoxContainer
var _paused := false

# Minimap. Public (unlike everything else here) so Main.gd can reach it
# directly as hud.minimap to wire up the map, echo ghost, and local player.
var minimap: Minimap

# Echo buffer indicator (Hider only): shows progress until the echo goes live.
var _echo_indicator: VBoxContainer
var _echo_bar: ProgressBar
var _echo_label: Label
var _echo_recorder: EchoRecorder = null

var _connection_status_label: Label
var _grace_deadline := -1.0

# Bottom-left echo-direction radar — see EchoMinimap.gd.
var _echo_minimap: EchoMinimap

# Per-frame _process work only rebuilds label strings when the displayed
# value actually changed — Label.text assignment isn't free (layout), and
# these run every frame for the whole session.
var _last_timer_second := -1
var _last_lobby_player_count := -1
var _last_countdown_value := -1
var _last_grace_second := -1


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UIKit.theme()
	add_child(_root)

	_build_top_bar()
	_build_lobby_panel()
	_build_banner()
	_build_round_end_panel()
	_build_game_over_panel()
	_build_pause_panel()
	_build_connection_status()
	_build_echo_minimap()
	_build_minimap()
	_build_echo_indicator()

	RoundManager.round_started.connect(_on_round_started)
	RoundManager.round_ended.connect(_on_round_ended)
	RoundManager.role_assigned.connect(_on_role_assigned)
	MatchStateManager.phase_changed.connect(_on_phase_changed)
	NetworkManager.reconnect_grace_started.connect(_on_reconnect_grace_started)
	NetworkManager.reconnect_grace_ended.connect(_on_reconnect_grace_ended)
	get_node("/root/WebRTCSignaler").room_created.connect(_on_room_created)
	# Otherwise silent for a host already sitting in the Lobby when a
	# joiner's WebRTC handshake times out — see UI_STATE_MACHINE.md
	# Finding 3. MainMenu's own connection_failed listener dies with its
	# node the moment the host's scene changes, so this is the only place
	# left that can tell the host a join attempt didn't work.
	NetworkManager.connection_failed.connect(_on_lobby_connection_failed)
	# Same gap, different signal: a joiner bailing during signaling (before
	# the WebRTC handshake even completed) previously had zero listeners
	# anywhere in the project — see PACKET_TRACE.md / UI_STATE_MACHINE.md.
	get_node("/root/WebRTCSignaler").disconnected.connect(_on_signaling_disconnected)

	_apply_phase(MatchStateManager.phase)
	_update_mouse()


func _process(_delta: float) -> void:
	if RoundManager.round_active:
		var whole_seconds := int(ceil(RoundManager.time_left))
		if whole_seconds != _last_timer_second:
			_last_timer_second = whole_seconds
			_timer_label.text = "%02d:%02d" % [whole_seconds / 60, whole_seconds % 60]
			# The clock turns gold when the hider is close to winning.
			_timer_label.add_theme_color_override("font_color",
				UIKit.COLOR_GOLD if whole_seconds <= 15 else UIKit.COLOR_TEXT)
	elif MatchStateManager.is_in_lobby() and _last_timer_second != -1:
		_last_timer_second = -1
		_timer_label.text = "--:--"

	if _lobby_panel.visible:
		_refresh_lobby()

	if _round_end_panel.visible:
		var remaining := maxi(ceili(RoundManager.NEXT_ROUND_DELAY - (Time.get_ticks_msec() / 1000.0 - _round_end_started_at)), 0)
		if remaining != _last_countdown_value:
			_last_countdown_value = remaining
			_round_end_countdown.text = "Next round in %d..." % remaining

	if _grace_deadline > 0.0:
		var remaining := ceili(maxf(_grace_deadline - Time.get_ticks_msec() / 1000.0, 0.0))
		if remaining != _last_grace_second:
			_last_grace_second = remaining
			_connection_status_label.text = "Opponent disconnected — waiting %ds to reconnect..." % remaining

	_update_echo_indicator()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_focus_next") and MatchStateManager.is_in_lobby():
		_lobby_panel.visible = not _lobby_panel.visible
		_update_mouse()
		return
		
	if not event.is_action_pressed("ui_cancel"):
		return
	# Game over demands a decision (Rematch / Leave); ESC won't dismiss it.
	if _game_over_panel.visible:
		return
	AudioManager.play_click()
	if _paused and _pause_settings.visible:
		_show_pause_page(_pause_main) # back out of settings first
		return
	_set_paused(not _paused)


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

func _build_top_bar() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(margin)

	var bar := HBoxContainer.new()
	bar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(bar)

	_role_chip = UIKit.make_label("", 19)
	_role_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_role_chip)

	_timer_label = UIKit.make_label("--:--", 30)
	_timer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_timer_label)

	var score := Scoreboard.new()
	score.add_theme_font_size_override("font_size", 19)
	score.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(score)


func _build_lobby_panel() -> void:
	var panel := UIKit.make_panel()
	_lobby_panel = panel["root"]
	var content: VBoxContainer = panel["content"]

	content.add_child(UIKit.make_title("WARM-UP LOBBY", 28))
	content.add_child(UIKit.make_title(MapManager.get_map_name(MapManager.selected_map_id), 16, UIKit.COLOR_GOLD))
	_lobby_players_label = UIKit.make_title("Players: 1 / 2", 16)
	content.add_child(_lobby_players_label)
	content.add_child(UIKit.make_paragraph("First to %d round wins takes the match.\nRoles swap every round — everyone hides, everyone hunts." % MatchStateManager.ROUNDS_TO_WIN, 14))

	_lobby_room_code_label = UIKit.make_title("", 18, UIKit.COLOR_GOLD)
	content.add_child(_lobby_room_code_label)
	
	var tab_hint := UIKit.make_paragraph("Press [TAB] to hide this menu and practice driving.", 13)
	tab_hint.add_theme_color_override("font_color", UIKit.COLOR_MUTED)
	content.add_child(tab_hint)

	_lobby_start_button = UIKit.make_button("Start Match")
	_lobby_start_button.pressed.connect(func() -> void: RoundManager.start_match())
	content.add_child(_lobby_start_button)
	
	_lobby_kick_button = UIKit.make_button("Kick Player")
	_lobby_kick_button.pressed.connect(func() -> void:
		if NetworkManager.connected_peer_ids.size() > 1:
			NetworkManager.kick_peer(NetworkManager.connected_peer_ids[1])
	)
	content.add_child(_lobby_kick_button)

	_lobby_waiting_label = UIKit.make_title("", 14, UIKit.COLOR_MUTED)
	content.add_child(_lobby_waiting_label)
	_root.add_child(_lobby_panel)


func _build_banner() -> void:
	_banner = VBoxContainer.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_top = 120
	_banner.offset_left = -400
	_banner.offset_right = 400
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false

	_banner_round = UIKit.make_title("", 24, UIKit.COLOR_MUTED)
	_banner_role = UIKit.make_title("", 44)
	_banner_hint = UIKit.make_title("", 16, UIKit.COLOR_TEXT)
	for label in [_banner_round, _banner_role, _banner_hint]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_banner.add_child(label)
	_root.add_child(_banner)


func _build_round_end_panel() -> void:
	var panel := UIKit.make_panel()
	_round_end_panel = panel["root"]
	var content: VBoxContainer = panel["content"]

	_round_end_headline = UIKit.make_title("", 32)
	content.add_child(_round_end_headline)
	_round_end_detail = UIKit.make_title("", 16)
	content.add_child(_round_end_detail)
	_round_end_countdown = UIKit.make_title("", 15, UIKit.COLOR_MUTED)
	content.add_child(_round_end_countdown)

	_round_end_panel.visible = false
	_root.add_child(_round_end_panel)


func _build_game_over_panel() -> void:
	var panel := UIKit.make_panel()
	_game_over_panel = panel["root"]
	var content: VBoxContainer = panel["content"]

	content.add_child(UIKit.make_title("MATCH OVER", 18, UIKit.COLOR_MUTED))
	_game_over_headline = UIKit.make_title("", 46)
	content.add_child(_game_over_headline)
	# A faint mirrored echo of VICTORY/DEFEAT — same "reflection" language
	# as the title screen (UIKit.make_reflected_title), applied here as
	# two separately-tracked labels instead of that all-in-one helper
	# because this headline's text/color change at runtime (see
	# _show_game_over below), not just once at construction.
	_game_over_headline_reflection = UIKit.make_reflection_label(UIKit.make_title("", 46))
	content.add_child(_game_over_headline_reflection)
	_game_over_detail = UIKit.make_title("", 17)
	content.add_child(_game_over_detail)

	var rematch := UIKit.make_button("Rematch")
	rematch.pressed.connect(func() -> void: RoundManager.request_rematch())
	content.add_child(rematch)
	var leave := UIKit.make_button("Leave to Menu")
	leave.pressed.connect(func() -> void: NetworkManager.leave_game())
	content.add_child(leave)

	_game_over_panel.visible = false
	_root.add_child(_game_over_panel)


func _build_pause_panel() -> void:
	_pause_panel = Control.new()
	_pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_panel.visible = false

	# Dim the game behind the menu; also swallows clicks so nothing under
	# it can be pressed through the pause screen.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_panel.add_child(dim)

	var panel := UIKit.make_panel()
	_pause_panel.add_child(panel["root"])
	var content: VBoxContainer = panel["content"]

	_pause_main = VBoxContainer.new()
	_pause_main.add_theme_constant_override("separation", 12)
	_pause_main.add_child(UIKit.make_title("PAUSED", 32))
	_pause_main.add_child(UIKit.make_paragraph("The match keeps running while this menu is open —\nthis is a two-player game, not a time-out.", 13))
	var resume := UIKit.make_button("Resume")
	resume.pressed.connect(func() -> void: _set_paused(false))
	_pause_main.add_child(resume)
	var settings := UIKit.make_button("Settings")
	settings.pressed.connect(func() -> void: _show_pause_page(_pause_settings))
	_pause_main.add_child(settings)
	var leave := UIKit.make_button("Leave Match")
	leave.pressed.connect(func() -> void: NetworkManager.leave_game())
	_pause_main.add_child(leave)
	var quit := UIKit.make_button("Quit Game")
	quit.pressed.connect(func() -> void: get_tree().quit())
	_pause_main.add_child(quit)
	content.add_child(_pause_main)

	_pause_settings = VBoxContainer.new()
	_pause_settings.add_theme_constant_override("separation", 12)
	_pause_settings.add_child(UIKit.make_title("SETTINGS", 32))
	_pause_settings.add_child(SettingsPanel.new())
	var back := UIKit.make_button("Back")
	back.pressed.connect(func() -> void: _show_pause_page(_pause_main))
	_pause_settings.add_child(back)
	_pause_settings.visible = false
	content.add_child(_pause_settings)

	_root.add_child(_pause_panel)


func _build_connection_status() -> void:
	_connection_status_label = UIKit.make_title("", 17, UIKit.COLOR_GOLD)
	_connection_status_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_connection_status_label.offset_top = 64
	_connection_status_label.offset_left = -300
	_connection_status_label.offset_right = 300
	_connection_status_label.visible = false
	_root.add_child(_connection_status_label)


## Bottom-left echo radar — see EchoMinimap.gd. Sized from the widget's
## own RADIUS constant so this stays correct if that changes.
func _build_echo_minimap() -> void:
	_echo_minimap = EchoMinimap.new()
	_echo_minimap.main_root = get_parent()
	var diameter := EchoMinimap.RADIUS * 2.0
	_echo_minimap.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_echo_minimap.offset_left = 24
	_echo_minimap.offset_right = 24 + diameter
	_echo_minimap.offset_top = -(24 + diameter)
	_echo_minimap.offset_bottom = -24
	_root.add_child(_echo_minimap)


func _build_minimap() -> void:
	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(170, 170)
	minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	minimap.offset_left = -190
	minimap.offset_top = -190
	minimap.offset_right = -20
	minimap.offset_bottom = -20
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(minimap)


func _build_echo_indicator() -> void:
	_echo_indicator = VBoxContainer.new()
	_echo_indicator.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_echo_indicator.offset_left  = -110
	_echo_indicator.offset_right =  110
	_echo_indicator.offset_top   = -72
	_echo_indicator.offset_bottom = -20
	_echo_indicator.add_theme_constant_override("separation", 4)
	_echo_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_echo_indicator.visible = false

	_echo_label = UIKit.make_label("Echo in 10s", 13, UIKit.COLOR_MUTED)
	_echo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_echo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_echo_indicator.add_child(_echo_label)

	_echo_bar = ProgressBar.new()
	_echo_bar.custom_minimum_size = Vector2(220, 6)
	_echo_bar.min_value = 0.0
	_echo_bar.max_value = 100.0
	_echo_bar.value = 0.0
	_echo_bar.show_percentage = false
	_echo_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = UIKit.COLOR_ACCENT
	bar_style.set_corner_radius_all(3)
	_echo_bar.add_theme_stylebox_override("fill", bar_style)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(UIKit.COLOR_PANEL.r, UIKit.COLOR_PANEL.g, UIKit.COLOR_PANEL.b, 0.8)
	bg_style.set_corner_radius_all(3)
	_echo_bar.add_theme_stylebox_override("background", bg_style)
	_echo_indicator.add_child(_echo_bar)

	_root.add_child(_echo_indicator)


func set_echo_recorder(recorder: EchoRecorder) -> void:
	_echo_recorder = recorder


func _update_echo_indicator() -> void:
	if not RoundManager.round_active or _local_role() != Role.HIDER or _echo_recorder == null:
		_echo_indicator.visible = false
		return

	_echo_indicator.visible = true
	var fill := _echo_recorder.buffer_fill_ratio()
	_echo_bar.value = fill * 100.0

	if fill >= 1.0:
		_echo_label.text = "Echo is live"
		_echo_label.add_theme_color_override("font_color", UIKit.COLOR_ACCENT)
	else:
		var secs_left := ceili(_echo_recorder.buffer_seconds * (1.0 - fill))
		_echo_label.text = "Echo in %ds" % secs_left
		_echo_label.add_theme_color_override("font_color", UIKit.COLOR_MUTED)


# ---------------------------------------------------------------------------
# State changes
# ---------------------------------------------------------------------------

func _on_round_started() -> void:
	_round_end_panel.visible = false
	_game_over_panel.visible = false
	_lobby_panel.visible = false
	_update_mouse()
	_show_round_banner()


func _on_round_ended(winner_role: int) -> void:
	var local_won := _local_role() == winner_role
	if MatchStateManager.is_match_over():
		_show_game_over(winner_role, local_won)
		return

	_round_end_headline.text = "Round won!" if local_won else "Round lost"
	_round_end_headline.add_theme_color_override("font_color",
		UIKit.COLOR_GOLD if local_won else UIKit.COLOR_MUTED)
	var winner_name := "Hunter" if winner_role == Role.HUNTER else "Hider"
	var how := "the echoes gave the hider away" if winner_role == Role.HUNTER else "time ran out before the hunter closed in"
	_round_end_detail.text = "%s takes round %d — %s.\nScore: Hunter %d — %d Hider" % [
		winner_name, MatchStateManager.round_number() - 1, how,
		MatchStateManager.hunter_score, MatchStateManager.hider_score]
	_round_end_started_at = Time.get_ticks_msec() / 1000.0
	_last_countdown_value = -1
	_round_end_panel.visible = true


func _show_game_over(winner_role: int, local_won: bool) -> void:
	_round_end_panel.visible = false
	_game_over_headline.text = "VICTORY" if local_won else "DEFEAT"
	var headline_color := UIKit.COLOR_GOLD if local_won else UIKit.COLOR_MUTED
	_game_over_headline.add_theme_color_override("font_color", headline_color)
	# Keep the mirrored echo beneath it in lockstep — see
	# _build_game_over_panel()'s doc comment for why this is two labels
	# kept in sync by hand rather than one reusable widget.
	_game_over_headline_reflection.text = _game_over_headline.text
	_game_over_headline_reflection.add_theme_color_override("font_color", headline_color)
	var winner_name := "The Hunter" if winner_role == Role.HUNTER else "The Hider"
	_game_over_detail.text = "%s takes the match\nFinal score: Hunter %d — %d Hider" % [
		winner_name, MatchStateManager.hunter_score, MatchStateManager.hider_score]
	_game_over_panel.visible = true
	_set_paused(false)
	_update_mouse()


func _on_role_assigned(peer_id: int, role: int) -> void:
	if peer_id != multiplayer.get_unique_id():
		return
	if role == Role.HIDER:
		_role_chip.text = "HIDER"
		_role_chip.add_theme_color_override("font_color", UIKit.COLOR_HIDER)
	else:
		_role_chip.text = "HUNTER"
		_role_chip.add_theme_color_override("font_color", UIKit.COLOR_HUNTER)


# `phase` is a MatchStateManager.MatchPhase value; typed as int because
# an autoload's enum isn't usable as a static type annotation.
func _on_phase_changed(new_phase: int) -> void:
	_apply_phase(new_phase)


func _apply_phase(phase: int) -> void:
	var in_lobby: bool = phase == MatchStateManager.MatchPhase.LOBBY
	_lobby_panel.visible = in_lobby
	if in_lobby:
		_last_lobby_player_count = -1 # force a fresh refresh on re-entry
		_round_end_panel.visible = false
		_game_over_panel.visible = false
		_role_chip.text = ""
	_update_mouse()


func _refresh_lobby() -> void:
	var player_count := NetworkManager.connected_peer_ids.size()
	if player_count == _last_lobby_player_count:
		return
	_last_lobby_player_count = player_count
	_lobby_players_label.text = "Players: %d / 2" % player_count
	var code = get_node("/root/WebRTCSignaler").current_room_code
	_lobby_room_code_label.text = ("Room Code: " + code) if code != "" else ""

	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_lobby_start_button.visible = true
		_lobby_start_button.disabled = player_count < 2
		_lobby_kick_button.visible = player_count >= 2
		var wait_msg = "Waiting for a second player to join..."
		_lobby_waiting_label.text = wait_msg if player_count < 2 else "Ready when you are."
	else:
		_lobby_start_button.visible = false
		_lobby_kick_button.visible = false
		_lobby_waiting_label.text = "Waiting for the host to start the match..."

func _on_room_created(_code: String) -> void:
	_last_lobby_player_count = -1
	if _lobby_panel.visible:
		_refresh_lobby()

func _show_round_banner() -> void:
	_banner_round.text = "ROUND %d" % MatchStateManager.round_number()
	var is_hider := _local_role() == Role.HIDER
	_banner_role.text = "You are the %s" % ("HIDER" if is_hider else "HUNTER")
	_banner_role.add_theme_color_override("font_color",
		UIKit.COLOR_HIDER if is_hider else UIKit.COLOR_HUNTER)
	_banner_hint.text = ("Stay unseen. Your echo repeats your past — use it to mislead." if is_hider
		else "Track the echoes. Sound and ghost trails betray the hider.")

	if _banner_tween != null:
		_banner_tween.kill()
	_banner.modulate.a = 0.0
	_banner.visible = true
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.25)
	_banner_tween.tween_interval(2.4)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.6)
	_banner_tween.tween_callback(func() -> void: _banner.visible = false)


# ---------------------------------------------------------------------------
# Pause + mouse policy
# ---------------------------------------------------------------------------

func _set_paused(paused: bool) -> void:
	_paused = paused
	_pause_panel.visible = paused
	if not paused:
		_show_pause_page(_pause_main)
	_update_mouse()


func _show_pause_page(page: VBoxContainer) -> void:
	_pause_main.visible = page == _pause_main
	_pause_settings.visible = page == _pause_settings


## The single decision point for who owns the cursor. Any interactive
## overlay -> visible cursor and PlayerController blocked from grabbing
## it back on refocus; none -> captured for camera look.
func _update_mouse() -> void:
	var ui_open := _paused or _game_over_panel.visible or _lobby_panel.visible
	UIKit.block_mouse_capture = ui_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if ui_open else Input.MOUSE_MODE_CAPTURED


func _local_role() -> int:
	if multiplayer.multiplayer_peer == null:
		return Role.NONE
	return Role.HIDER if multiplayer.get_unique_id() == RoundManager.hider_id else Role.HUNTER


# ---------------------------------------------------------------------------
# Reconnect grace (unchanged behavior from before this UI pass)
# ---------------------------------------------------------------------------

func _on_reconnect_grace_started(_role: int) -> void:
	_grace_deadline = Time.get_ticks_msec() / 1000.0 + NetworkManager.RECONNECT_GRACE_PERIOD
	_last_grace_second = -1
	_connection_status_label.visible = true


## Covers both outcomes the same way on purpose: if they reconnected,
## role_assigned/round_started (from RoundManager's resync) already
## refresh the rest of the HUD; if the window expired, Main.gd's own
## listener already called RoundManager.reset_state(), which returns the
## HUD to the lobby. Either way this label just gets out of the way.
func _on_reconnect_grace_ended(_role: int, _reconnected: bool) -> void:
	_grace_deadline = -1.0
	_connection_status_label.visible = false


## Fires from NetworkManager.connection_failed, which now also covers a
## WebRTC handshake that timed out (see WebRTCSignaler.HANDSHAKE_TIMEOUT_SEC).
## Only relevant while still waiting in the Lobby for a second player —
## once a match is underway, a lost connection is the reconnect-grace
## path above instead, not a fresh join attempt failing.
func _on_lobby_connection_failed() -> void:
	if not MatchStateManager.is_in_lobby():
		return
	_show_transient_status("A connection attempt failed or timed out. Still waiting for a player...")


## Fires from WebRTCSignaler.disconnected when the other party's WebSocket
## signaling drops (e.g. a joiner cancels or crashes before the WebRTC
## handshake completes) — a different failure point than the timeout
## above, so it gets its own listener rather than being folded into it.
func _on_signaling_disconnected() -> void:
	if not MatchStateManager.is_in_lobby():
		return
	_show_transient_status("The other player disconnected before the match could start. Still waiting for a player...")


func _show_transient_status(message: String) -> void:
	_connection_status_label.text = message
	_connection_status_label.visible = true
	get_tree().create_timer(6.0).timeout.connect(func() -> void:
		if _grace_deadline <= 0.0: # don't clobber an unrelated reconnect-grace message
			_connection_status_label.visible = false
	)
