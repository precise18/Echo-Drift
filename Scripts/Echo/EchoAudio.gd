extends AudioStreamPlayer3D
class_name EchoAudio
## Single responsibility: give the echo ghost a positional audio cue.
## This MVP ships with no external audio assets (see Assets/README.md),
## so a soft looping tone is synthesized at runtime via
## AudioStreamGenerator instead of requiring a licensed sound file —
## swap `stream` for a real asset later without touching EchoGhost.gd at
## all, since it only ever calls the inherited play()/stop().
##
## Being an AudioStreamPlayer3D, volume/panning automatically follow this
## node's position relative to the listener (the local player's camera)
## — no extra code needed for the "positional" part.

const SAMPLE_RATE := 22050.0
const FREQUENCY := 220.0 # a low, unobtrusive hum (A3)
const AMPLITUDE := 0.15

var _playback: AudioStreamGeneratorPlayback
var _phase := 0.0


func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = SAMPLE_RATE
	generator.buffer_length = 0.2
	stream = generator
	max_distance = 15.0
	unit_size = 4.0


## Distinct name from the inherited play() because it also (re)acquires
## the generator playback handle needed to push samples each frame.
func begin() -> void:
	if playing:
		return
	_phase = 0.0
	play()
	_playback = get_stream_playback()


func _process(_delta: float) -> void:
	if not playing or _playback == null:
		return

	var frames_available := _playback.get_frames_available()
	for _i in range(frames_available):
		var sample := sin(_phase) * AMPLITUDE
		_playback.push_frame(Vector2(sample, sample))
		_phase = fmod(_phase + TAU * FREQUENCY / SAMPLE_RATE, TAU)
