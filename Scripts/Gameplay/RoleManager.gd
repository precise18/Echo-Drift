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
static func assign_roles(connected_peer_ids: Array[int], previous_hider_id: int, peer_preferred_roles: Dictionary = {}) -> Dictionary:
	if connected_peer_ids.size() < 2:
		return {}

	var ids := connected_peer_ids.duplicate()
	ids.sort()
	
	var p1 = ids[0]
	var p2 = ids[1]
	
	var pref1 = peer_preferred_roles.get(p1, 0)
	var pref2 = peer_preferred_roles.get(p2, 0)
	
	var hider_id: int = -1
	var hunter_id: int = -1
	
	# If they have non-conflicting preferences, assign exactly what they want
	if pref1 == 1 and pref2 != 1:
		hider_id = p1
		hunter_id = p2
	elif pref2 == 1 and pref1 != 1:
		hider_id = p2
		hunter_id = p1
	elif pref1 == 2 and pref2 != 2:
		hunter_id = p1
		hider_id = p2
	elif pref2 == 2 and pref1 != 2:
		hunter_id = p2
		hider_id = p1
	else:
		# Conflicting or both Any: fallback to original logic
		hider_id = previous_hider_id if ids.has(previous_hider_id) else ids[0]
		hunter_id = ids[1] if ids[0] == hider_id else ids[0]

	return {"hider_id": hider_id, "hunter_id": hunter_id}
