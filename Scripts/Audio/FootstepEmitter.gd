extends AudioStreamPlayer3D
class_name FootstepEmitter
## Single responsibility: play a footstep sound every `stride` meters its
## parent actually moves. Deliberately driven by *observed position*, not
## by input or velocity — so the exact same node works for the local
## player (moved by physics), remote players (moved by
## MultiplayerSynchronizer replication), and echo ghosts (moved by
## EchoRecorder playback), with zero networking of its own: every peer
## derives every character's footsteps independently from positions it
## already has. See AUDIO_SYSTEM.md.
##
## Being an AudioStreamPlayer3D, the positional part is free: volume and
## panning follow this node relative to the local camera. Footsteps are a
## core gameplay signal in a hide-and-seek game — a Hunter can track a
## Hider (or be fooled by an echo) by ear.

## Fired every time a step actually plays, with the exact ground
## position (this node's parent's position at that instant) it happened
## at. Nothing before this pass consumed it — it exists so EchoGhost can
## spawn a footstep ripple in lockstep with the sound, without EchoGhost
## needing to reimplement (or duplicate) this class's stride/cadence
## logic. Purely additive: emitting it changes nothing about when or how
## often a step plays.
signal stepped(ground_position: Vector3)

## Meters of horizontal travel per step. Cadence scales with speed
## automatically since this is distance-based, not time-based.
@export var stride := 1.9

## A single-frame jump larger than this is a teleport (or a spawn), not
## running — reset instead of machine-gunning accumulated steps.
const TELEPORT_DELTA := 3.0
const MIN_SPEED := 0.8 # ignore sub-walking drift (interpolation settle, etc.)

var active := true

var _target: Node3D
var _has_last_position := false
var _last_position := Vector3.ZERO
var _distance_accum := 0.0


func _ready() -> void:
	_target = get_parent() as Node3D
	bus = &"SFX"
	max_distance = 18.0


func _process(delta: float) -> void:
	if _target == null or not _target.is_inside_tree():
		return

	var pos := _target.global_position
	if not _has_last_position:
		_has_last_position = true
		_last_position = pos
		return

	var step := pos - _last_position
	step.y = 0.0
	var dist := step.length()
	_last_position = pos

	if not active or dist > TELEPORT_DELTA:
		_distance_accum = 0.0
		return
	if delta <= 0.0 or dist / delta < MIN_SPEED:
		return

	_distance_accum += dist
	if _distance_accum >= stride:
		_distance_accum = fmod(_distance_accum, stride)
		pitch_scale = randf_range(0.92, 1.08) # repeats don't sound mechanical
		play()
		stepped.emit(pos)
