extends Node
## Autoload: authoritative round/score/role state.
## Only the server (multiplayer.is_server()) ever decides outcomes; it then
## replicates state to every peer through RPCs so clients stay in sync.

enum Role { NONE, HIDER, HUNTER }

const ROUND_TIME := 90.0
const HIDE_WARMUP := 10.0 # seconds before the echo ghost has enough data to appear
const TOUCH_RADIUS := 1.3 # meters; how close the hunter must get to win

signal role_assigned(peer_id: int, role: Role)
signal round_started
signal round_ended(winner_role: Role, hunter_score: int, hider_score: int)
signal timer_updated(time_left: float)

var hider_id := -1
var hunter_id := -1
var round_active := false
var time_left := ROUND_TIME
var hunter_score := 0
var hider_score := 0

# Server-only bookkeeping: which peer id should be Hider next round.
# -1 means "unset"; start_round() picks a default once peers are known.
var _next_hider_id := -1

# Set by Main.gd once the arena/players are in the tree.
var _players_container: Node = null


func register_players_container(container: Node) -> void:
	_players_container = container


func _physics_process(delta: float) -> void:
	if not round_active:
		return

	# Every peer counts down its own local copy for smooth HUD display;
	# only the server's copy is authoritative for deciding the outcome.
	time_left = maxf(time_left - delta, 0.0)

	if not multiplayer.is_server():
		return

	if time_left <= 0.0:
		_end_round.rpc(Role.HIDER) # time ran out, hider survived
		return

	_check_for_capture()


func _check_for_capture() -> void:
	if _players_container == null:
		return
	var hunter_node := _get_player_node(hunter_id)
	var hider_node := _get_player_node(hider_id)
	if hunter_node == null or hider_node == null:
		return
	var dist := hunter_node.global_position.distance_to(hider_node.global_position)
	if dist <= TOUCH_RADIUS:
		_end_round.rpc(Role.HUNTER)


func _get_player_node(peer_id: int) -> Node3D:
	if _players_container == null or peer_id < 0:
		return null
	var node_name := str(peer_id)
	if _players_container.has_node(node_name):
		return _players_container.get_node(node_name) as Node3D
	return null


## Called by Main.gd on the server once both players exist in the tree.
## Peer ids from ENet are arbitrary 32-bit numbers (not simply 1 and 2), so
## roles are derived from whoever is actually connected right now rather
## than assumed.
func start_round() -> void:
	if not multiplayer.is_server():
		return
	var ids := NetworkManager.connected_peer_ids.duplicate()
	if ids.size() < 2:
		return
	ids.sort()

	if not ids.has(_next_hider_id):
		_next_hider_id = ids[0]
	var new_hider_id: int = _next_hider_id
	var new_hunter_id: int = ids[1] if ids[0] == new_hider_id else ids[0]

	_apply_round_state.rpc(new_hider_id, new_hunter_id, ROUND_TIME)


@rpc("authority", "call_local", "reliable")
func _apply_round_state(new_hider_id: int, new_hunter_id: int, starting_time: float) -> void:
	hider_id = new_hider_id
	hunter_id = new_hunter_id
	time_left = starting_time
	round_active = true
	role_assigned.emit(hider_id, Role.HIDER)
	role_assigned.emit(hunter_id, Role.HUNTER)
	round_started.emit()
	timer_updated.emit(time_left)


@rpc("authority", "call_local", "reliable")
func _end_round(winner_role: Role) -> void:
	round_active = false
	if winner_role == Role.HUNTER:
		hunter_score += 1
	else:
		hider_score += 1
	round_ended.emit(winner_role, hunter_score, hider_score)


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


func get_local_role() -> Role:
	var id := multiplayer.get_unique_id()
	if id == hider_id:
		return Role.HIDER
	elif id == hunter_id:
		return Role.HUNTER
	return Role.NONE
