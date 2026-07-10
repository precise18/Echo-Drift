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
@onready var connection_status_label: Label = $ConnectionStatusLabel


func _ready() -> void:
	round_end_panel.visible = false
	connection_status_label.visible = false
	restart_button.pressed.connect(_on_restart_pressed)
	RoundManager.round_started.connect(_on_round_started)
	RoundManager.round_ended.connect(_on_round_ended)
	RoundManager.role_assigned.connect(_on_role_assigned)
	NetworkManager.reconnect_grace_started.connect(_on_reconnect_grace_started)
	NetworkManager.reconnect_grace_ended.connect(_on_reconnect_grace_ended)


var _grace_deadline := -1.0


func _process(_delta: float) -> void:
	if RoundManager.round_active:
		var whole_seconds := int(ceil(RoundManager.time_left))
		timer_label.text = "%02d:%02d" % [whole_seconds / 60, whole_seconds % 60]

	if _grace_deadline > 0.0:
		var remaining := maxf(_grace_deadline - Time.get_ticks_msec() / 1000.0, 0.0)
		connection_status_label.text = "Opponent disconnected — waiting %ds to reconnect..." % ceili(remaining)


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


func _on_reconnect_grace_started(_role: int) -> void:
	_grace_deadline = Time.get_ticks_msec() / 1000.0 + NetworkManager.RECONNECT_GRACE_PERIOD
	connection_status_label.visible = true


## Covers both outcomes the same way on purpose: if they reconnected,
## role_assigned/round_started (from RoundManager's resync) already
## refresh the rest of the HUD; if the window expired, Main.gd's own
## listener already called RoundManager.reset_state(), which leaves the
## HUD in its normal "no active round" appearance. Either way, the only
## thing this label needs to do is get out of the way.
func _on_reconnect_grace_ended(_role: int, _reconnected: bool) -> void:
	_grace_deadline = -1.0
	connection_status_label.visible = false
