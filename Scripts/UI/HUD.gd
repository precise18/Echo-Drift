extends CanvasLayer
## Single responsibility: reflect GameManager state on screen and forward
## the Play Again button press back to GameManager.

@onready var timer_label: Label = $Margin/TopBar/TimerLabel
@onready var role_label: Label = $Margin/TopBar/RoleLabel
@onready var score_label: Label = $Margin/TopBar/ScoreLabel
@onready var round_end_panel: PanelContainer = $RoundEndPanel
@onready var winner_label: Label = $RoundEndPanel/VBoxContainer/WinnerLabel
@onready var restart_button: Button = $RoundEndPanel/VBoxContainer/RestartButton


func _ready() -> void:
	round_end_panel.visible = false
	restart_button.pressed.connect(_on_restart_pressed)
	GameManager.round_started.connect(_on_round_started)
	GameManager.round_ended.connect(_on_round_ended)
	GameManager.role_assigned.connect(_on_role_assigned)
	_refresh_score()


func _process(_delta: float) -> void:
	if GameManager.round_active:
		var whole_seconds := int(ceil(GameManager.time_left))
		timer_label.text = "%02d:%02d" % [whole_seconds / 60, whole_seconds % 60]


func _on_role_assigned(peer_id: int, role: GameManager.Role) -> void:
	if peer_id != multiplayer.get_unique_id():
		return
	role_label.text = "You are: HIDER" if role == GameManager.Role.HIDER else "You are: HUNTER"


func _on_round_started() -> void:
	round_end_panel.visible = false


func _on_round_ended(winner_role: GameManager.Role, _hunter_score: int, _hider_score: int) -> void:
	round_end_panel.visible = true
	if winner_role == GameManager.Role.HUNTER:
		winner_label.text = "Hunter wins!\nThe echoes gave you away."
	else:
		winner_label.text = "Hider wins!\nTime ran out before the hunter closed in."
	_refresh_score()


func _refresh_score() -> void:
	score_label.text = "Hunter %d — %d Hider" % [GameManager.hunter_score, GameManager.hider_score]


func _on_restart_pressed() -> void:
	GameManager.request_restart()
