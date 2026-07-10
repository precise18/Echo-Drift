class_name SoundFactory
## Every sound in the game, synthesized at runtime into plain
## AudioStreamWAV resources — no external audio files, matching the
## project's license-clean procedural approach (see Assets/README.md and
## EchoAudio.gd, which established this pattern for the echo hum). Each
## sound is built once on first request and cached, so repeated play()
## calls share one stream. Swapping any of these for a real recorded
## asset later means changing one function here — nothing that *plays*
## audio knows or cares that the stream was synthesized.
##
## All generators are deterministic (fixed RNG seeds) so every player
## hears the same game. See AUDIO_SYSTEM.md.

const SFX_RATE := 22050
const LOOP_RATE := 11025
const PAD_RATE := 8000 # music/hum pads have no content above ~1kHz — cheaper to build

static var _cache: Dictionary = {}


# ---------------------------------------------------------------------------
# One-shot SFX
# ---------------------------------------------------------------------------

## A short, soft thud-plus-scuff. Played with slight per-step pitch
## randomization by FootstepEmitter so repeats don't sound mechanical.
static func footstep() -> AudioStreamWAV:
	if _cache.has("footstep"):
		return _cache["footstep"]
	var samples := _footstep_impulse(0.09, 1.0)
	_cache["footstep"] = _wav(samples, SFX_RATE, false)
	return _cache["footstep"]


## A footstep with a reverberant, hollow tail — the same impulse as
## footstep() plus two decaying delay taps and a faint tonal ping in the
## echo system's register, so a ghost's steps are recognizably "the same
## sound, but wrong": you can tell an echo from the real player by ear.
static func echo_footstep() -> AudioStreamWAV:
	if _cache.has("echo_footstep"):
		return _cache["echo_footstep"]
	var impulse := _footstep_impulse(0.09, 0.7)
	var n := int(0.55 * SFX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	# Dry hit plus taps at 140ms/300ms, each quieter and duller.
	for tap in [[0, 1.0], [int(0.14 * SFX_RATE), 0.45], [int(0.30 * SFX_RATE), 0.22]]:
		var offset: int = tap[0]
		var gain: float = tap[1]
		for i in impulse.size():
			if offset + i < n:
				samples[offset + i] += impulse[i] * gain
	# The faint ping that ties it to the echo/ghost sound language.
	for i in n:
		var t := float(i) / SFX_RATE
		samples[i] += sin(TAU * 660.0 * t) * exp(-t * 9.0) * 0.05
		samples[i] = clampf(samples[i], -1.0, 1.0)
	_cache["echo_footstep"] = _wav(samples, SFX_RATE, false)
	return _cache["echo_footstep"]


## A rising sweep with a shimmer partial — played positionally at both
## ends of a teleport jump (see TeleportPad.gd).
static func teleport() -> AudioStreamWAV:
	if _cache.has("teleport"):
		return _cache["teleport"]
	var duration := 0.45
	var n := int(duration * SFX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var phase := 0.0
	var shimmer_phase := 0.0
	for i in n:
		var t := float(i) / SFX_RATE
		var progress := t / duration
		var freq := 280.0 * pow(980.0 / 280.0, progress) # exponential rise
		phase += TAU * freq / SFX_RATE
		shimmer_phase += TAU * freq * 2.01 / SFX_RATE # slightly detuned octave = shimmer
		var env := sin(PI * progress) # smooth in and out, no clicks
		samples[i] = (sin(phase) * 0.5 + sin(shimmer_phase) * 0.15) * env
	_cache["teleport"] = _wav(samples, SFX_RATE, false)
	return _cache["teleport"]


static func ui_click() -> AudioStreamWAV:
	if _cache.has("ui_click"):
		return _cache["ui_click"]
	_cache["ui_click"] = _wav(_blip(880.0, 0.06, 80.0, 0.4), SFX_RATE, false)
	return _cache["ui_click"]


static func ui_hover() -> AudioStreamWAV:
	if _cache.has("ui_hover"):
		return _cache["ui_hover"]
	_cache["ui_hover"] = _wav(_blip(660.0, 0.045, 90.0, 0.2), SFX_RATE, false)
	return _cache["ui_hover"]


# ---------------------------------------------------------------------------
# Round stings (non-positional — played by AudioManager)
# ---------------------------------------------------------------------------

## Two quick ascending notes: "go".
static func round_start() -> AudioStreamWAV:
	if _cache.has("round_start"):
		return _cache["round_start"]
	_cache["round_start"] = _wav(_pluck_sequence([440.0, 659.25], 0.16, 0.6, 0.35), SFX_RATE, false)
	return _cache["round_start"]


## A gong-ish, deliberately neutral hit — the round is over, but this
## sound doesn't say who won; the victory/defeat jingle that follows does.
static func round_end() -> AudioStreamWAV:
	if _cache.has("round_end"):
		return _cache["round_end"]
	var duration := 1.4
	var n := int(duration * SFX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t := float(i) / SFX_RATE
		var env := exp(-t * 3.0) * minf(t * 100.0, 1.0)
		# Slightly inharmonic partials read as "struck metal" rather than a note.
		samples[i] = (sin(TAU * 220.0 * t) + 0.6 * sin(TAU * 277.0 * t) + 0.35 * sin(TAU * 331.0 * t)) * env * 0.3
	_cache["round_end"] = _wav(samples, SFX_RATE, false)
	return _cache["round_end"]


## Ascending major arpeggio — you won.
static func victory() -> AudioStreamWAV:
	if _cache.has("victory"):
		return _cache["victory"]
	_cache["victory"] = _wav(_pluck_sequence([523.25, 659.25, 783.99, 1046.5], 0.13, 0.9, 0.3), SFX_RATE, false)
	return _cache["victory"]


## Slow descending minor line — you lost.
static func defeat() -> AudioStreamWAV:
	if _cache.has("defeat"):
		return _cache["defeat"]
	_cache["defeat"] = _wav(_pluck_sequence([440.0, 349.23, 293.66], 0.24, 0.8, 0.3), SFX_RATE, false)
	return _cache["defeat"]


# ---------------------------------------------------------------------------
# Loops (seamless — see the frequency-quantization note on _music below)
# ---------------------------------------------------------------------------

## The ambient music bed: a slow two-chord pad (A minor <-> F major)
## crossfading over a 12-second loop. Loops seamlessly because (a) the two
## chords' crossfade windows (sin^2 / cos^2, so they always sum to 1) are
## periodic in the loop length, and (b) every note frequency is quantized
## to a whole number of cycles per loop, so phase at the loop point
## matches phase at the start exactly. The quantization error is far below
## anything audible.
static func music_loop() -> AudioStreamWAV:
	if _cache.has("music"):
		return _cache["music"]
	var loop_len := 12.0
	var chord_a := _quantize_freqs([110.0, 220.0, 261.63, 329.63], loop_len) # A minor
	var chord_b := _quantize_freqs([174.61, 220.0, 261.63, 349.23], loop_len) # F major
	var n := int(loop_len * PAD_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t := float(i) / PAD_RATE
		var blend := pow(sin(PI * t / loop_len), 2.0) # 0 at loop point, so chord A can drop out freely
		var v := 0.0
		for f in chord_a:
			v += sin(TAU * f * t) * blend
		for f in chord_b:
			v += sin(TAU * f * t) * (1.0 - blend)
		samples[i] = v * 0.11
	_cache["music"] = _wav(samples, PAD_RATE, true)
	return _cache["music"]


## Environment ambience: filtered brown noise with a slow gust swell.
## Loops via a short crossfade of the buffer's tail into its head.
static func wind_loop() -> AudioStreamWAV:
	if _cache.has("wind"):
		return _cache["wind"]
	var loop_len := 6.0
	var fade := int(0.3 * LOOP_RATE)
	var n := int(loop_len * LOOP_RATE)
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var state := 0.0
	var lowpass := 0.0
	for i in raw.size():
		var t := float(i) / LOOP_RATE
		state = state * 0.997 + rng.randf_range(-1.0, 1.0) * 0.05 # brown-ish random walk
		lowpass += (state - lowpass) * 0.12
		var gust := 0.65 + 0.35 * sin(TAU * 2.0 * t / loop_len) # two gusts per loop, periodic
		raw[i] = lowpass * gust * 0.9
	var samples := raw.slice(0, n)
	for i in fade:
		var mix := float(i) / fade
		samples[i] = samples[i] * mix + raw[n + i] * (1.0 - mix)
	_cache["wind"] = _wav(samples, LOOP_RATE, true)
	return _cache["wind"]


## The mirror pool's positional hum: two barely-detuned low sines whose
## beat frequency gives a slow pulse, plus a quiet octave. All frequencies
## quantized to the loop length, so it loops seamlessly.
static func pool_hum_loop() -> AudioStreamWAV:
	if _cache.has("pool_hum"):
		return _cache["pool_hum"]
	var loop_len := 4.0
	var freqs := _quantize_freqs([110.0, 110.5, 220.0], loop_len)
	var n := int(loop_len * PAD_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t := float(i) / PAD_RATE
		samples[i] = (sin(TAU * freqs[0] * t) * 0.5 + sin(TAU * freqs[1] * t) * 0.5 + sin(TAU * freqs[2] * t) * 0.15) * 0.22
	_cache["pool_hum"] = _wav(samples, PAD_RATE, true)
	return _cache["pool_hum"]


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## The shared footstep impulse: a fast-decaying burst of lowpassed noise
## (the scuff) over a low sine thump (the heel).
static func _footstep_impulse(duration: float, gain: float) -> PackedFloat32Array:
	var n := int(duration * SFX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var noise := 0.0
	for i in n:
		var t := float(i) / SFX_RATE
		var env := exp(-t * 45.0)
		noise = noise * 0.82 + rng.randf_range(-1.0, 1.0) * 0.18
		var thump := sin(TAU * 85.0 * t) * exp(-t * 30.0)
		samples[i] = (noise * 1.6 + thump * 0.9) * env * 0.7 * gain
	return samples


## A tiny sine blip with exponential decay — the whole UI sound palette.
static func _blip(freq: float, duration: float, decay: float, amp: float) -> PackedFloat32Array:
	var n := int(duration * SFX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t := float(i) / SFX_RATE
		samples[i] = sin(TAU * freq * t) * exp(-t * decay) * minf(t * 400.0, 1.0) * amp
	return samples


## A sequence of soft plucked notes, each ringing out under the ones that
## follow — enough to make every sting/jingle in the game from one helper.
static func _pluck_sequence(freqs: Array, note_len: float, tail: float, amp: float) -> PackedFloat32Array:
	var total := freqs.size() * note_len + tail
	var n := int(total * SFX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	for note_i in freqs.size():
		var start := int(note_i * note_len * SFX_RATE)
		var f: float = freqs[note_i]
		for i in range(start, n):
			var t := float(i - start) / SFX_RATE
			var env := exp(-t * 4.0) * minf(t * 60.0, 1.0)
			samples[i] += (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * env * amp
	for i in n:
		samples[i] = clampf(samples[i], -1.0, 1.0)
	return samples


## Snap each frequency to a whole number of cycles per loop, which is what
## makes a sine loop seamlessly. The shift is at most 1/(2*loop_len) Hz —
## inaudible.
static func _quantize_freqs(freqs: Array, loop_len: float) -> Array:
	var out := []
	for f in freqs:
		out.append(round(f * loop_len) / loop_len)
	return out


static func _wav(samples: PackedFloat32Array, rate: int, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav
