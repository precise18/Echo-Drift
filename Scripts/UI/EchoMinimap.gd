extends Control
class_name EchoMinimap
## Bottom-left echo radar: the local player at the center (fixed
## north-up — the map does not rotate with the camera; a known 1.1.0
## limitation, see KNOWN_LIMITATIONS.md) and any currently *visible*
## echo as a cyan blip at its real relative direction/distance, clamped
## to the rim when it's beyond RANGE_METERS. Drawn with plain 2D
## primitives (draw_circle/draw_arc/draw_colored_polygon) in the game's
## own palette — consistent with the rest of the UI being code-built
## via UIKit rather than art assets. See ECHO_VISUAL_GUIDE.md.
##
## Deliberately only shows a ghost that's actually `visible` (i.e. one a
## player could also see/hear in the world right now) — this is a
## readability aid for something already inferable in-world, not a new
## way to detect the echo that bypasses looking/listening for it.

const RANGE_METERS := 24.0 # world distance mapped to the outer ring
const RADIUS := 64.0       # on-screen radius, px

const COLOR_BG := Color(0.05, 0.07, 0.09, 0.72)
const COLOR_RING := Color(0.55, 0.95, 1.0, 0.35)
const COLOR_PLAYER := Color(0.92, 0.95, 1.0, 0.95)
const COLOR_ECHO := Color(0.55, 0.95, 1.0, 0.95)

## The Main.tscn root — used to lazily look up the local player body and
## the EchoSystem each frame rather than requiring HUD to hand over
## already-resolved references (both can legitimately not exist yet the
## moment HUD._ready() runs — see HUD.gd).
var main_root: Node = null


func _ready() -> void:
	custom_minimum_size = Vector2(RADIUS, RADIUS) * 2.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var center := Vector2(RADIUS, RADIUS)
	draw_circle(center, RADIUS, COLOR_BG)
	draw_arc(center, RADIUS - 1.0, 0.0, TAU, 48, COLOR_RING, 1.5)

	var player := _find_local_player()
	var echo := _find_visible_echo()

	# Player marker: a small triangle pointing screen-up. Fixed
	# orientation for this preview — a real version would rotate the
	# whole map to the camera's facing instead.
	var tri := PackedVector2Array([
		center + Vector2(0, -7),
		center + Vector2(-5, 6),
		center + Vector2(5, 6),
	])
	draw_colored_polygon(tri, COLOR_PLAYER)

	if player == null or echo == null:
		return

	var delta_world := echo.global_position - player.global_position
	var offset := Vector2(delta_world.x, delta_world.z)
	var scale := (RADIUS - 6.0) / RANGE_METERS
	var mapped := offset * scale
	if mapped.length() > RADIUS - 6.0:
		mapped = mapped.normalized() * (RADIUS - 6.0) # clamp to rim — "that way, off the edge"

	draw_circle(center + mapped, 5.0, COLOR_ECHO)
	draw_arc(center + mapped, 8.0, 0.0, TAU, 16, Color(COLOR_ECHO.r, COLOR_ECHO.g, COLOR_ECHO.b, 0.4), 2.0)


func _find_local_player() -> Node3D:
	if main_root == null:
		return null
	var players := main_root.get_node_or_null("Players")
	if players == null:
		return null
	return players.get_node_or_null(str(multiplayer.get_unique_id())) as Node3D


## Only the first *visible* ghost — matches EchoSystem's current
## single-echo-by-default configuration (see ECHO_SYSTEM.md "Multiple
## echoes"); a multi-echo build would want every visible ghost plotted,
## not just one, but that's real-minimap-art scope, not preview scope.
func _find_visible_echo() -> Node3D:
	if main_root == null:
		return null
	var echo_system := main_root.get_node_or_null("EchoSystem")
	if echo_system == null:
		return null
	for child in echo_system.get_children():
		if child is EchoGhost and child.visible:
			return child
	return null
