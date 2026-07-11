extends Node3D
class_name CharacterRig
## Single responsibility: own one instantiated character model (a skin
## from SkinRegistry) and translate gameplay movement states into that
## rig's actual animations. Player bodies and echo ghosts both use this,
## which is what keeps recorded animation state replayable: the recorder
## stores abstract STATE names ("Idle"/"Walk"/"Run"), never rig-specific
## clip names, so any skin can replay any skin's history.
##
## Imported rigs name their clips inconsistently ("Walk",
## "Armature|Run", "CharacterArmature|Idle", ...), so the clip for each
## state is resolved once by case-insensitive substring match instead of
## hardcoding names. Unresolvable states fall back to Idle's clip, so a
## rig with fewer clips degrades gracefully instead of erroring.

## Abstract movement states, in resolve order. "Idle" first — it's the
## fallback for everything else.
const STATES := ["Idle", "Walk", "Run"]

var _anim_player: AnimationPlayer = null
var _state_clips: Dictionary = {} # state name -> actual clip name
var _current_state := ""


## Replaces the current model (if any) with `skin_id`'s scene, resolves
## its animation clips, and starts it idling. Safe to call repeatedly —
## that's exactly what happens when a player flips through skins in the
## lobby.
func set_skin(skin_id: String) -> void:
	for child in get_children():
		child.queue_free()
	_anim_player = null
	_state_clips.clear()
	_current_state = ""

	var scene := SkinRegistry.get_skin_scene(skin_id)
	if scene == null:
		return
	var model: Node3D = scene.instantiate()
	add_child(model)

	_anim_player = model.find_child("AnimationPlayer", true, false)
	if _anim_player == null:
		return
	_resolve_state_clips()
	play_state("Idle")


func _resolve_state_clips() -> void:
	var clip_names := _anim_player.get_animation_list()
	for state in STATES:
		for clip in clip_names:
			if clip.to_lower().contains(state.to_lower()):
				_state_clips[state] = clip
				break
	for state in STATES:
		if not _state_clips.has(state) and _state_clips.has("Idle"):
			_state_clips[state] = _state_clips["Idle"]


## Play the clip for an abstract movement state. No-ops on repeats so
## calling it every frame (as PlayerController and EchoGhost both do)
## never restarts the clip.
func play_state(state: String) -> void:
	if state == _current_state or _anim_player == null:
		return
	var clip: String = _state_clips.get(state, "")
	if clip == "":
		return
	_current_state = state
	var animation := _anim_player.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR # movement states always cycle
	_anim_player.play(clip)


## The abstract state currently playing — this is what EchoRecorder
## records (rig-agnostic, so any skin can replay it).
func get_state() -> String:
	return _current_state


## Ghost mode: paint every mesh surface with one override material (the
## translucent cyan echo look) while keeping the rig and animations —
## the echo is recognizably the hider's own skin.
func apply_ghost_material(material: Material) -> void:
	for mesh_instance: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		mesh_instance.material_override = material
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
