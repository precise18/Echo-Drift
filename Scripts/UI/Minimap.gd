class_name Minimap
extends Control
## Single responsibility: draw a top-down 2D overlay of the current map's
## gameplay obstacles, the local player, and (Hunter-only) the primary echo
## ghost. Obstacles are read live from whichever map is loaded, via
## MapKit.NAV_SOURCE_GROUP — the same group MapKit tags every static piece
## of gameplay geometry into for navmesh baking (see MapKit.gd) — so this
## works with any current or future MapKit-built map without hardcoding a
## specific map's node names or layout. No SubViewport/camera: this is a
## drawn 2D overlay, consistent with the project's MVP scope.

const MAP_HALF_SIZE := 15.0 # matches EchoChamber.gd's HALF_SIZE: ground/walls span -15..15 on X/Z

## Obstacles are styled by name prefix; anything unrecognized still renders
## with DEFAULT_OBSTACLE_STYLE rather than being silently skipped, so a
## future map's new obstacle types show up on the minimap immediately.
const OBSTACLE_STYLES := {
	"Pillar": {"color": Color(0.6, 0.6, 0.65), "shape": "circle", "radius": 4.0},
	"MirrorPanel": {"color": Color(0.55, 0.85, 0.95), "shape": "square", "radius": 5.0},
}
const DEFAULT_OBSTACLE_STYLE := {"color": Color(0.55, 0.55, 0.55), "shape": "circle", "radius": 4.0}

## The ground slab and perimeter walls are also tagged into nav_source (for
## navmesh baking), but the panel's own border already represents the
## arena's bounds — drawing them again as blips would just be four
## redundant edge rectangles, so they're filtered out by name prefix.
const EXCLUDED_PREFIXES := ["Ground", "Wall"]

const PLAYER_COLOR := Color(1.0, 0.83, 0.2)

var local_player: Node3D = null
var echo_ghost: Node3D = null

# Array of { "position": Vector3, "style": Dictionary }, cached once by setup().
var _obstacle_blips: Array = []


## Reads every MapKit.NAV_SOURCE_GROUP node under p_map_root at call time
## and caches its world position + blip style. Called once per map load
## (see Main.gd._load_map()) — maps don't change mid-round, so there's no
## need to re-scan every frame.
func setup(p_map_root: Node3D) -> void:
	_obstacle_blips.clear()
	for node in p_map_root.get_tree().get_nodes_in_group(MapKit.NAV_SOURCE_GROUP):
		if not (node is Node3D) or not p_map_root.is_ancestor_of(node):
			continue
		var node_name := String(node.name)
		if _is_excluded(node_name):
			continue
		_obstacle_blips.append({
			"position": (node as Node3D).global_position,
			"style": _style_for(node_name),
		})


func _is_excluded(node_name: String) -> bool:
	for prefix in EXCLUDED_PREFIXES:
		if node_name.begins_with(prefix):
			return true
	return false


func _style_for(node_name: String) -> Dictionary:
	for prefix in OBSTACLE_STYLES.keys():
		if node_name.begins_with(prefix):
			return OBSTACLE_STYLES[prefix]
	return DEFAULT_OBSTACLE_STYLE


func set_local_player(p: Node3D) -> void:
	local_player = p


func set_echo_ghost(g: Node3D) -> void:
	echo_ghost = g


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UIKit.COLOR_PANEL)
	draw_rect(Rect2(Vector2.ZERO, size), UIKit.COLOR_MUTED, false, 2.0)

	var center := size / 2.0
	var half_box := minf(size.x, size.y) / 2.0 - 6.0

	for blip in _obstacle_blips:
		_draw_obstacle(blip, center, half_box)

	# Never draw the opposing Hider's real position — only the delayed echo
	# ghost, and only once the local player is actually the Hunter.
	if echo_ghost != null and is_instance_valid(echo_ghost) and echo_ghost.visible \
			and _local_role() == Role.HUNTER:
		var ghost_pos := _world_to_panel(echo_ghost.global_position, center, half_box)
		draw_circle(ghost_pos, 5.0, UIKit.COLOR_ACCENT)

	if local_player != null and is_instance_valid(local_player):
		_draw_player_arrow(center, half_box)


func _local_role() -> int:
	if multiplayer.multiplayer_peer == null:
		return Role.NONE
	return Role.HIDER if multiplayer.get_unique_id() == RoundManager.hider_id else Role.HUNTER


func _draw_obstacle(blip: Dictionary, center: Vector2, half_box: float) -> void:
	var world_pos: Vector3 = blip["position"]
	var panel_pos := _world_to_panel(world_pos, center, half_box)
	var style: Dictionary = blip["style"]
	var r: float = style["radius"]
	if style["shape"] == "circle":
		draw_circle(panel_pos, r, style["color"])
	else:
		draw_rect(Rect2(panel_pos - Vector2(r, r), Vector2(r, r) * 2.0), style["color"])


func _draw_player_arrow(center: Vector2, half_box: float) -> void:
	var panel_pos := _world_to_panel(local_player.global_position, center, half_box)
	# global_transform.basis.z is the node's local -forward axis in world space
	# (Godot's -Z-forward convention), and world_to_panel maps X/Z straight
	# into panel X/Y with no axis flip, so negating it gives the correct
	# on-screen facing direction directly, without re-deriving it from
	# global_rotation.y and risking a sign mistake.
	var forward3d := -local_player.global_transform.basis.z
	var forward := Vector2(forward3d.x, forward3d.z)
	if forward == Vector2.ZERO:
		forward = Vector2.UP
	else:
		forward = forward.normalized()
	var perp := Vector2(-forward.y, forward.x)
	var tip := panel_pos + forward * 7.0
	var left := panel_pos - forward * 4.0 + perp * 4.0
	var right := panel_pos - forward * 4.0 - perp * 4.0
	draw_colored_polygon(PackedVector2Array([tip, left, right]), PLAYER_COLOR)


func _world_to_panel(world_pos: Vector3, center: Vector2, half_box: float) -> Vector2:
	return center + Vector2(world_pos.x, world_pos.z) / MAP_HALF_SIZE * half_box
