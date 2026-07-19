extends GutTest
## Unit tests for managers/CountdownRules.gd -- the pre-match Countdown
## display/completion math (TK-P2-14).
##
## Only the pure decision logic is tested here (node-independent, no live
## peers/RPC/Timer node) -- same "pure static helper" testability split
## every other decision-logic file in this codebase follows (see
## tests/test_round_rules.gd, tests/test_safe_circle.gd). CountdownManager's
## own host-only wiring (the Timer/_physics_process accumulation, the
## tick_changed RPC broadcast) needs a live multiplayer server context and is
## NOT covered here -- live cross-instance verification belongs to a human
## 2-instance pass, not GUT.

const CountdownRulesScript := preload("res://managers/CountdownRules.gd")


# --- display_number -----------------------------------------------------------

func test_display_number_full_at_zero_elapsed() -> void:
	assert_eq(CountdownRulesScript.display_number(0.0, 3.0), 3,
		"the very first tick, at elapsed 0.0, must already read the full starting number")


func test_display_number_just_under_one_second_still_reads_three() -> void:
	assert_eq(CountdownRulesScript.display_number(0.99, 3.0), 3)


func test_display_number_at_one_second_reads_two() -> void:
	assert_eq(CountdownRulesScript.display_number(1.0, 3.0), 2)


func test_display_number_at_two_seconds_reads_one() -> void:
	assert_eq(CountdownRulesScript.display_number(2.0, 3.0), 1)


func test_display_number_at_exactly_the_duration_reads_zero() -> void:
	assert_eq(CountdownRulesScript.display_number(3.0, 3.0), 0)


func test_display_number_past_the_duration_stays_zero() -> void:
	assert_eq(CountdownRulesScript.display_number(9999.0, 3.0), 0,
		"a caller polling well past completion must never read a negative/garbage tick")


func test_display_number_degenerate_non_positive_duration_reads_zero() -> void:
	assert_eq(CountdownRulesScript.display_number(0.0, 0.0), 0)
	assert_eq(CountdownRulesScript.display_number(0.0, -1.0), 0)


# --- is_countdown_complete -----------------------------------------------------

func test_not_complete_when_no_time_has_elapsed() -> void:
	assert_false(CountdownRulesScript.is_countdown_complete(0.0, 3.0))


func test_not_complete_partway_through() -> void:
	assert_false(CountdownRulesScript.is_countdown_complete(2.9, 3.0))


func test_complete_exactly_at_the_boundary() -> void:
	assert_true(CountdownRulesScript.is_countdown_complete(3.0, 3.0),
		"exactly at the duration must already count as complete (>=, not >), matching RoundRules.has_round_timed_out()'s own boundary-inclusive convention")


func test_complete_past_the_boundary() -> void:
	assert_true(CountdownRulesScript.is_countdown_complete(3.1, 3.0))


func test_degenerate_zero_duration_is_always_complete() -> void:
	assert_true(CountdownRulesScript.is_countdown_complete(0.0, 0.0),
		"a misconfigured (non-positive) countdown_duration_sec can never be honestly 'not yet complete'")


func test_degenerate_negative_duration_is_always_complete() -> void:
	assert_true(CountdownRulesScript.is_countdown_complete(0.0, -5.0))
