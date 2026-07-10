class_name RoundTimer extends Node
## Reusable countdown component. Owns no game rules of its own —
## RoundManager decides what "expired" means and what to do about it;
## this class only counts down and announces when it hits zero.

signal expired

var time_left: float = 0.0
var running: bool = false


func _ready() -> void:
	# Only ticks while a countdown is actually running (start/stop toggle
	# processing) instead of branching every physics frame forever.
	set_physics_process(false)


func start(duration: float) -> void:
	time_left = duration
	running = true
	set_physics_process(true)


func stop() -> void:
	running = false
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	time_left = maxf(time_left - delta, 0.0)
	if time_left <= 0.0:
		running = false
		set_physics_process(false)
		expired.emit()
