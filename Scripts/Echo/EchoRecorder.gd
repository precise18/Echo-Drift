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
# oldest first (so "t" is sorted ascending — _straddling_samples relies
# on that to binary-search).
var _samples: Array = []
var _time_since_last_sample := 0.0

# Cached per-target so recording doesn't re-resolve the node path on
# every sample (see _current_animation_name).
var _target_anim_player: AnimationPlayer = null


## Begins recording a new target from scratch. Any previously buffered
## history is discarded — an echo should never show a mix of two
## different players' movement.
func set_target(new_target: Node3D) -> void:
	target = new_target
	_target_anim_player = _find_anim_player(target) if target != null else null
	_samples.clear()
	_time_since_last_sample = 0.0


## Player.tscn's AnimationPlayer lives inside its imported model
## (Model/ModelInstance/... at whatever depth the import produced), not
## as a direct child literally named "AnimPlayer" — mirrors
## AnimationComponent's own lookup (Scripts/Player/components/
## animation_component.gd) so recording actually finds the same node
## driving the player's real animation state instead of silently finding
## nothing and recording an empty anim name for every sample.
func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var result := _find_anim_player(child)
		if result:
			return result
	return null


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


func _current_animation_name() -> String:
	if _target_anim_player == null or not is_instance_valid(_target_anim_player):
		return ""
	return _target_anim_player.current_animation


func has_enough_data() -> bool:
	if _samples.size() < 2:
		return false
	# Tolerance scales with sample_interval so a coarser recording rate
	# doesn't make "enough data" perpetually unreachable.
	return _samples[-1]["t"] - _samples[0]["t"] >= buffer_seconds - (sample_interval * 2.5)


## One lookup answering both "where" and "which animation" `seconds_ago`
## — EchoGhost calls this once per frame instead of two separate
## searches. Returns { "xform": Transform3D, "anim": String }.
## Animation names are categorical (not interpolatable), so the closer
## of the two straddling samples wins for "anim".
func sample_at(seconds_ago: float) -> Dictionary:
	if _samples.is_empty():
		return {"xform": Transform3D(), "anim": ""}

	var target_time := _absolute_time(seconds_ago)
	var oldest: Dictionary = _samples[0]
	if target_time <= oldest["t"]:
		return {"xform": oldest["xform"], "anim": oldest["anim"]}

	var newest: Dictionary = _samples[-1]
	if target_time >= newest["t"]:
		return {"xform": newest["xform"], "anim": newest["anim"]}

	# Samples are appended in time order, so "t" is sorted: binary-search
	# for the first sample at/after target_time instead of scanning the
	# whole buffer (O(log n) per ghost-frame instead of O(n)).
	var lo := 0
	var hi := _samples.size() - 1
	while lo < hi:
		var mid := (lo + hi) / 2
		if _samples[mid]["t"] < target_time:
			lo = mid + 1
		else:
			hi = mid
	var b: Dictionary = _samples[lo]
	var a: Dictionary = _samples[lo - 1]

	var span: float = b["t"] - a["t"]
	var f: float = 0.0 if span <= 0.0 else (target_time - a["t"]) / span
	return {
		"xform": a["xform"].interpolate_with(b["xform"], f),
		"anim": a["anim"] if f < 0.5 else b["anim"],
	}


## Compatibility wrappers around sample_at() (see ECHO_SYSTEM.md's public
## API); prefer sample_at() when you need both answers in one frame.
func get_transform_at(seconds_ago: float) -> Transform3D:
	return sample_at(seconds_ago)["xform"]


func get_animation_at(seconds_ago: float) -> String:
	return sample_at(seconds_ago)["anim"]


func _absolute_time(seconds_ago: float) -> float:
	return Time.get_ticks_msec() / 1000.0 - seconds_ago
