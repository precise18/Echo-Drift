extends Node
## Autoload: tracks state that spans the whole play session — cumulative
## score and which phase the match is currently in — as distinct from
## RoundManager, which only ever knows about the *current* round.
##
## This MVP doesn't have a "first to N wins" match-ending rule (the brief
## calls for endless replayability: "Play again" after every round), so
## MatchPhase never reaches a terminal "match over" state on its own —
## but keeping match-level bookkeeping in its own module means that rule
## could be added later (see GAMEPLAY_SYSTEMS.md) without touching round
## orchestration at all.

enum MatchPhase { LOBBY, ROUND_ACTIVE, ROUND_ENDED }

signal score_changed(hunter_score: int, hider_score: int)
signal phase_changed(new_phase: MatchPhase)

var phase: MatchPhase = MatchPhase.LOBBY
var hunter_score := 0
var hider_score := 0


func _set_phase(new_phase: MatchPhase) -> void:
	if phase == new_phase:
		return
	phase = new_phase
	phase_changed.emit(phase)


## Called by RoundManager once roles are assigned and the round clock
## starts.
func begin_round() -> void:
	_set_phase(MatchPhase.ROUND_ACTIVE)


## Called by RoundManager when a round concludes. `winner_role` is a
## Role.HIDER / Role.HUNTER value (see Scripts/Gameplay/Role.gd).
func record_round_result(winner_role: int) -> void:
	if winner_role == Role.HUNTER:
		hunter_score += 1
	else:
		hider_score += 1
	_set_phase(MatchPhase.ROUND_ENDED)
	score_changed.emit(hunter_score, hider_score)


## Clears score and returns to the lobby phase. Called whenever the
## multiplayer session itself ends (see RoundManager.reset_state()),
## since a fresh host/join should start a fresh match, not continue the
## previous session's score.
func reset() -> void:
	hunter_score = 0
	hider_score = 0
	_set_phase(MatchPhase.LOBBY)
	score_changed.emit(hunter_score, hider_score)
