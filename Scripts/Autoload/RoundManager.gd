extends Node
## Autoload: orchestrates a single round's lifecycle — role assignment,
## the countdown, win-condition checks, and restart — by delegating each
## concern to a focused module instead of doing it all inline:
##   - who hides/hunts next  -> RoleManager
##   - the countdown itself  -> RoundTimer
##   - "has someone won yet" -> WinConditions
##   - score / match phase   -> MatchStateManager
##
## Only the server (multiplayer.is_server()) ever *decides* outcomes; it
## then replicates state to every peer through RPCs so clients stay in
## sync. See GAMEPLAY_SYSTEMS.md for the full design writeup.

const ROUND_TIME := 90.0

signal role_assigned(peer_id: int, role: int) # role is a Role.* value
signal round_started
signal round_ended(winner_role: int) # winner_role is a Role.* value

var hider_id := -1
var hunter_id := -1
var round_active := false
var time_left := ROUND_TIME

# Server-only bookkeeping: which peer id should be Hider next round.
# -1 means "unset"; start_round() picks a default once peers are known.
var _next_hider_id := -1

# Set by Main.gd once the arena/players are in the tree.
var _players_container: Node = null

var _timer: RoundTimer


func _ready() -> void:
	_timer = RoundTimer.new()
	add_child(_timer)
	_timer.expired.connect(_on_timer_expired)


func register_players_container(container: Node) -> void:
	_players_container = container


func _on_timer_expired() -> void:
	# Every peer's local RoundTimer reaches zero at roughly the same
	# time (each counts down independently for smooth HUD display), but
	# only the server's expiry is authoritative for ending the round.
	if not multiplayer.is_server():
		return
	_end_round.rpc(Role.HIDER) # time ran out, hider survived


func _physics_process(_delta: float) -> void:
	time_left = _timer.time_left

	if not round_active or not multiplayer.is_server():
		return

	_check_for_capture()


func _check_for_capture() -> void:
	var hunter_node := _get_player_node(hunter_id)
	var hider_node := _get_player_node(hider_id)
	if hunter_node == null or hider_node == null:
		return
	if WinConditions.is_capture(hunter_node.global_position, hider_node.global_position):
		_end_round.rpc(Role.HUNTER)


func _get_player_node(peer_id: int) -> Node3D:
	if _players_container == null or peer_id < 0:
		return null
	var node_name := str(peer_id)
	if _players_container.has_node(node_name):
		return _players_container.get_node(node_name) as Node3D
	return null


## Called by Main.gd on the server once both players exist in the tree.
func start_round() -> void:
	if not multiplayer.is_server():
		return
	var roles := RoleManager.assign_roles(NetworkManager.connected_peer_ids, _next_hider_id)
	if roles.is_empty():
		return
	_apply_round_state.rpc(roles["hider_id"], roles["hunter_id"], ROUND_TIME)


@rpc("authority", "call_local", "reliable")
func _apply_round_state(new_hider_id: int, new_hunter_id: int, starting_time: float) -> void:
	hider_id = new_hider_id
	hunter_id = new_hunter_id
	_timer.start(starting_time)
	time_left = starting_time
	round_active = true
	MatchStateManager.begin_round()
	role_assigned.emit(hider_id, Role.HIDER)
	role_assigned.emit(hunter_id, Role.HUNTER)
	round_started.emit()


@rpc("authority", "call_local", "reliable")
func _end_round(winner_role: int) -> void:
	round_active = false
	_timer.stop()
	MatchStateManager.record_round_result(winner_role)
	round_ended.emit(winner_role)


## Called locally by HUD on any peer; forwards the request to the server.
func request_restart() -> void:
	_request_restart.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _request_restart() -> void:
	if not multiplayer.is_server():
		return
	# Alternate who hides next so both players experience both roles.
	_next_hider_id = hunter_id
	start_round()


## Clears all round state. Called whenever the multiplayer session ends
## (host lost, disconnected, or a peer left mid-round) so a fresh
## host/join cycle always starts from a known-good state instead of
## carrying over a stale round that can never resolve.
func reset_state() -> void:
	hider_id = -1
	hunter_id = -1
	round_active = false
	time_left = ROUND_TIME
	_next_hider_id = -1
	_timer.stop()
	MatchStateManager.reset()
	# _players_container is intentionally left as-is: the server may still
	# be running this same Main.tscn instance after just one peer left, and
	# that reference stays valid until the scene itself reloads.
