extends Node
class_name EchoSystem
## Modular echo subsystem, self-contained: owns exactly one EchoRecorder
## (the actual recording buffer) and one-or-more EchoGhost instances that
## each replay that *same* buffer at their own configurable delay. This
## is what "multiple echoes" means in this design — several simultaneous
## shadows of one recorded history, not several independent recordings —
## so the (already cheap) recording work is never duplicated per echo.
## See ECHO_SYSTEM.md for the full architecture writeup.
##
## Usage: instance this as a Node anywhere in the scene tree (see
## Main.tscn), then call set_target()/clear() as the round's Hider
## changes. Nothing else needs to know EchoRecorder or EchoGhost exist.

const ECHO_GHOST_SCENE: PackedScene = preload("res://Scenes/Player/EchoGhost.tscn")

## One entry per simultaneous echo "shadow", in seconds-in-the-past.
## Defaults to a single echo to match this MVP's tuned difficulty —
## add more entries (e.g. [5.0, 10.0]) to show multiple simultaneous
## echoes; see "Multiple echoes" in ECHO_SYSTEM.md.
@export var echo_delays: Array[float] = [10.0]
@export var buffer_seconds := 10.0
@export var sample_interval := 0.1

var recorder: EchoRecorder

## Public so callers that only care about "the" echo (e.g. Minimap showing
## the primary ghost to the Hunter) don't need to know EchoRecorder exists;
## indexed in the same order as echo_delays.
var ghosts: Array[EchoGhost] = []


func _ready() -> void:
	recorder = EchoRecorder.new()
	recorder.buffer_seconds = buffer_seconds
	recorder.sample_interval = sample_interval
	add_child(recorder)

	for delay in echo_delays:
		var ghost: EchoGhost = ECHO_GHOST_SCENE.instantiate()
		add_child(ghost)
		ghost.recorder = recorder
		ghost.delay_seconds = delay
		ghosts.append(ghost)


## Begins echoing a new target (typically called when the round's Hider
## changes). Any previous target's buffered history is discarded.
func set_target(target: Node3D) -> void:
	recorder.set_target(target)


## Stops recording entirely (not just wiping the buffer — otherwise the
## recorder would immediately start refilling it from the same target)
## and lets any active ghosts fall silent/invisible on their next
## _process, since EchoGhost hides itself once has_enough_data() goes
## false.
func clear() -> void:
	recorder.set_target(null)
