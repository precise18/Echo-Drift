extends Node3D
class_name EchoGhost
## Single responsibility: render one target's position, animation, and a
## positional audio cue from `delay_seconds` in the past, by reading from
## an EchoRecorder it doesn't own. Purely visual/audio — no collision, no
## gameplay authority, no recording logic of its own.
##
## Hidden and silent until the recorder has a full buffer, so the ghost
## never "teleports" or plays a sound from nothing. Multiple EchoGhost
## instances can point at the same EchoRecorder with different
## `delay_seconds` values to show several simultaneous echoes of one
## recorded history — see EchoSystem.gd and ECHO_SYSTEM.md.

@export var delay_seconds := 10.0

var recorder: EchoRecorder = null

@onready var _anim_player: AnimationPlayer = $AnimPlayer
@onready var _audio: EchoAudio = $EchoAudio

var _current_anim := ""


func _process(_delta: float) -> void:
	if recorder == null or not recorder.has_enough_data():
		_set_active(false)
		return

	_set_active(true)
	global_transform = recorder.get_transform_at(delay_seconds)
	_update_animation()


func _update_animation() -> void:
	var anim_name := recorder.get_animation_at(delay_seconds)
	if anim_name == "" or anim_name == _current_anim:
		return
	if _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name)
		_current_anim = anim_name


func _set_active(active: bool) -> void:
	if visible == active:
		return
	visible = active
	if active:
		_audio.begin()
	else:
		_audio.stop()
		_current_anim = ""
