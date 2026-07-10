class_name MapKit
## Reusable, static building blocks shared by every map. A map script
## (see EchoChamber.gd) composes these instead of hand-authoring
## StaticBody3D + CollisionShape3D + MeshInstance3D boilerplate itself —
## this is what "maps use reusable assets" means in a project with no
## external art files (see Assets/README.md): the *pieces* are shared
## code, not copy-pasted resource blocks per map. See MAP_SYSTEM.md.
##
## Every function returns a ready-to-add node; callers just do
## `add_child(MapKit.make_wall(...))`.

const WORLD_LAYER := 1

## Flyweight cache for particle draw-pass meshes: every emitter with the
## same color and dot size shares one mesh + material resource instead of
## allocating its own (the mirror pool, both teleport pads, every burst
## and every ghost trail otherwise each carry a duplicate). Keyed by
## "radius:color"; lives for the whole session, and the full set is a
## handful of tiny primitives. See OPTIMIZATION_REPORT.md.
static var _particle_mesh_cache: Dictionary = {}

## Every piece of static geometry MapKit builds is tagged into this
## group, regardless of where it ends up in the map's node tree —
## bake_navigation() parses geometry by group membership rather than by
## strict parent/child position under the NavigationRegion3D, so a map
## script is free to organize its own hierarchy however makes sense.
const NAV_SOURCE_GROUP := "nav_source"


## A flat, walkable slab. `size` is footprint (X, Z); thickness is fixed
## at 1m with the top surface sitting at y=0, matching every other
## MapKit piece's convention of "y=0 is the floor".
static func make_ground(size: Vector2, material: Material, node_name := "Ground") -> StaticBody3D:
	var box_size := Vector3(size.x, 1.0, size.y)
	var body := _make_static_box(box_size, Vector3(0, -0.5, 0), material)
	body.name = node_name
	return body


## A wall/room-divider segment. `size` is the full box (width, height,
## thickness); `center` is the box's center point (its base sits at
## `center.y - size.y / 2`).
static func make_wall(size: Vector3, center: Vector3, material: Material, node_name := "Wall") -> StaticBody3D:
	var body := _make_static_box(size, center, material)
	body.name = node_name
	return body


## A vertical cylinder — pillar, tower, trunk, whatever the theme calls
## for. `base_position` is where it touches the ground (y = base level).
static func make_pillar(radius: float, height: float, base_position: Vector3, material: Material, node_name := "Pillar") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	body.add_to_group(NAV_SOURCE_GROUP)

	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = base_position + Vector3(0, height / 2.0, 0)
	body.add_child(col)

	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.position = col.position
	mesh_instance.material_override = material
	body.add_child(mesh_instance)

	return body


## A generic solid box obstacle — crate, pedestal, cell wall, whatever.
## `center` is the box's center point.
static func make_box_obstacle(size: Vector3, center: Vector3, material: Material, node_name := "Obstacle") -> StaticBody3D:
	var body := _make_static_box(size, center, material)
	body.name = node_name
	return body


static func _make_static_box(size: Vector3, center: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	body.add_to_group(NAV_SOURCE_GROUP)

	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = center
	body.add_child(col)

	var mesh := BoxMesh.new()
	mesh.size = size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.position = center
	mesh_instance.material_override = material
	body.add_child(mesh_instance)

	return body


## A point light with no collision — torches, neon strips, accent glow.
static func make_light(position: Vector3, color: Color, energy: float, light_range: float, node_name := "Light") -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = node_name
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	return light


## A player spawn point. `group` should be "hider_spawn" or
## "hunter_spawn" — SpawnManager looks these groups up by name
## regardless of which map is loaded (see Scripts/World/SpawnManager.gd).
static func make_spawn_point(position: Vector3, group: String, node_name := "SpawnPoint") -> Marker3D:
	var marker := Marker3D.new()
	marker.name = node_name
	marker.position = position
	marker.add_to_group(group)
	return marker


## Places a decorative prop scene (e.g. a downloaded low-poly model —
## see Assets/Environment/NatureKit/ and ART_DIRECTION.md) at a given
## position, with optional Y-rotation and uniform scale. Deliberately
## adds no collision and isn't tagged into NAV_SOURCE_GROUP — props
## placed with this are visual dressing only, never gameplay-relevant
## obstacles (use make_box_obstacle/make_pillar for those).
static func place_prop(scene: PackedScene, position: Vector3, y_rotation_deg: float = 0.0, uniform_scale: float = 1.0) -> Node3D:
	var instance: Node3D = scene.instantiate()
	instance.position = position
	instance.rotation.y = deg_to_rad(y_rotation_deg)
	instance.scale = Vector3.ONE * uniform_scale
	return instance


## A small looping ambient sparkle effect — deliberately cheap (a capped
## particle count, one tiny unshaded emissive sphere as the draw mesh, no
## collision or physics processing) so it's safe to use in more than one
## place per map without meaningfully changing performance. Used for the
## mirror pool's surface glimmer and each teleport pad's idle shimmer.
static func make_sparkle_particles(color: Color, amount: int, spawn_radius: float, node_name := "Sparkles") -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.amount = amount
	particles.lifetime = 2.5
	particles.emitting = true
	# Tiny unshaded emissive dots never contribute a visible shadow, but
	# left on (the default) they'd each be drawn again in every shadow
	# pass — the single cheapest rendering flag in this file.
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3(0, 1, 0)
	process_material.spread = 20.0
	process_material.gravity = Vector3(0, 0.15, 0) # gentle upward drift, not a fall
	process_material.initial_velocity_min = 0.1
	process_material.initial_velocity_max = 0.3
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = spawn_radius
	process_material.scale_min = 0.5
	process_material.scale_max = 1.0
	particles.process_material = process_material

	particles.draw_pass_1 = _get_particle_dot_mesh(color, 0.05)
	return particles


## Shared (cached) draw mesh for all particle effects of a given color
## and dot size — see _particle_mesh_cache above.
static func _get_particle_dot_mesh(color: Color, radius: float) -> SphereMesh:
	var key := "%s:%s" % [radius, color.to_html()]
	if _particle_mesh_cache.has(key):
		return _particle_mesh_cache[key]

	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	material.albedo_color = Color(color.r, color.g, color.b, 0.7)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	_particle_mesh_cache[key] = mesh
	return mesh


## A one-shot particle burst — teleport activation, capture, anything
## that needs a quick "something just happened here" flourish rather than
## a continuous effect. Frees itself once the burst finishes so it never
## lingers as dead weight in the scene tree.
static func make_burst_particles(color: Color, amount: int, node_name := "Burst") -> GPUParticles3D:
	var particles := make_sparkle_particles(color, amount, 0.3, node_name)
	particles.lifetime = 0.6
	particles.one_shot = true
	particles.explosiveness = 0.9
	var process_material: ParticleProcessMaterial = particles.process_material
	process_material.initial_velocity_min = 1.0
	process_material.initial_velocity_max = 2.5
	process_material.gravity = Vector3(0, -1.0, 0)
	particles.finished.connect(particles.queue_free)
	return particles


## A short-lived, world-space particle drip meant to be parented to a
## moving node (e.g. EchoGhost) so it leaves a fading trail behind rather
## than a cloud that follows the emitter — `local_coords = false` is what
## makes already-emitted particles stay put in world space while the
## parent keeps moving. Caller controls `.emitting` to turn the trail on
## and off (see EchoGhost._set_active); deliberately tiny (short lifetime,
## capped amount) so a trail running continuously for the whole time a
## ghost is visible stays cheap.
static func make_trail_particles(color: Color, amount: int, node_name := "Trail") -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.amount = amount
	particles.lifetime = 0.5
	particles.emitting = false
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3(0, 1, 0)
	process_material.spread = 15.0
	process_material.gravity = Vector3(0, -0.3, 0)
	process_material.initial_velocity_min = 0.05
	process_material.initial_velocity_max = 0.2
	process_material.scale_min = 0.4
	process_material.scale_max = 0.8
	particles.process_material = process_material

	particles.draw_pass_1 = _get_particle_dot_mesh(color, 0.04)
	return particles


## Bakes a walkable NavigationMesh from every MapKit-built piece in the
## map, wherever it sits in the tree — every StaticBody3D this file
## creates is auto-tagged into NAV_SOURCE_GROUP, and baking parses by
## group membership (SOURCE_GEOMETRY_GROUPS_EXPLICIT) rather than
## requiring geometry to be a direct child of `region`. Call this last,
## after everything else in the map has been added. Uses collision
## shapes (not visual meshes) as the source geometry, which is both
## correct (navigation should follow physical geometry) and avoids a
## GPU-readback performance warning Godot logs when baking from visual
## meshes at runtime.
static func bake_navigation(region: NavigationRegion3D) -> void:
	var navmesh := NavigationMesh.new()
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_EXPLICIT
	navmesh.geometry_source_group_name = NAV_SOURCE_GROUP
	region.navigation_mesh = navmesh
	region.bake_navigation_mesh(false) # false = synchronous; these maps are small
