class_name CountdownRules
## Pure, node-independent decision logic for the pre-match Countdown
## (TK-P2-14, gameplay-engineer) -- same "pure static helper, thin host-only
## shell" split every timer-driven decision-logic file in this codebase
## already follows (see managers/RoundRules.gd's own class doc, which this
## file's split mirrors exactly). The live host-only shell (elapsed-time
## accumulation, the one broadcast every peer must OBSERVE) lives on
## managers/CountdownManager.gd -- see that file's class doc for the full
## picture and for WHY clients never count down locally (host-authoritative,
## CLAUDE.md server authority / the card's own DoD).
##
## SCOPE: this is a fixed-duration countdown ("3 -> 2 -> 1", ending at 0) --
## no pause/cancel/extend semantics exist here or anywhere else in this card
## on purpose; `countdown_duration_sec` itself is a design-owned placeholder
## tunable that lives as an @export on CountdownManager.gd (CLAUDE.md:
## "expose design-owned tunables, never hard-code"), same posture
## RoundRules.gd's own doc documents for `round_duration_sec`.


## The whole-number countdown display value for `elapsed_sec` seconds into a
## `countdown_duration_sec`-long countdown -- e.g. for a 3.0s countdown:
## elapsed in [0.0, 1.0) -> 3, [1.0, 2.0) -> 2, [2.0, 3.0) -> 1,
## elapsed >= 3.0 -> 0. Uses ceil() on the seconds REMAINING (not floor on
## elapsed) so the very first tick displayed, at elapsed_sec == 0.0, already
## reads the full "3" a player expects to see the instant the countdown
## starts, rather than needing a full second to elapse first.
##
## Degenerate guard: a non-positive `countdown_duration_sec` (a
## misconfigured tunable) can never display anything above 0 -- clamped so a
## caller cannot be handed a nonsensical negative or otherwise-undefined
## display number.
static func display_number(elapsed_sec: float, countdown_duration_sec: float) -> int:
	if countdown_duration_sec <= 0.0:
		return 0
	var remaining: float = countdown_duration_sec - elapsed_sec
	if remaining <= 0.0:
		return 0
	return int(ceil(remaining))


## True once `elapsed_sec` has reached (or passed) `countdown_duration_sec` --
## the countdown-end condition ("จบ 0 -> Match Start" per the card note).
## Uses >=, not >, matching RoundRules.has_round_timed_out()'s own
## boundary-inclusive convention (and SafeCircleRules.is_inside()'s) so every
## boundary-condition check in this codebase agrees at the exact edge.
## Same non-positive-duration degenerate guard as RoundRules.gd's own
## has_round_timed_out(): a misconfigured (<=0) duration can never be
## honestly "not yet complete".
static func is_countdown_complete(elapsed_sec: float, countdown_duration_sec: float) -> bool:
	if countdown_duration_sec <= 0.0:
		return true
	return elapsed_sec >= countdown_duration_sec
