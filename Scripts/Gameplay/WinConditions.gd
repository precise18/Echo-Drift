class_name WinConditions
## Pure logic, no state, no scene tree access: given positions/time, answer
## "has someone won yet". Kept separate from RoundManager so the actual
## win/lose rules can be read (and unit-tested) in one small place instead
## of buried inside round orchestration code.
##
## Win / lose is symmetric in this MVP — there is exactly one way a round
## can end, and it always produces exactly one winner and one loser:
##   - Hunter WINS (Hider LOSES) the instant is_capture() is true.
##   - Hider WINS (Hunter LOSES) the instant is_timeout() is true and no
##     capture happened first.

const TOUCH_RADIUS := 1.3 # meters; how close the hunter must get to win


## True once the hunter is within TOUCH_RADIUS of the hider.
static func is_capture(hunter_position: Vector3, hider_position: Vector3) -> bool:
	return hunter_position.distance_to(hider_position) <= TOUCH_RADIUS


## True once the round clock has run out.
static func is_timeout(time_left: float) -> bool:
	return time_left <= 0.0
