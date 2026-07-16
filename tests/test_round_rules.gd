extends GutTest
## Unit tests for managers/RoundRules.gd -- the ROUND timer / round-end
## condition (TK-P2-07).
##
## Only the pure decision logic is tested here (node-independent, no live
## peers/RPC/Timer node) -- same "pure static helper" testability split
## every other decision-logic file in this codebase follows (see
## tests/test_safe_circle.gd, tests/test_tag_sequence.gd,
## tests/test_tiger_assignment.gd). managers/RoundManager.gd's own
## host-only wiring (the role_changed watch, the Timer/_physics_process
## accumulation, the start_new_round RPC) needs a live multiplayer server
## context and a "../Players" sibling in the scene tree, and is NOT covered
## here -- same scope line tests/test_tag_sequence.gd's own class doc draws
## for GameManager's equivalent host-only methods; live cross-instance
## verification belongs to a human 2-instance pass, not GUT.

const RoundRulesScript := preload("res://managers/RoundRules.gd")


# --- has_round_timed_out ------------------------------------------------------

func test_not_timed_out_when_no_time_has_elapsed() -> void:
	assert_false(RoundRulesScript.has_round_timed_out(0.0, 240.0))


func test_not_timed_out_partway_through() -> void:
	assert_false(RoundRulesScript.has_round_timed_out(120.0, 240.0))


func test_timed_out_exactly_at_the_boundary() -> void:
	assert_true(RoundRulesScript.has_round_timed_out(240.0, 240.0),
		"exactly at the duration must already count as timed out (>=, not >), matching SafeCircleRules' own boundary-inclusive convention")


func test_timed_out_past_the_boundary() -> void:
	assert_true(RoundRulesScript.has_round_timed_out(240.1, 240.0))


func test_timed_out_well_past_the_boundary() -> void:
	assert_true(RoundRulesScript.has_round_timed_out(9999.0, 240.0))


func test_zero_elapsed_never_times_out_for_a_positive_duration() -> void:
	# sanity: a fresh round (0 elapsed) must never read as timed out for any
	# sane positive duration.
	assert_false(RoundRulesScript.has_round_timed_out(0.0, 1.0))


# --- has_round_timed_out degenerate guard (misconfigured tunable) -----------

func test_degenerate_zero_duration_is_always_timed_out() -> void:
	assert_true(RoundRulesScript.has_round_timed_out(0.0, 0.0),
		"a misconfigured (non-positive) round_duration_sec can never be honestly 'not yet timed out'")


func test_degenerate_negative_duration_is_always_timed_out() -> void:
	assert_true(RoundRulesScript.has_round_timed_out(0.0, -5.0))


# --- remaining_sec -------------------------------------------------------------

func test_remaining_sec_full_duration_at_zero_elapsed() -> void:
	assert_almost_eq(RoundRulesScript.remaining_sec(0.0, 240.0), 240.0, 0.0001)


func test_remaining_sec_partway_through() -> void:
	assert_almost_eq(RoundRulesScript.remaining_sec(100.0, 240.0), 140.0, 0.0001)


func test_remaining_sec_exactly_zero_at_the_boundary() -> void:
	assert_almost_eq(RoundRulesScript.remaining_sec(240.0, 240.0), 0.0, 0.0001)


func test_remaining_sec_never_goes_negative_past_the_boundary() -> void:
	assert_almost_eq(RoundRulesScript.remaining_sec(9999.0, 240.0), 0.0, 0.0001,
		"a caller polling one frame after timeout must read 0.0, never a negative countdown")


# --- reuse of TigerSelector for round re-picks (TK-P2-07 card note: --------
# "reusable for re-rolling the Tiger each round") -- confirms the anti-repeat
# `avoid` parameter RoundManager._on_round_timeout() relies on already exists
# and behaves as documented; this is regression coverage for a dependency
# this card leans on, not new decision logic of RoundRules.gd itself (see
# tests/test_tiger_assignment.gd for the full TigerSelector suite).

const TigerSelectorScript := preload("res://managers/TigerSelector.gd")


func test_tiger_selector_pick_first_tiger_avoids_the_just_expired_tiger_on_reroll() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var candidates: Array = [1, 2, 3, 4]
	for _i in range(200):
		var picked: int = TigerSelectorScript.pick_first_tiger(candidates, rng, 2)
		assert_ne(picked, 2,
			"a timer-driven round restart must not immediately hand the reign back to the Tiger who just timed out, when other candidates exist")
