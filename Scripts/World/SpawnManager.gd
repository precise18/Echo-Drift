class_name SpawnManager
## Owns spawn-point lookup and player (re)placement. Covers both "Spawn
## management" (initial placement) and "Respawning" (placement again at
## the start of every round/restart) — in this MVP those are the same
## operation, since a captured Hider ends the round immediately rather
## than respawning mid-round (see GAMEPLAY_SYSTEMS.md for why).
##
## Pure static utility: every map scene (Arena.tscn and any future map)
## just needs a Marker3D in the "hider_spawn" group and one in the
## "hunter_spawn" group; this class does the rest via the scene tree's
## group lookup, so it works with whichever map is currently loaded
## without knowing anything about that map in advance.

const HIDER_SPAWN_GROUP := "hider_spawn"
const HUNTER_SPAWN_GROUP := "hunter_spawn"


## Returns the world position of the current map's spawn point for the
## given role. Returns Vector3.ZERO (with a warning) if the loaded map is
## missing that spawn group entirely — a map authoring mistake, not
## something callers should need to guard against individually.
static func get_spawn_position(tree: SceneTree, role: int) -> Vector3:
	var group := HIDER_SPAWN_GROUP if role == Role.HIDER else HUNTER_SPAWN_GROUP
	var markers := tree.get_nodes_in_group(group)
	if markers.is_empty():
		push_warning("SpawnManager: no Marker3D found in group '%s'" % group)
		return Vector3.ZERO
	return markers[0].global_position


## Moves `player` to its role's spawn point and zeroes its velocity so it
## doesn't carry momentum from wherever it was before. Callers are
## responsible for only doing this for a body they have multiplayer
## authority over (see Main._on_round_started).
static func respawn_player(tree: SceneTree, player: CharacterBody3D, role: int) -> void:
	player.global_position = get_spawn_position(tree, role)
	player.velocity = Vector3.ZERO
