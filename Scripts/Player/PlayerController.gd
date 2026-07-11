extends CharacterBody3D

var HIDER_MATERIAL: Material = load("res://Materials/player_hider_material.tres")
var HUNTER_MATERIAL: Material = load("res://Materials/player_hunter_material.tres")

@onready var movement = $MovementComponent
@onready var camera = $CameraYaw
@onready var anim = $AnimationComponent

var _was_airborne := false
var _base_scale := Vector3.ONE

var _chest_ray: RayCast3D
var _head_ray: RayCast3D
var is_mantling: bool = false

var peer_id: int = -1

const _SAMPLE1_IDLE := "res://Assets/Characters/animations/idle/sample_1_idle.glb"
const _CANIMO_IDLE  := "res://Assets/Characters/canimo/animations/idle/sample_3_idle.glb"
const _SAMPLE1_ANIMS := {
	"walk":       "res://Assets/Characters/animations/walk/sample_1_walk.glb",
	"run":        "res://Assets/Characters/animations/run/sample_1_run.glb",
	"jump_start": "res://Assets/Characters/animations/jump_start/sample_1_jump_start.glb",
	"jump":       "res://Assets/Characters/animations/jump/sample_1_jump.glb",
	"jump_fall":  "res://Assets/Characters/animations/jump_fall/sample_1_jump_fall.glb",
	"jump_end":   "res://Assets/Characters/animations/jump_end/sample_1_jump_end.glb",
}
const _CANIMO_ANIMS := {
	"walk":       "res://Assets/Characters/canimo/animations/walk/sample_3_walk.glb",
	"run":        "res://Assets/Characters/canimo/animations/run/sample_3_run.glb",
	"jump_start": "res://Assets/Characters/canimo/animations/jump_start/sample_3_jump_start.glb",
	"jump":       "res://Assets/Characters/canimo/animations/jump/sample_3_jump.glb",
	"jump_fall":  "res://Assets/Characters/canimo/animations/jump_fall/sample_3_jump_fall.glb",
	"jump_end":   "res://Assets/Characters/canimo/animations/jump_end/sample_3_jump_end.glb",
}

func _ready() -> void:
	peer_id = name.to_int()

	anim.setup($Model/ModelInstance)
	_autofit_model()

	_chest_ray = RayCast3D.new()
	_head_ray = RayCast3D.new()
	add_child(_chest_ray)
	add_child(_head_ray)

	_chest_ray.position = Vector3(0, 1.2, 0)
	_chest_ray.target_position = Vector3(0, 0, -0.6)
	_head_ray.position = Vector3(0, 2.1, 0)
	_head_ray.target_position = Vector3(0, 0, -0.6)

	var footsteps := FootstepEmitter.new()
	footsteps.name = "Footsteps"
	footsteps.stream = SoundFactory.footstep()
	add_child(footsteps)

	apply_authority_state()
	_refresh_role_material()
	RoundManager.role_assigned.connect(_on_role_assigned)

	# Reconnect case: role was already assigned before this node was created
	if RoundManager.hider_id == peer_id or RoundManager.hunter_id == peer_id:
		_swap_character(peer_id == RoundManager.hider_id)
		_refresh_role_material()

func apply_authority_state() -> void:
	if is_multiplayer_authority():
		$CameraYaw/CameraPitch/Camera3D.make_current()
		if not get_window().focus_entered.is_connected(_capture_mouse):
			get_window().focus_entered.connect(_capture_mouse)
		_capture_mouse()
	elif get_window().focus_entered.is_connected(_capture_mouse):
		get_window().focus_entered.disconnect(_capture_mouse)

func _exit_tree() -> void:
	if RoundManager.role_assigned.is_connected(_on_role_assigned):
		RoundManager.role_assigned.disconnect(_on_role_assigned)
	if get_window().focus_entered.is_connected(_capture_mouse):
		get_window().focus_entered.disconnect(_capture_mouse)

func _capture_mouse() -> void:
	if UIKit.block_mouse_capture:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_role_assigned(_peer_id: int, _role: int) -> void:
	_swap_character(peer_id == RoundManager.hider_id)
	_refresh_role_material()

## Replaces the ModelInstance under $Model with the character for the given role.
## The new model's AnimationPlayer is fresh, so anim.setup() re-merges everything.
func _swap_character(is_hider: bool) -> void:
	var idle_path := _CANIMO_IDLE if is_hider else _SAMPLE1_IDLE
	var anims := _CANIMO_ANIMS if is_hider else _SAMPLE1_ANIMS

	var old: Node = $Model.get_node_or_null("ModelInstance")
	if old:
		old.name = "_old_model"
		old.queue_free()

	var scene: PackedScene = load(idle_path)
	if not scene:
		push_warning("PlayerController: could not load character model: " + idle_path)
		return
	var new_inst: Node3D = scene.instantiate()
	new_inst.name = "ModelInstance"
	$Model.add_child(new_inst)

	anim.glb_walk       = anims["walk"]
	anim.glb_run        = anims["run"]
	anim.glb_jump_start = anims["jump_start"]
	anim.glb_jump       = anims["jump"]
	anim.glb_jump_fall  = anims["jump_fall"]
	anim.glb_jump_end   = anims["jump_end"]
	anim.setup(new_inst)
	_autofit_model()

func _refresh_role_material() -> void:
	var model_inst := $Model.get_node_or_null("ModelInstance")
	if model_inst == null:
		return
	# Use next_pass so the original character texture is preserved underneath
	# and we only apply a semi-transparent team-colour tint on top.
	var is_hunter := peer_id == RoundManager.hunter_id
	var tint_mat := HUNTER_MATERIAL if is_hunter else HIDER_MATERIAL
	_apply_tint_recursive(model_inst, tint_mat)

func _apply_tint_recursive(node: Node, tint_mat: Material) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		# Clear any previous override so original surface materials show through
		mi.material_override = null
		# Apply tint as next_pass on each surface so original texture stays visible
		for i in mi.get_surface_override_material_count():
			var base = mi.mesh.surface_get_material(i)
			if base:
				base.next_pass = tint_mat
			else:
				mi.set_surface_override_material(i, tint_mat)
	for child in node.get_children():
		_apply_tint_recursive(child, tint_mat)

func _execute_mantle() -> void:
	is_mantling = true
	anim.play("jump_start")
	velocity = Vector3.ZERO
	
	var tween = create_tween()
	var mantle_up = global_position + Vector3(0, 1.6, 0)
	var mantle_fwd = mantle_up + movement.direction * 1.0
	
	tween.tween_property(self, "global_position", mantle_up, 0.15).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "global_position", mantle_fwd, 0.15).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(func(): is_mantling = false)

var _last_position := Vector3.ZERO

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		# Animate puppets based on positional changes since velocity isn't synced
		var pos_delta = global_position - _last_position
		_last_position = global_position
		
		var h_speed = Vector2(pos_delta.x, pos_delta.z).length() / delta
		
		if h_speed > 0.1:
			anim.play("run" if h_speed > 5.0 else "walk")
		else:
			anim.play("idle")
		return
		
	if is_mantling:
		return
		
	if not (RoundManager.round_active or MatchStateManager.is_in_lobby()):
		movement.tick(delta, Vector2.ZERO, false, camera.get_forward(), camera.get_right())
		anim.play("idle")
		return
		
	var input_dir  := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var is_running := Input.is_action_pressed("sprint")

	movement.tick(delta, input_dir, is_running, camera.get_forward(), camera.get_right())
	camera.follow_behind(movement.direction, delta)
	anim.face_direction(movement.direction, delta)
	
	if movement.direction.length() > 0.1:
		_chest_ray.target_position = movement.direction * 0.6
		_head_ray.target_position = movement.direction * 0.6

	var h_speed := Vector2(velocity.x, velocity.z).length()
	camera.update_fov(h_speed, movement.run_speed, delta)

	var is_airborne = movement.is_airborne()
	
	# Ledge Grabbing Logic & Airborne Animation
	if is_airborne:
		if movement.vertical_velocity() < 0.0 and _chest_ray.is_colliding() and not _head_ray.is_colliding():
			_execute_mantle()
		else:
			anim.play("jump_start" if movement.vertical_velocity() > 0 else "jump_fall")
	elif movement.is_moving():
		anim.play("run" if is_running else "walk")
	else:
		anim.play("idle")

	is_airborne = movement.is_airborne()
	if _was_airborne and not is_airborne:
		_squash_and_stretch()
	_was_airborne = is_airborne

func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		camera.handle_mouse(event)

func _squash_and_stretch() -> void:
	if _base_scale == Vector3.ONE and $Model.scale != Vector3.ONE:
		_base_scale = $Model.scale
		
	var model: Node3D = $Model
	var tween = create_tween()
	var squash = _base_scale * Vector3(1.3, 0.7, 1.3)
	var stretch = _base_scale * Vector3(0.9, 1.1, 0.9)
	
	tween.tween_property(model, "scale", squash, 0.06).set_trans(Tween.TRANS_SINE)
	tween.tween_property(model, "scale", stretch, 0.1).set_trans(Tween.TRANS_SPRING)
	tween.tween_property(model, "scale", _base_scale, 0.1)

func _autofit_model() -> void:
	# Wait two frames: first for nodes to enter the tree, second for the
	# skeleton/animation player to update bone transforms.
	await get_tree().process_frame
	await get_tree().process_frame
	var model: Node3D = $Model

	var aabb: AABB = _collect_aabb_local(model)
	if aabb.size.y < 0.001:
		push_warning("Player: model AABB is empty — auto-fit skipped.")
		return

	var s: float   = 1.8 / aabb.size.y   # scale so total height == capsule height
	model.scale    = Vector3(s, s, s)
	# Shift down so the mesh bottom lands exactly at y = 0
	model.position = Vector3(0.0, -aabb.position.y * s, 0.0)

	# Store the fitted scale as the base for squash-and-stretch
	_base_scale = model.scale

# Returns the combined AABB of all MeshInstance3D mesh resources,
# in the mesh's native vertex space (which for GLTF skinned characters
# equals the rig-root / $Model local space, since ModelInstance sits at
# y=0 relative to $Model and the inverse-bind matrices bake the rest).
# Using mesh.get_aabb() directly avoids the Skeleton3D offset that
# Godot's GLTF importer inserts between the rig root and the mesh node,
# which otherwise cancels the feet-offset and wrongly produces aabb.y=0.
func _collect_aabb_local(node: Node) -> AABB:
	var result := AABB()
	var found  := false
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			var a := mi.mesh.get_aabb()
			if a.size.length_squared() > 0.0:
				result = a
				found  = true
	for child in node.get_children():
		var ca: AABB = _collect_aabb_local(child)
		if ca.size.length_squared() < 0.001:
			continue
		if found:
			result = result.merge(ca)
		else:
			result = ca
			found  = true
	return result
