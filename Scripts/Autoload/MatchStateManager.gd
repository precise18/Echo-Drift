extends Node
## Autoload: tracks state that spans the whole play session — cumulative
## score and which phase the match is currently in — as distinct from
## RoundManager, which only ever knows about the *current* round.
##
## A match is first-to-ROUNDS_TO_WIN round wins. Every peer runs this
## identically off RoundManager's replicated _end_round RPC (which calls
## record_round_result on all peers via call_local), so the match-over
## decision needs no synchronization of its own — each peer reaches the
## same conclusion from the same replicated inputs.

const ROUNDS_TO_WIN := 3

enum MatchPhase { LOBBY, ROUND_ACTIVE, ROUND_ENDED, MATCH_OVER }

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
	_set_phase(MatchPhase.MATCH_OVER if is_match_over() else MatchPhase.ROUND_ENDED)
	score_changed.emit(hunter_score, hider_score)


func is_match_over() -> bool:
	return hunter_score >= ROUNDS_TO_WIN or hider_score >= ROUNDS_TO_WIN


## Role.HUNTER / Role.HIDER once the match is decided, Role.NONE before.
func match_winner_role() -> int:
	if hunter_score >= ROUNDS_TO_WIN:
		return Role.HUNTER
	if hider_score >= ROUNDS_TO_WIN:
		return Role.HIDER
	return Role.NONE


## 1-based number of the round currently being played (or about to be).
func round_number() -> int:
	return hunter_score + hider_score + 1


## True while players are in the warm-up lobby (connected, walking
## around, no round started yet). PlayerController checks this to allow
## warm-up movement.
func is_in_lobby() -> bool:
	return phase == MatchPhase.LOBBY


## Applies scores handed down by RoundManager's reconnect-resync RPC. A
## reconnecting peer's own MatchStateManager otherwise has no way to learn
## the current score at all — ordinary score updates only ever travel via
## _end_round's call_local RPC, which a peer that wasn't connected yet
## when earlier rounds ended never received, leaving its scoreboard stuck
## at 0-0 until the next round happens to end.
func sync_scores(new_hunter_score: int, new_hider_score: int) -> void:
	hunter_score = new_hunter_score
	hider_score = new_hider_score
	score_changed.emit(hunter_score, hider_score)


## Clears score and returns to the lobby phase. Called whenever the
## multiplayer session itself ends (see RoundManager.reset_state()) and
## on rematch, since both should start from a fresh 0–0.
func reset() -> void:
	hunter_score = 0
	hider_score = 0
	_set_phase(MatchPhase.LOBBY)
	score_changed.emit(hunter_score, hider_score)
