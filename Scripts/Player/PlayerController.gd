extends CharacterBody3D

var HIDER_MATERIAL: Material = load("res://Materials/player_hider_material.tres")
var HUNTER_MATERIAL: Material = load("res://Materials/player_hunter_material.tres")

@onready var movement: Node   = $MovementComponent
@onready var camera:   Node3D = $CameraYaw
@onready var anim:     Node   = $AnimationComponent

var _was_airborne := false
var _base_scale := Vector3.ONE

var _chest_ray: RayCast3D
var _head_ray: RayCast3D
var is_mantling: bool = false

var peer_id: int = -1

func _ready() -> void:
	peer_id = name.to_int()
	
	anim.setup($Model/ModelInstance)
	_autofit_model()   # coroutine — runs after first frame, doesn't block _ready
	
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

func apply_authority_state() -> void:
	if is_multiplayer_authority():
		camera._cam.make_current()
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
	_refresh_role_material()

func _refresh_role_material() -> void:
	# Iterate through all mesh instances and update material override
	var is_hunter = peer_id == RoundManager.hunter_id
	var mat = HUNTER_MATERIAL if is_hunter else HIDER_MATERIAL
	_apply_material_recursive($Model/ModelInstance, mat)

func _apply_material_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = mat
	for child in node.get_children():
		_apply_material_recursive(child, mat)

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
		var v_speed = pos_delta.y / delta
		
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
	
	# Ledge Grabbing Logic
	if is_airborne and movement.vertical_velocity() < 0.0:
		if _chest_ray.is_colliding() and not _head_ray.is_colliding():
			_execute_mantle()
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
	await get_tree().process_frame   
	var model: Node3D = $Model
	var aabb: AABB    = _node_aabb(model)
	if aabb.size.y < 0.001:
		push_warning("Player: model AABB is empty — auto-fit skipped.")
		return
	var s: float      = 1.8 / aabb.size.y   
	model.scale       = Vector3(s, s, s)
	model.position.y  = -(aabb.position.y * s) + 0.5  

func _node_aabb(node: Node3D) -> AABB:
	var result := AABB()
	var found  := false
	if node is MeshInstance3D:
		var a: AABB = (node as MeshInstance3D).get_aabb()
		if a.size.length_squared() > 0.0:
			result = node.transform * a
			found  = true
	for child: Node in node.get_children():
		if not (child is Node3D):
			continue
		var ca: AABB = _node_aabb(child as Node3D)
		if ca.size.length_squared() < 0.001:
			continue
		var in_parent: AABB = (child as Node3D).transform * ca
		if found:
			result = result.merge(in_parent)
		else:
			result = in_parent
			found  = true
	return result
