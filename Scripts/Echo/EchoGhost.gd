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

const GHOST_CYAN := Color(0.55, 0.95, 1.0) # matches GlowLight / ghost_material.tres

@export var delay_seconds := 10.0

var recorder: EchoRecorder = null

@onready var _anim_player: AnimationPlayer = $AnimPlayer
@onready var _audio: EchoAudio = $EchoAudio

var _current_anim := ""
var _trail: GPUParticles3D
var _footsteps: FootstepEmitter


func _ready() -> void:
	# Feet-height so the trail reads as footsteps left behind, not a halo
	# around the ghost's body. World-space (see MapKit.make_trail_particles)
	# so it stays behind as the ghost moves along its recorded path.
	_trail = MapKit.make_trail_particles(GHOST_CYAN, 10, "Trail")
	_trail.position = Vector3(0, 0.1, 0)
	add_child(_trail)

	# The ghost's replayed movement gets footsteps too — same emitter as a
	# live player but with the reverberant echo variant, so a Hunter can
	# tell "real steps" from "echo steps" by ear (see SoundFactory.
	# echo_footstep). Off until the ghost is actually visible/replaying.
	_footsteps = FootstepEmitter.new()
	_footsteps.name = "EchoFootsteps"
	_footsteps.stream = SoundFactory.echo_footstep()
	_footsteps.active = false
	add_child(_footsteps)


func _process(_delta: float) -> void:
	if recorder == null or not recorder.has_enough_data():
		_set_active(false)
		return

	_set_active(true)
	# One buffer lookup per frame answers both position and animation
	# (see EchoRecorder.sample_at).
	var sample := recorder.sample_at(delay_seconds)
	global_transform = sample["xform"]
	_update_animation(sample["anim"])


func _update_animation(anim_name: String) -> void:
	if anim_name == "" or anim_name == _current_anim:
		return
	if _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name)
		_current_anim = anim_name


func _set_active(active: bool) -> void:
	if visible == active:
		return
	visible = active
	_trail.emitting = active
	_footsteps.active = active
	if active:
		_audio.begin()
	else:
		_audio.stop()
		_current_anim = ""
