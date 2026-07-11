## Loads and drives character animations.
extends Node

@export var turn_speed: float = 9.0
@export var crossfade_time: float = 0.1  ## Snappy blending between states

@export var speed_idle:  float = 1.0
@export var speed_walk:  float = 1.5
@export var speed_run:   float = 1.8
@export var speed_jump:  float = 1.5

@export var glb_walk:       String = "res://Assets/Characters/animations/walk/sample_1_walk.glb"
@export var glb_run:        String = "res://Assets/Characters/animations/run/sample_1_run.glb"
@export var glb_jump_start: String = "res://Assets/Characters/animations/jump_start/sample_1_jump_start.glb"
@export var glb_jump:       String = "res://Assets/Characters/animations/jump/sample_1_jump.glb"
@export var glb_jump_fall:  String = "res://Assets/Characters/animations/jump_fall/sample_1_jump_fall.glb"
@export var glb_jump_end:   String = "res://Assets/Characters/animations/jump_end/sample_1_jump_end.glb"

var _anim_player: AnimationPlayer = null
var _model_root:  Node3D          = null
var _current:     String          = ""

func setup(model_root: Node3D) -> void:
	_current     = ""   # reset so play() doesn't skip the first call on a fresh model
	_model_root  = model_root
	_anim_player = _find_anim_player(model_root)
	if not _anim_player:
		push_warning("AnimationComponent: no AnimationPlayer found.")
		return

	_normalize_default_library()
	_merge_glb(glb_walk)
	_merge_glb(glb_run)
	_merge_glb(glb_jump_start)
	_merge_glb(glb_jump)
	_merge_glb(glb_jump_fall)
	_merge_glb(glb_jump_end)

	play("idle")

@export var lean_amount: float = 0.15

func face_direction(dir: Vector3, delta: float) -> void:
	if _model_root == null or dir.length() < 0.1:
		if _model_root:
			_model_root.rotation.z = lerp_angle(_model_root.rotation.z, 0.0, turn_speed * delta)
		return
		
	var target_yaw: float = atan2(dir.x, dir.z)
	var yaw_diff = wrapf(target_yaw - _model_root.rotation.y, -PI, PI)
	
	_model_root.rotation.y = lerp_angle(_model_root.rotation.y, target_yaw, turn_speed * delta)
	
	var target_lean = clamp(-yaw_diff * lean_amount * 1.5, -0.15, 0.15)
	_model_root.rotation.z = lerp_angle(_model_root.rotation.z, target_lean, turn_speed * delta)

func play(name: String) -> void:
	if not _anim_player or _current == name:
		return
	if _anim_player.has_animation(name):
		# Crossfade animations for AAA smoothness
		_anim_player.play(name, crossfade_time)
		_current = name
		match name:
			"idle":       _anim_player.speed_scale = speed_idle
			"walk":       _anim_player.speed_scale = speed_walk
			"run":        _anim_player.speed_scale = speed_run
			_:            _anim_player.speed_scale = speed_jump

# ── internals ──────────────────────────────────────────────────────────────────

func _normalize_default_library() -> void:
	var lib: AnimationLibrary = _anim_player.get_animation_library("")
	if not lib:
		return
	for raw: String in lib.get_animation_list():
		if raw == "RESET":
			continue
		var parts: PackedStringArray = raw.split("|")
		var clean: String = parts[parts.size() - 1]
		if clean != raw:
			var anim = lib.get_animation(raw).duplicate()
			if clean in ["idle", "walk", "run"]:
				anim.loop_mode = Animation.LOOP_LINEAR
			lib.add_animation(clean, anim)
			lib.remove_animation(raw)
		else:
			var anim = lib.get_animation(raw)
			if clean in ["idle", "walk", "run"]:
				anim.loop_mode = Animation.LOOP_LINEAR

func _merge_glb(path: String) -> void:
	if path.is_empty():
		return
	var scene: PackedScene = load(path) as PackedScene
	if not scene:
		return

	var inst: Node = scene.instantiate()
	var ext_ap: AnimationPlayer = _find_anim_player(inst)

	if ext_ap:
		var lib: AnimationLibrary = _anim_player.get_animation_library("")
		if not lib:
			lib = AnimationLibrary.new()
			_anim_player.add_animation_library("", lib)

		for raw: String in ext_ap.get_animation_list():
			if raw == "RESET":
				continue
			var parts: PackedStringArray = raw.split("|")
			var clean: String = parts[parts.size() - 1]
			if not lib.has_animation(clean):
				var anim = ext_ap.get_animation(raw).duplicate()
				if clean in ["idle", "walk", "run"]:
					anim.loop_mode = Animation.LOOP_LINEAR
				lib.add_animation(clean, anim)

	inst.queue_free()

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var result: AnimationPlayer = _find_anim_player(child)
		if result:
			return result
	return null
