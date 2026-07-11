extends CharacterBody3D

var HIDER_MATERIAL: Material = load("res://Materials/player_hider_material.tres")
var HUNTER_MATERIAL: Material = load("res://Materials/player_hunter_material.tres")

## Fixed height above the body root, not the (auto-fit, model-scaled)
## $Model child — see PLAYER_NAME_SYSTEM.md "Never clipping into the
## player". Comfortably above the ~1.8m capsule regardless of which
## skin/model is loaded under $Model, and immune to _autofit_model()'s
## scale/position changes since NameTag is a sibling of $Model, not a
## child of it.
const NAME_TAG_HEIGHT := 2.2

## Gameplay animation name -> CharacterRig abstract state, for skinned
## bodies. "Jump" is deliberately NOT one of CharacterRig's resolvable
## STATES, so play_state("Jump") is a graceful no-op that keeps the
## current cycle playing through airborne moments instead of snapping —
## exactly the degradation CharacterRig's own doc comment designs for.
const _RIG_STATES := {
	"idle": "Idle",
	"walk": "Walk",
	"run": "Run",
	"jump_start": "Jump",
	"jump_fall": "Jump",
}

@onready var movement = $MovementComponent
@onready var camera = $CameraYaw
@onready var anim = $AnimationComponent

var _was_airborne := false
var _base_scale := Vector3.ONE

var _chest_ray: RayCast3D
var _head_ray: RayCast3D
var is_mantling: bool = false

var peer_id: int = -1
var name_tag: Label3D

## Non-null once this body wears a CharacterRig skin (teammate system —
## see SkinRegistry/CharacterRig). Null means the stock capsule model
## and the original AnimationComponent clip path, exactly as before
## skins existed.
var _rig: CharacterRig = null

func _ready() -> void:
	peer_id = name.to_int()

	# A skin may already be known here (the host registers before the
	# scene even loads); if not, the registry-sync signal connected below
	# retries once it arrives, and the stock capsule fills in meanwhile.
	_apply_skin()
	if _rig == null:
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

	name_tag = _build_name_tag()
	add_child(name_tag)
	_refresh_name_tag()
	# Registration/(re)sync can land after this body has already spawned
	# (see PLAYER_NAME_SYSTEM.md) — re-read the registry every time it
	# changes rather than only once at spawn, so a name typed in by a
	# reconnecting or slow-to-register peer still shows up correctly.
	# Skins ride the same registry sync, so the same signal also retries
	# the (one-shot — see _apply_skin) capsule-to-skin swap.
	NetworkManager.player_names_changed.connect(_refresh_name_tag)
	NetworkManager.player_names_changed.connect(_apply_skin)

	apply_authority_state()
	_refresh_role_material()
	RoundManager.role_assigned.connect(_on_role_assigned)

func apply_authority_state() -> void:
	if is_multiplayer_authority():
		$CameraYaw/CameraPitch/Camera3D.make_current()
		if not get_window().focus_entered.is_connected(_capture_mouse):
			get_window().focus_entered.connect(_capture_mouse)
		_capture_mouse()
	elif get_window().focus_entered.is_connected(_capture_mouse):
		get_window().focus_entered.disconnect(_capture_mouse)
	# Every peer independently hides its OWN tag (you don't need to read
	# your own name, and it's one less thing between the camera and the
	# character) while always showing every other player's — a purely
	# local, per-viewer rendering decision that needs no network traffic
	# of its own, since is_multiplayer_authority() already tells each
	# peer which body is "mine" here.
	if name_tag != null:
		name_tag.visible = not is_multiplayer_authority()

func _exit_tree() -> void:
	if RoundManager.role_assigned.is_connected(_on_role_assigned):
		RoundManager.role_assigned.disconnect(_on_role_assigned)
	if NetworkManager.player_names_changed.is_connected(_refresh_name_tag):
		NetworkManager.player_names_changed.disconnect(_refresh_name_tag)
	if NetworkManager.player_names_changed.is_connected(_apply_skin):
		NetworkManager.player_names_changed.disconnect(_apply_skin)
	if get_window().focus_entered.is_connected(_capture_mouse):
		get_window().focus_entered.disconnect(_capture_mouse)

## Builds the floating name tag. Label3D is a world-space, billboard-
## capable node built exactly for this: `billboard` keeps it always
## facing the viewer's camera, and being a normal 3D node (not a
## Control/CanvasItem) means it naturally shrinks with distance under
## perspective projection the same way any other object in the world
## does — no per-frame distance math needed for either requirement.
func _build_name_tag() -> Label3D:
	var tag := Label3D.new()
	tag.name = "NameTag"
	tag.position = Vector3(0, NAME_TAG_HEIGHT, 0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.shaded = false          # always readable regardless of local lighting
	tag.no_depth_test = false   # still occludes behind walls/geometry like a real object
	tag.double_sided = true
	tag.font_size = 48
	tag.outline_size = 14
	tag.modulate = Color(0.95, 0.97, 1.0)
	tag.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	tag.pixel_size = 0.01
	return tag

## Reads the current name for this body's owning peer straight out of
## NetworkManager's already-synced registry (no RPC of its own — see
## PLAYER_NAME_SYSTEM.md). Safe to call before the registry has actually
## synced: NetworkManager.get_display_name() falls back to the same
## deterministic "Player N" the server would compute, so the tag is
## never blank.
func _refresh_name_tag() -> void:
	if name_tag != null:
		name_tag.text = NetworkManager.get_display_name(peer_id)

## Swaps the stock capsule model for this peer's chosen CharacterRig
## skin. One-shot by design: skins can't change mid-session, so once a
## rig is on, later registry syncs are ignored. Runs at spawn AND on
## every registry sync because a client's own choice round-trips through
## the server and can land after this body already spawned (same timing
## reality the name tag handles — see PLAYER_NAME_SYSTEM.md).
func _apply_skin() -> void:
	if _rig != null:
		return
	var skin_id := NetworkManager.get_peer_skin(peer_id)
	if skin_id == "":
		return # not registered yet, or this build ships no skin models
	var model: Node3D = $Model
	var old_instance := model.get_node_or_null("ModelInstance")
	if old_instance != null:
		model.remove_child(old_instance)
		old_instance.queue_free()
	_rig = CharacterRig.new()
	_rig.name = "Rig"
	model.add_child(_rig)
	_rig.set_skin(skin_id)
	# Facing/lean smoothing still belongs to AnimationComponent, but clip
	# playback belongs to the rig now — facing_only also clears anim's
	# reference to the (just freed) stock model's AnimationPlayer.
	anim.setup_facing_only(_rig)
	_autofit_model()

## Single dispatch point for gameplay animation: skinned bodies route
## through CharacterRig's abstract states (rig-agnostic clip names — the
## same states EchoRecorder ends up replaying), the stock capsule keeps
## the original AnimationComponent sample clips.
func _play_anim(anim_name: String) -> void:
	if _rig != null:
		_rig.play_state(_RIG_STATES.get(anim_name, "Idle"))
	else:
		anim.play(anim_name)

func _capture_mouse() -> void:
	if UIKit.block_mouse_capture:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_role_assigned(_peer_id: int, _role: int) -> void:
	_refresh_role_material()

func _refresh_role_material() -> void:
	# Skinned bodies keep their skin: per SkinRegistry's own rule, skins
	# are identity, not role — role lives on the HUD chip and banner, and
	# painting the whole rig blue/red would also destroy the skin's own
	# look. (Also load-bearing: ModelInstance no longer exists once a rig
	# is on.)
	if _rig != null:
		return
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
	_play_anim("jump_start")
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
			_play_anim("run" if h_speed > 5.0 else "walk")
		else:
			_play_anim("idle")
		return
		
	if is_mantling:
		return
		
	if not (RoundManager.round_active or MatchStateManager.is_in_lobby()):
		movement.tick(delta, Vector2.ZERO, false, camera.get_forward(), camera.get_right())
		_play_anim("idle")
		return
		
	var input_dir  := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
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
		_play_anim("jump_start" if movement.vertical_velocity() > 0 else "jump_fall")
	elif movement.is_moving():
		_play_anim("run" if is_running else "walk")
	else:
		_play_anim("idle")

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
