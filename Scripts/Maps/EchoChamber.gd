extends Node3D
## The Echo Hunt MVP's map: a bilaterally symmetric arena built entirely
## from MapKit's reusable pieces. The symmetry is the point — everything
## on one side of the central mirror plane (X = 0) has a matching twin on
## the other, including the two spawn points, so the Hider and Hunter
## literally start as reflections of each other. The centerpiece "mirror
## pool" and the linked teleport pads (stepping into one is like walking
## through a mirror to the other) turn that same idea into gameplay, not
## just set dressing. See MAP_SYSTEM.md.

const HALF_SIZE := 15.0 # ground spans -15..15 on both X and Z

const WALL_MATERIAL := preload("res://Materials/wall_material.tres")
const FLOOR_MATERIAL := preload("res://Materials/echo_chamber_floor_material.tres")
const PILLAR_MATERIAL := preload("res://Materials/rock_material.tres")
const PANEL_MATERIAL := preload("res://Materials/mirror_panel_material.tres")
const POOL_MATERIAL := preload("res://Materials/mirror_pool_material.tres")

const ECHO_CYAN := Color(0.55, 0.95, 1.0) # matches EchoGhost's glow color

# Free, CC0 low-poly props (Kenney Nature Kit — see
# Assets/Environment/NatureKit/LICENSE.txt and ART_DIRECTION.md for
# sourcing). Placed with MapKit.place_prop(), which adds no collision —
# pure visual dressing, never a new hiding obstacle, so the hand-tuned
# gameplay layout above is unaffected.
const ROCK_SMALL := preload("res://Assets/Environment/NatureKit/rock_smallA.glb")
const ROCK_LARGE := preload("res://Assets/Environment/NatureKit/rock_largeC.glb")
const FLOWER_PURPLE := preload("res://Assets/Environment/NatureKit/flower_purpleA.glb")
const FLOWER_YELLOW := preload("res://Assets/Environment/NatureKit/flower_yellowA.glb")
const BUSH := preload("res://Assets/Environment/NatureKit/plant_bush.glb")


func _ready() -> void:
	_build_environment()
	_build_ground_and_walls()
	_build_mirror_pool()
	_build_mirrored_obstacles()
	_build_environment_dressing()
	_build_spawn_points()
	_build_teleport_pads()
	_build_navigation()


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.3, 0.42, 0.55)
	sky_material.sky_horizon_color = Color(0.6, 0.75, 0.82)
	sky_material.sky_curve = 0.15
	sky_material.ground_bottom_color = Color(0.2, 0.24, 0.28)
	sky_material.ground_horizon_color = Color(0.6, 0.75, 0.82)
	sky_material.ground_curve = 0.15
	sky_material.sun_angle_max = 30.0
	sky_material.sun_curve = 0.15
	var sky := Sky.new()
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# A faint cyan fog reinforces the "echo" atmosphere without hurting
	# readability at the arena's scale.
	env.fog_enabled = true
	env.fog_light_color = ECHO_CYAN
	env.fog_density = 0.004
	# Cheap but high-impact: every emissive surface in this map (the
	# mirror pool, teleport pads, accent lights, and the echo ghost
	# itself) is tuned to bloom under glow — one inexpensive post-process
	# that makes the whole "echo" visual language read as actually
	# glowing instead of just being a bright flat color. Levels/HDR
	# threshold kept modest to stay cheap on lower-end hardware.
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.05
	# Deliberately below the HDR default (1.0): this map's emissive
	# materials (mirror pool, teleport pads, accent lights) use modest
	# energy multipliers so they read as gently lit rather than
	# blown-out, so glow's threshold has to be lowered to actually catch
	# them instead of requiring every material to be re-tuned brighter.
	env.glow_hdr_threshold = 0.65
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# A small saturation lift keeps the flat StandardMaterial3D colors
	# feeling stylized/toylike (see BEGINNER_GODOT_GUIDE art direction)
	# rather than washed out — free at runtime, no texture cost.
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.05

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.transform = sun.transform.looking_at(Vector3(-0.4, -0.8, -0.4), Vector3.UP)
	sun.light_color = Color(0.85, 0.92, 1.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)


func _build_ground_and_walls() -> void:
	add_child(MapKit.make_ground(Vector2(HALF_SIZE * 2, HALF_SIZE * 2), FLOOR_MATERIAL))

	var wall_span := HALF_SIZE * 2 + 2.0
	add_child(MapKit.make_wall(Vector3(wall_span, 4, 1), Vector3(0, 2, -HALF_SIZE - 0.5), WALL_MATERIAL, "WallNorth"))
	add_child(MapKit.make_wall(Vector3(wall_span, 4, 1), Vector3(0, 2, HALF_SIZE + 0.5), WALL_MATERIAL, "WallSouth"))
	add_child(MapKit.make_wall(Vector3(1, 4, wall_span), Vector3(-HALF_SIZE - 0.5, 2, 0), WALL_MATERIAL, "WallWest"))
	add_child(MapKit.make_wall(Vector3(1, 4, wall_span), Vector3(HALF_SIZE + 0.5, 2, 0), WALL_MATERIAL, "WallEast"))


## The chamber's centerpiece: a flat, non-collidable reflective disc
## sitting exactly on the mirror plane (X = 0) — visually the thing being
## "reflected across", and a landmark both players can navigate by.
func _build_mirror_pool() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 4.0
	mesh.bottom_radius = 4.0
	mesh.height = 0.05
	var pool := MeshInstance3D.new()
	pool.name = "MirrorPool"
	pool.mesh = mesh
	pool.position = Vector3(0, 0.02, 0)
	pool.material_override = POOL_MATERIAL
	pool.cast_shadow = 0
	add_child(pool)

	var glow := MapKit.make_light(Vector3(0, 2.0, 0), ECHO_CYAN, 1.2, 10.0, "MirrorPoolGlow")
	add_child(glow)

	var sparkles := MapKit.make_sparkle_particles(ECHO_CYAN, 14, 3.5, "MirrorPoolSparkles")
	sparkles.position = Vector3(0, 0.1, 0)
	add_child(sparkles)


## Every obstacle is placed as a symmetric pair (x, z) / (-x, z) so the
## whole layout mirrors across X = 0 — a Hunter learning one half of the
## map has effectively learned the other half's geometry too, just not
## which half the Hider is actually using.
func _build_mirrored_obstacles() -> void:
	_add_mirrored_pillar_pair(8.0, -6.0)
	_add_mirrored_pillar_pair(8.0, 6.0)
	_add_mirrored_panel_pair(5.0, -3.0)
	_add_mirrored_panel_pair(5.0, 3.0)
	_add_mirrored_light_pair(6.0, 0.0)


func _add_mirrored_pillar_pair(x: float, z: float) -> void:
	add_child(MapKit.make_pillar(0.5, 4.0, Vector3(-x, 0, z), PILLAR_MATERIAL, "Pillar"))
	add_child(MapKit.make_pillar(0.5, 4.0, Vector3(x, 0, z), PILLAR_MATERIAL, "Pillar"))


func _add_mirrored_panel_pair(x: float, z: float) -> void:
	add_child(MapKit.make_box_obstacle(Vector3(0.2, 2.5, 2.2), Vector3(-x, 1.25, z), PANEL_MATERIAL, "MirrorPanel"))
	add_child(MapKit.make_box_obstacle(Vector3(0.2, 2.5, 2.2), Vector3(x, 1.25, z), PANEL_MATERIAL, "MirrorPanel"))


func _add_mirrored_light_pair(x: float, z: float) -> void:
	add_child(MapKit.make_light(Vector3(-x, 2.5, z), ECHO_CYAN, 0.7, 8.0, "AccentLight"))
	add_child(MapKit.make_light(Vector3(x, 2.5, z), ECHO_CYAN, 0.7, 8.0, "AccentLight"))


## Small, purely decorative CC0 props grounding the pillars and framing
## the mirror pool — mirrored pairs like everything else here, and
## deliberately modest in count (10 tiny low-poly meshes, a few KB each)
## to stay well within "don't increase performance requirements". See
## ART_DIRECTION.md.
func _build_environment_dressing() -> void:
	_add_mirrored_prop_pair(ROCK_SMALL, 8.8, -6.6, 15.0)
	_add_mirrored_prop_pair(ROCK_LARGE, 8.8, 6.6, -20.0)
	_add_mirrored_prop_pair(FLOWER_PURPLE, 2.0, -5.0, 0.0)
	_add_mirrored_prop_pair(FLOWER_YELLOW, 2.0, 5.0, 0.0)
	_add_mirrored_prop_pair(BUSH, 10.5, -3.0, 40.0)


func _add_mirrored_prop_pair(scene: PackedScene, x: float, z: float, y_rotation_deg: float) -> void:
	add_child(MapKit.place_prop(scene, Vector3(-x, 0, z), -y_rotation_deg))
	add_child(MapKit.place_prop(scene, Vector3(x, 0, z), y_rotation_deg))


## Mirror images of each other across X = 0 — the Hider and Hunter start
## the round as literal reflections of one another.
func _build_spawn_points() -> void:
	add_child(MapKit.make_spawn_point(Vector3(-10, 1, 0), "hider_spawn", "HiderSpawn"))
	add_child(MapKit.make_spawn_point(Vector3(10, 1, 0), "hunter_spawn", "HunterSpawn"))


## A mirrored pair near the back wall for a quick cross-map shortcut —
## stepping into one is, thematically, stepping through the mirror to
## reach its reflection on the other side.
func _build_teleport_pads() -> void:
	var pad_a := TeleportPad.new()
	pad_a.name = "TeleportPadWest"
	pad_a.position = Vector3(-13, 0, 10)
	var pad_b := TeleportPad.new()
	pad_b.name = "TeleportPadEast"
	pad_b.position = Vector3(13, 0, 10)

	add_child(pad_a)
	add_child(pad_b)
	pad_a.linked_pad = pad_b
	pad_b.linked_pad = pad_a


func _build_navigation() -> void:
	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	add_child(region)
	MapKit.bake_navigation(region)
