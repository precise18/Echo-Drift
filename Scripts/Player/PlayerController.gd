extends CharacterBody3D
## Single responsibility: local input -> movement for the player this peer
## owns. Non-authority instances are pure puppets driven entirely by
## MultiplayerSynchronizer and never process input or physics here.

const WALK_SPEED := 4.0
const SPRINT_SPEED := 7.5
const JUMP_VELOCITY := 6.5
const MOUSE_SENSITIVITY := 0.0035
const GROUND_ACCEL := 10.0
const AIR_ACCEL := 3.0
const PITCH_MIN := deg_to_rad(-60)
const PITCH_MAX := deg_to_rad(60)
const FACE_TURN_SPEED := 12.0

const HIDER_MATERIAL := preload("res://Materials/player_hider_material.tres")
const HUNTER_MATERIAL := preload("res://Materials/player_hunter_material.tres")

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var anim_player: AnimationPlayer = $AnimPlayer

var peer_id: int = -1
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _camera_pitch := 0.0


func _ready() -> void:
	peer_id = name.to_int()
	camera.current = is_multiplayer_authority()
	if is_multiplayer_authority():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_refresh_role_material()
	GameManager.role_assigned.connect(_on_role_assigned)


func _exit_tree() -> void:
	if GameManager.role_assigned.is_connected(_on_role_assigned):
		GameManager.role_assigned.disconnect(_on_role_assigned)


func _on_role_assigned(_peer_id: int, _role: GameManager.Role) -> void:
	_refresh_role_material()


func _refresh_role_material() -> void:
	body_mesh.material_override = HUNTER_MATERIAL if peer_id == GameManager.hunter_id else HIDER_MATERIAL


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		_camera_pitch = clampf(_camera_pitch - event.relative.y * MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX)
		spring_arm.rotation.x = _camera_pitch
	elif event.is_action_pressed("ui_cancel"):
		var capturing := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if capturing else Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if is_on_floor():
		velocity.y = -0.1
	else:
		velocity.y -= _gravity * delta

	if GameManager.round_active:
		_handle_movement_input(delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, GROUND_ACCEL * delta)
		velocity.z = move_toward(velocity.z, 0.0, GROUND_ACCEL * delta)

	move_and_slide()
	_update_animation()


func _handle_movement_input(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move_basis := camera_pivot.transform.basis
	var move_dir := (move_basis * Vector3(input_dir.x, 0.0, input_dir.y))
	move_dir.y = 0.0
	move_dir = move_dir.normalized()

	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	var target_velocity := move_dir * speed
	var accel := GROUND_ACCEL if is_on_floor() else AIR_ACCEL

	velocity.x = move_toward(velocity.x, target_velocity.x, accel * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, accel * delta)

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	if move_dir.length() > 0.1:
		var target_yaw := atan2(move_dir.x, move_dir.z)
		body_mesh.rotation.y = lerp_angle(body_mesh.rotation.y, target_yaw, FACE_TURN_SPEED * delta)


func _update_animation() -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor():
		anim_player.play("Idle")
	elif horizontal_speed > WALK_SPEED + 0.5:
		anim_player.play("Run")
	elif horizontal_speed > 0.3:
		anim_player.play("Walk")
	else:
		anim_player.play("Idle")
