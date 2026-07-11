extends Node
## Autoload: registry of available maps and which one is active for the
## current match. The host's selection (made on MainMenu before hosting)
## is authoritative; a joining client learns it via a reliable RPC sent
## as part of the connection handshake (see NetworkManager.
## _on_peer_connected -> sync_to_peer). Main.gd waits for is_map_ready()
## before instantiating map content, rather than the whole game scene
## waiting on it — see MAP_SYSTEM.md for why that distinction matters.

signal map_selected(map_id: String)

## Registry of every map this build ships. Adding a new map later means
## adding one entry here and one new map scene built from MapKit pieces
## — nothing else about the selection/sync system changes.
const MAPS := {
	"echo_chamber": {
		"name": "Echo Chamber",
		"scene": "res://Scenes/Maps/EchoChamber.tscn",
		"description": "A perfectly mirrored arena split by a glowing pool. Every pillar, light and teleport pad has a twin across the mirror line — hunter and hider start as reflections of each other.",
	},
	"arena": {
		"name": "The Arena",
		"scene": "res://Scenes/Maps/Arena.tscn",
		"description": "An open forest arena with trees, rocks, and a central cabin. Short sightlines force close-quarters cat-and-mouse.",
	},
}
const DEFAULT_MAP_ID := "echo_chamber"

var selected_map_id: String = DEFAULT_MAP_ID

# Client-only: true once _receive_map_id has actually fired. The server
# never needs this — its own selection is authoritative from the moment
# it's set, with nothing to wait for.
var _has_synced := false


## Called from MainMenu before host_game(). Ignored if map_id isn't a
## known map — a stale/typo'd id should never silently break hosting.
func set_selected_map(map_id: String) -> void:
	if MAPS.has(map_id):
		selected_map_id = map_id


func get_map_ids() -> Array:
	return MAPS.keys()


func get_map_name(map_id: String) -> String:
	var entry: Dictionary = MAPS.get(map_id, MAPS[DEFAULT_MAP_ID])
	return entry["name"]


func get_map_description(map_id: String) -> String:
	var entry: Dictionary = MAPS.get(map_id, MAPS[DEFAULT_MAP_ID])
	return entry.get("description", "")


## True once it's safe to call instantiate_selected_map(): always true on
## the server (it already knows its own choice); on a client, true only
## after the host's choice has actually arrived.
func is_map_ready() -> bool:
	return multiplayer.is_server() or _has_synced


func instantiate_selected_map() -> Node3D:
	var entry: Dictionary = MAPS.get(selected_map_id, MAPS[DEFAULT_MAP_ID])
	var packed: PackedScene = load(entry["scene"])
	return packed.instantiate()


## Server-only. Called by NetworkManager as soon as a peer connects, so
## they know the active map as early as possible (independent of
## whatever pace their own scene loading happens at).
func sync_to_peer(peer_id: int) -> void:
	PacketTrace.sent("receive_map_id", multiplayer.get_unique_id(), peer_id, "map_id=%s" % selected_map_id, "_receive_map_id") # TEMP DEBUG
	_receive_map_id.rpc_id(peer_id, selected_map_id)


@rpc("authority", "call_remote", "reliable")
func _receive_map_id(map_id: String) -> void:
	# TEMP DEBUG: an unrecognized map_id was previously tolerated completely
	# silently -- selected_map_id just stayed at its old value and
	# _has_synced/map_selected fired anyway, giving no sign anything was
	# wrong. That's "a packet with invalid format/payload" handled with
	# zero trace, exactly the case this instrumentation pass is meant to
	# surface.
	if MAPS.has(map_id):
		selected_map_id = map_id
		PacketTrace.received("receive_map_id", multiplayer.get_remote_sender_id(), multiplayer.get_unique_id(), "map_id=%s" % map_id, "_receive_map_id", "_receive_map_id (handled)")
	else:
		PacketTrace.received("receive_map_id", multiplayer.get_remote_sender_id(), multiplayer.get_unique_id(), "map_id=%s" % map_id, "_receive_map_id", "INVALID_PAYLOAD -- unrecognized map_id, silently kept old selected_map_id=%s" % selected_map_id)
	_has_synced = true
	map_selected.emit(selected_map_id)
