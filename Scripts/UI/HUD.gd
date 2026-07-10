extends CanvasLayer
## Single responsibility: reflect RoundManager state on screen and forward
## the Play Again button press back to it. Score display itself is
## delegated to Scoreboard.gd (attached to the ScoreLabel node) — this
## script only owns the timer, role label, and round-end panel.

@onready var timer_label: Label = $Margin/TopBar/TimerLabel
@onready var role_label: Label = $Margin/TopBar/RoleLabel
@onready var round_end_panel: PanelContainer = $RoundEndPanel
@onready var winner_label: Label = $RoundEndPanel/VBoxContainer/WinnerLabel
@onready var restart_button: Button = $RoundEndPanel/VBoxContainer/RestartButton


func _ready() -> void:
	round_end_panel.visible = false
	restart_button.pressed.connect(_on_restart_pressed)
	RoundManager.round_started.connect(_on_round_started)
	RoundManager.round_ended.connect(_on_round_ended)
	RoundManager.role_assigned.connect(_on_role_assigned)


func _process(_delta: float) -> void:
	if RoundManager.round_active:
		var whole_seconds := int(ceil(RoundManager.time_left))
		timer_label.text = "%02d:%02d" % [whole_seconds / 60, whole_seconds % 60]


func _on_role_assigned(peer_id: int, role: int) -> void:
	if peer_id != multiplayer.get_unique_id():
		return
	role_label.text = "You are: HIDER" if role == Role.HIDER else "You are: HUNTER"


func _on_round_started() -> void:
	round_end_panel.visible = false


func _on_round_ended(winner_role: int) -> void:
	round_end_panel.visible = true
	if winner_role == Role.HUNTER:
		winner_label.text = "Hunter wins!\nThe echoes gave you away."
	else:
		winner_label.text = "Hider wins!\nTime ran out before the hunter closed in."


func _on_restart_pressed() -> void:
	RoundManager.request_restart()
