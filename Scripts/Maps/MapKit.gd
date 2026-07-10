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
