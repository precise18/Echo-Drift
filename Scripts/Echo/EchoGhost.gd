extends Node3D
class_name EchoGhost
## Single responsibility: render the hider's position from N seconds ago.
## Purely visual — no collision, no gameplay authority. Hidden until the
## recorder has a full buffer so the ghost never "teleports" from nothing.

@export var delay_seconds := EchoRecorder.BUFFER_SECONDS

var recorder: EchoRecorder = null


func _process(_delta: float) -> void:
	if recorder == null or not recorder.has_enough_data():
		visible = false
		return

	visible = true
	global_transform = recorder.get_transform_at(delay_seconds)
