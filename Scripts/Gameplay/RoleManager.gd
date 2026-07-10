class_name RoleManager
## Pure logic: given who is actually connected and who hid last round,
## decide who hides and who hunts next. No state, no scene tree access —
## this is what "Team assignment", "Hunter selection" and "Hider
## selection" all reduce to in a 2-player game (each player is a team of
## one, assigned one of the two roles).
##
## Exactly two players are assumed, matching this MVP's networking cap
## (NetworkManager.MAX_PLAYERS = 2).


## Returns {"hider_id": int, "hunter_id": int}, or an empty Dictionary if
## fewer than two peers are connected. Peer ids from ENet are arbitrary
## 32-bit numbers (not simply 1 and 2), so roles are derived from whoever
## is actually connected right now rather than assumed positions.
static func assign_roles(connected_peer_ids: Array[int], previous_hider_id: int) -> Dictionary:
	if connected_peer_ids.size() < 2:
		return {}

	var ids := connected_peer_ids.duplicate()
	ids.sort()

	# Keep the same hider if they're still connected (first round, or a
	# reconnect); otherwise alternate deterministically so both players
	# get a turn at both roles across repeated restarts.
	var hider_id: int = previous_hider_id if ids.has(previous_hider_id) else ids[0]
	var hunter_id: int = ids[1] if ids[0] == hider_id else ids[0]

	return {"hider_id": hider_id, "hunter_id": hunter_id}
