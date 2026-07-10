extends Node
class_name EchoRecorder
## Single responsibility: keep a rolling buffer of a target Node3D's
## transform covering the last BUFFER_SECONDS, and answer "where was the
## target N seconds ago". Runs identically on every peer because every peer
## already receives the hider's replicated transform each frame.

const BUFFER_SECONDS := 10.0

var target: Node3D = null

# Array of { "t": float (seconds), "xform": Transform3D }, oldest first.
var _samples: Array = []


func set_target(new_target: Node3D) -> void:
	target = new_target
	_samples.clear()


func clear() -> void:
	_samples.clear()


func _physics_process(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return

	var now := Time.get_ticks_msec() / 1000.0
	_samples.append({"t": now, "xform": target.global_transform})

	while _samples.size() > 2 and now - _samples[0]["t"] > BUFFER_SECONDS:
		_samples.pop_front()


func has_enough_data() -> bool:
	if _samples.size() < 2:
		return false
	return _samples[-1]["t"] - _samples[0]["t"] >= BUFFER_SECONDS - 0.25


## Returns an interpolated transform from `seconds_ago` in the past.
func get_transform_at(seconds_ago: float) -> Transform3D:
	if _samples.is_empty():
		return Transform3D()

	var now := Time.get_ticks_msec() / 1000.0
	var target_time := now - seconds_ago

	if target_time <= _samples[0]["t"]:
		return _samples[0]["xform"]

	for i in range(_samples.size() - 1):
		var a: Dictionary = _samples[i]
		var b: Dictionary = _samples[i + 1]
		if a["t"] <= target_time and target_time <= b["t"]:
			var span: float = b["t"] - a["t"]
			var f: float = 0.0 if span <= 0.0 else (target_time - a["t"]) / span
			return a["xform"].interpolate_with(b["xform"], f)

	return _samples[-1]["xform"]
