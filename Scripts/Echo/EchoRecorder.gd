extends Node
class_name EchoRecorder
## Single responsibility: keep a rolling buffer of a target Node3D's
## transform (and current animation name) covering the last
## `buffer_seconds`, and answer "where/what-animation was the target N
## seconds ago". Runs identically on every peer because every peer
## already receives the target's replicated transform each frame — see
## ECHO_SYSTEM.md for the full design writeup.
##
## Recording rate is decoupled from playback smoothness: samples are
## taken every `sample_interval` seconds (not every physics frame), and
## get_transform_at()/get_animation_at() interpolate between whichever
## two samples straddle the requested time. Lowering the sample rate
## trades a little positional precision for a smaller buffer — see the
## Performance section of ECHO_SYSTEM.md.

@export var buffer_seconds := 10.0
@export var sample_interval := 0.1

var target: Node3D = null

# Array of { "t": float (seconds), "xform": Transform3D, "anim": String },
# oldest first.
var _samples: Array = []
var _time_since_last_sample := 0.0


## Begins recording a new target from scratch. Any previously buffered
## history is discarded — an echo should never show a mix of two
## different players' movement.
func set_target(new_target: Node3D) -> void:
	target = new_target
	_samples.clear()
	_time_since_last_sample = 0.0


func clear() -> void:
	_samples.clear()
	_time_since_last_sample = 0.0


func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return

	_time_since_last_sample += delta
	if _time_since_last_sample < sample_interval:
		return
	_time_since_last_sample = 0.0

	var now := Time.get_ticks_msec() / 1000.0
	_samples.append({
		"t": now,
		"xform": target.global_transform,
		"anim": _current_animation_name(),
	})

	while _samples.size() > 2 and now - _samples[0]["t"] > buffer_seconds:
		_samples.pop_front()


## Assumes the target has a direct child named "AnimPlayer" (matches
## Player.tscn's convention) — returns "" for targets without one rather
## than erroring, so EchoRecorder stays usable on any Node3D.
func _current_animation_name() -> String:
	var anim_player := target.get_node_or_null("AnimPlayer") as AnimationPlayer
	return anim_player.current_animation if anim_player else ""


func has_enough_data() -> bool:
	if _samples.size() < 2:
		return false
	# Tolerance scales with sample_interval so a coarser recording rate
	# doesn't make "enough data" perpetually unreachable.
	return _samples[-1]["t"] - _samples[0]["t"] >= buffer_seconds - (sample_interval * 2.5)


## Returns an interpolated transform from `seconds_ago` in the past.
func get_transform_at(seconds_ago: float) -> Transform3D:
	if _samples.is_empty():
		return Transform3D()

	var target_time := _absolute_time(seconds_ago)
	if target_time <= _samples[0]["t"]:
		return _samples[0]["xform"]

	var pair := _straddling_samples(target_time)
	if pair.is_empty():
		return _samples[-1]["xform"]
	return pair["a"]["xform"].interpolate_with(pair["b"]["xform"], pair["f"])


## Returns which animation was playing `seconds_ago` in the past.
## Animation names are categorical (not interpolatable), so this picks
## whichever of the two straddling samples is closer in time.
func get_animation_at(seconds_ago: float) -> String:
	if _samples.is_empty():
		return ""

	var target_time := _absolute_time(seconds_ago)
	if target_time <= _samples[0]["t"]:
		return _samples[0]["anim"]

	var pair := _straddling_samples(target_time)
	if pair.is_empty():
		return _samples[-1]["anim"]
	return pair["a"]["anim"] if pair["f"] < 0.5 else pair["b"]["anim"]


func _absolute_time(seconds_ago: float) -> float:
	return Time.get_ticks_msec() / 1000.0 - seconds_ago


## Shared lookup used by both get_transform_at() and get_animation_at():
## finds the two recorded samples that straddle `target_time` and how far
## between them ("f", 0..1) that moment falls. Callers are expected to
## have already handled "at or before the oldest sample" themselves;
## an empty Dictionary here means `target_time` is at/after the newest
## sample (recording just hasn't caught up to it yet).
func _straddling_samples(target_time: float) -> Dictionary:
	for i in range(_samples.size() - 1):
		var a: Dictionary = _samples[i]
		var b: Dictionary = _samples[i + 1]
		if a["t"] <= target_time and target_time <= b["t"]:
			var span: float = b["t"] - a["t"]
			var f: float = 0.0 if span <= 0.0 else (target_time - a["t"]) / span
			return {"a": a, "b": b, "f": f}
	return {}
