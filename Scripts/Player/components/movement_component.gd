## Handles all physics: velocity, gravity, jumping.
## Drop onto any CharacterBody3D child node to add movement.
extends Node

@export var walk_speed:    float = 4.0
@export var run_speed:     float = 9.0
@export var jump_velocity: float = 6.5

@export var acceleration:  float = 45.0
@export var friction:      float = 60.0
@export var air_control:   float = 15.0

@export var coyote_time:   float = 0.15
@export var jump_buffer:   float = 0.15
@export var fall_gravity_multiplier: float = 1.8

var direction := Vector3.ZERO

var _body: CharacterBody3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0

func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	assert(_body != null, "MovementComponent must be a child of CharacterBody3D")
	_body.floor_snap_length = 0.5

func tick(delta: float, input_dir: Vector2, is_running: bool,
		cam_fwd: Vector3, cam_right: Vector3) -> void:
	
	# Coyote Time & Gravity
	if _body.is_on_floor() and _body.velocity.y <= 0.0:
		_coyote_timer = coyote_time
		_body.floor_snap_length = 0.5
	else:
		_coyote_timer -= delta
		var current_gravity = _gravity
		if _body.velocity.y < 0.0 or not Input.is_action_pressed("jump"):
			current_gravity *= fall_gravity_multiplier
		_body.velocity.y -= current_gravity * delta

	# Jump Buffering
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer
	else:
		_jump_buffer_timer -= delta

	# Jump execution
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		_body.velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		_body.floor_snap_length = 0.0

	# Direction & Speed
	direction = (cam_fwd * (-input_dir.y) + cam_right * input_dir.x)
	var target_speed := run_speed if is_running else walk_speed
	var current_accel = acceleration if _body.is_on_floor() else air_control
	
	if direction.length() > 0.1:
		direction = direction.normalized()
		_body.velocity.x = move_toward(_body.velocity.x, direction.x * target_speed, current_accel * delta)
		_body.velocity.z = move_toward(_body.velocity.z, direction.z * target_speed, current_accel * delta)
	else:
		var current_friction = friction if _body.is_on_floor() else air_control
		_body.velocity.x = move_toward(_body.velocity.x, 0.0, current_friction * delta)
		_body.velocity.z = move_toward(_body.velocity.z, 0.0, current_friction * delta)

	_body.move_and_slide()

func is_moving() -> bool:
	var horizontal_velocity = Vector2(_body.velocity.x, _body.velocity.z)
	return horizontal_velocity.length() > 0.1

func is_airborne() -> bool:
	return not _body.is_on_floor()

func vertical_velocity() -> float:
	return _body.velocity.y
