extends Label
class_name Scoreboard
## Single responsibility: render the match score. Deliberately independent
## of HUD's other concerns (timer, role label, round-end panel) — it only
## knows about MatchStateManager, so it could be dropped into any scene
## (a future pause menu, a spectator view, etc.) and keep working.


func _ready() -> void:
	MatchStateManager.score_changed.connect(_on_score_changed)
	_refresh()


func _on_score_changed(_hunter_score: int, _hider_score: int) -> void:
	_refresh()


func _refresh() -> void:
	text = "Hunter %d — %d Hider" % [MatchStateManager.hunter_score, MatchStateManager.hider_score]
