class_name RoundRules
## Pure, node-independent decision logic for the ROUND timer / round-end
## condition (TK-P2-07, gameplay-engineer) -- same "pure static helper, thin
## host-only shell" split every other decision-logic file in this codebase
## follows (see managers/TagSequenceRules.gd, managers/TigerSelector.gd,
## characters/RoleRules.gd, characters/components/SafeCircleRules.gd). The
## live host-only shell (Timer accumulation, RPC broadcast, re-picking a
## Tiger via TigerSelector) lives on managers/RoundManager.gd -- see that
## file's class doc for the full round-loop picture.
##
## SCOPE (GDD 02_Technical §2.2 core loop step 6 -- "เกมดำเนินต่อจนหมดเวลา ...
## แล้วเริ่มรอบใหม่ (Round Restart)" -- and GDD §9 Open Questions, which
## explicitly leaves "เงื่อนไขจบรอบที่สนุกที่สุดคืออะไร (จับเวลา จำนวนครั้งที่
## ถูกเตะ ฯลฯ)" -- i.e. which round-end condition is most fun, timer vs
## kick-count vs other -- UNRESOLVED, deferred to Phase 3 design tuning
## (TK-P3-04)): the GDD already commits to a TIMER as the Prototype baseline
## ("จนหมดเวลา"), so this file implements ONLY that -- a single elapsed-vs-
## duration comparison. No kick-count/score/other end condition exists here
## or anywhere else in this card, on purpose; do not extend this file to
## "prove" an alternate condition without a designer decision first.
##
## `round_duration_sec` itself is a design-owned tunable (Game_Balance.md
## "Round length: 3-5 นาที", sourced "GDD (ยังไม่ทำ)" -- not yet locked), so
## the actual VALUE lives as an @export on managers/RoundManager.gd (CLAUDE.md
## "expose design-owned tunables, never hard-code") -- this file only knows
## how to COMPARE an elapsed time against whatever duration its caller passes
## in, same "pure function of its inputs, no opinion about where the numbers
## come from" split as SafeCircleRules.gd's own `radius` parameter.


## True once `elapsed_sec` has reached (or passed) `round_duration_sec` -- the
## round-end condition. Uses >=, not >, so a round that lands EXACTLY on the
## duration boundary still ends on that same tick (matches
## SafeCircleRules.is_inside()'s own "<=, not <" boundary-inclusive
## convention -- the two checks must never disagree right at the boundary).
##
## Degenerate guard: a non-positive `round_duration_sec` (a misconfigured
## tunable -- e.g. a designer/producer fat-fingering 0 or a negative value in
## the Inspector) can never be "not yet timed out" -- returns true
## immediately rather than waiting forever for a duration that can never be
## reached honestly.
static func has_round_timed_out(elapsed_sec: float, round_duration_sec: float) -> bool:
	if round_duration_sec <= 0.0:
		return true
	return elapsed_sec >= round_duration_sec


## Seconds left before has_round_timed_out() would return true, clamped to
## never go negative (a caller polling one frame after the actual timeout
## still reads 0.0, not a negative countdown). No consumer exists yet in this
## card's scope (a HUD countdown display is polish-agent/Phase-4 territory),
## but this is a natural, trivially-testable companion to
## has_round_timed_out() and the obvious hook a future HUD would need -- same
## "pure math, no opinion about who renders it" split as this file's other
## function.
static func remaining_sec(elapsed_sec: float, round_duration_sec: float) -> float:
	return max(0.0, round_duration_sec - elapsed_sec)
