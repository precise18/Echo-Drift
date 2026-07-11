## Third-person camera with dynamic FOV speed effect.
## Attach to the CameraYaw node (Node3D).
extends Node3D

@export var distance:       float = 5.0    ## units behind the character
@export var sensitivity:    float = 0.003
@export var follow_speed:   float = 4.0

@export var base_fov:       float = 75.0
@export var max_fov:        float = 105.0  ## FOV at full sprint
@export var fov_lerp_speed: float = 8.0
@export var free_look_delay: float = 2.0   ## Time before camera auto-follows again

@export var position_smoothing: float = 15.0 ## Camera lag/elasticity

@onready var _pitch: Node3D   = $CameraPitch
@onready var _cam:   Camera3D = $CameraPitch/Camera3D

var _free_look_timer: float = 0.0

func _ready() -> void:
	position.y = 1.4   # pivot at shoulder height
	
	# Support for both Node3D and SpringArm3D
	if _pitch is SpringArm3D:
		_pitch.spring_length = distance
		_pitch.collision_mask = 1 # Collide with world
		_cam.transform = Transform3D()
	else:
		_cam.transform  = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, distance))
		
	_pitch.rotation = Vector3(-0.18, 0.0, 0.0)  # ~10° downward
	_cam.fov        = base_fov

	
	set_as_top_level(true) # Detach from player so we can add elastic lag
	global_position = get_parent().global_position + Vector3(0, 1.4, 0)

func _physics_process(delta: float) -> void:
	var target_pos = get_parent().global_position + Vector3(0, 1.4, 0)
	global_position = global_position.lerp(target_pos, position_smoothing * delta)

func follow_behind(move_dir: Vector3, delta: float) -> void:
	if _free_look_timer > 0.0:
		_free_look_timer -= delta
		return
		
	if move_dir.length() < 0.1:
		return
	var behind_yaw := atan2(-move_dir.x, -move_dir.z)
	rotation.y = lerp_angle(rotation.y, behind_yaw, follow_speed * delta)

func update_fov(horizontal_speed: float, max_speed: float, delta: float) -> void:
	var ratio      := clampf(horizontal_speed / max_speed, 0.0, 1.0)
	var target_fov := lerpf(base_fov, max_fov, ratio)
	_cam.fov        = lerpf(_cam.fov, target_fov, fov_lerp_speed * delta)

func get_forward() -> Vector3:
	var b := global_transform.basis
	return Vector3(-b.z.x, 0.0, -b.z.z).normalized()

func get_right() -> Vector3:
	var b := global_transform.basis
	return Vector3(b.x.x, 0.0, b.x.z).normalized()

func handle_mouse(event: InputEventMouseMotion) -> void:
	_free_look_timer = free_look_delay
	rotate_y(-event.relative.x * sensitivity)
	_pitch.rotation.x = clampf(
		_pitch.rotation.x - event.relative.y * sensitivity,
		-PI / 2.5, PI / 6.0
	)


