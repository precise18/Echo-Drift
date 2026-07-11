extends Node
## TEMPORARY test driver — verifies host+join, round start, and the new
## Minimap wiring end-to-end (see TEST_PLAN.md Level 3). Delete this file
## and its [autoload] entry in project.godot before committing.

const CODE_FILE := "user://__test_room_code.txt"

var _elapsed := 0.0
var _last_report := -1.0
var _started_match := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--host-test" in args:
		_run_host()
	elif "--join-test" in args:
		_run_join()


func _run_host() -> void:
	var abs_path := ProjectSettings.globalize_path(CODE_FILE)
	if FileAccess.file_exists(CODE_FILE):
		DirAccess.remove_absolute(abs_path)
	get_node("/root/WebRTCSignaler").room_created.connect(func(code: String) -> void:
		print("TESTDRIVER_HOST: room_created code=%s" % code)
		var f := FileAccess.open(CODE_FILE, FileAccess.WRITE)
		f.store_string(code)
		f.close()
	)
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		print("TESTDRIVER_HOST: calling host_game()")
		NetworkManager.host_game()
	)


func _run_join() -> void:
	var code := ""
	while code == "":
		if FileAccess.file_exists(CODE_FILE):
			var f := FileAccess.open(CODE_FILE, FileAccess.READ)
			code = f.get_as_text().strip_edges()
			f.close()
		if code == "":
			await get_tree().create_timer(0.5).timeout
	print("TESTDRIVER_JOIN: found code=%s, joining" % code)
	NetworkManager.join_game(code)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed - _last_report >= 2.0:
		_last_report = _elapsed
		_report()
	if _elapsed > 25.0:
		print("TESTDRIVER_DONE")
		get_tree().quit(0)


func _report() -> void:
	var minimap_state := "no-hud"
	var main := get_tree().current_scene
	if main != null and main.has_node("HUD"):
		var hud = main.get_node("HUD")
		if "minimap" in hud and hud.minimap != null:
			minimap_state = "obstacles=%d local_player=%s echo_ghost=%s" % [
				hud.minimap._obstacle_blips.size(),
				str(hud.minimap.local_player),
				str(hud.minimap.echo_ghost),
			]
		else:
			minimap_state = "hud-present-no-minimap"
	print("TESTDRIVER_STATE t=%.1f phase=%s round_active=%s hider=%s hunter=%s peers=%s minimap=[%s]" % [
		_elapsed, MatchStateManager.phase, RoundManager.round_active,
		RoundManager.hider_id, RoundManager.hunter_id,
		str(NetworkManager.connected_peer_ids), minimap_state])

	if multiplayer.multiplayer_peer != null and multiplayer.is_server() and not _started_match \
			and NetworkManager.connected_peer_ids.size() >= 2:
		_started_match = true
		print("TESTDRIVER_HOST: starting match")
		RoundManager.start_match()
