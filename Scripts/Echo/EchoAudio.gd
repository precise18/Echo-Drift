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

## A slow, gentle frequency wobble — the difference between "a machine
## hum" and "something not quite steady, not quite real". Cheap: one more
## sine evaluated per sample, reusing work this generator already does
## every frame regardless.
const VIBRATO_RATE := 0.35 # Hz
const VIBRATO_DEPTH := 3.0 # +/- Hz frequency deviation

var _playback: AudioStreamGeneratorPlayback
var _phase := 0.0
var _vibrato_phase := 0.0


func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = SAMPLE_RATE
	generator.buffer_length = 0.2
	stream = generator
	bus = &"SFX" # a gameplay cue like footsteps, not background ambience
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
		_vibrato_phase = fmod(_vibrato_phase + TAU * VIBRATO_RATE / SAMPLE_RATE, TAU)
		var wobbled_freq := FREQUENCY + sin(_vibrato_phase) * VIBRATO_DEPTH
		var sample := sin(_phase) * AMPLITUDE
		_playback.push_frame(Vector2(sample, sample))
		_phase = fmod(_phase + TAU * wobbled_freq / SAMPLE_RATE, TAU)
