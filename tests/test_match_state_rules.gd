extends GutTest
## Unit tests for managers/MatchStateRules.gd -- the match-level state
## machine's valid-transition guard (TK-P2-15).
##
## Only the pure decision logic is tested here (node-independent, no live
## peers/RPC) -- same "pure static helper" testability split every other
## state-transition file in this codebase follows (see
## tests/test_role_state_machine.gd for characters/RoleRules.gd's own
## equivalent suite). GameManager's own host-only wiring (the Countdown
## trigger, the round-counting watch, the return-to-WaitingRoom scene switch)
## needs a live multiplayer server context + scene tree and is NOT covered
## here -- live cross-instance verification belongs to a human 2-instance
## pass, not GUT.

const MatchStateRulesScript := preload("res://managers/MatchStateRules.gd")

const WAITING_ROOM := MatchStateRulesScript.State.WAITING_ROOM
const COUNTDOWN := MatchStateRulesScript.State.COUNTDOWN
const PLAYING := MatchStateRulesScript.State.PLAYING
const MATCH_END := MatchStateRulesScript.State.MATCH_END


# --- the one legal forward loop -------------------------------------------------

func test_waiting_room_to_countdown_is_valid() -> void:
	assert_true(MatchStateRulesScript.is_valid_transition(WAITING_ROOM, COUNTDOWN))


func test_countdown_to_playing_is_valid() -> void:
	assert_true(MatchStateRulesScript.is_valid_transition(COUNTDOWN, PLAYING))


func test_playing_to_match_end_is_valid() -> void:
	assert_true(MatchStateRulesScript.is_valid_transition(PLAYING, MATCH_END))


func test_match_end_to_waiting_room_is_valid() -> void:
	assert_true(MatchStateRulesScript.is_valid_transition(MATCH_END, WAITING_ROOM),
		"the match must be able to end and return to Waiting Room (card DoD)")


# --- idempotent same-state re-broadcast -----------------------------------------

func test_same_state_transition_is_valid_for_every_state() -> void:
	for state in [WAITING_ROOM, COUNTDOWN, PLAYING, MATCH_END]:
		assert_true(MatchStateRulesScript.is_valid_transition(state, state),
			"a re-broadcast of the current state must be a no-op, not an error")


# --- fail-closed on any skip-ahead / backward jump / shortcut -------------------

func test_skip_ahead_countdown_to_match_end_is_invalid() -> void:
	assert_false(MatchStateRulesScript.is_valid_transition(COUNTDOWN, MATCH_END))


func test_skip_ahead_waiting_room_to_playing_is_invalid() -> void:
	assert_false(MatchStateRulesScript.is_valid_transition(WAITING_ROOM, PLAYING))


func test_skip_ahead_waiting_room_to_match_end_is_invalid() -> void:
	assert_false(MatchStateRulesScript.is_valid_transition(WAITING_ROOM, MATCH_END))


func test_backward_jump_playing_to_countdown_is_invalid() -> void:
	assert_false(MatchStateRulesScript.is_valid_transition(PLAYING, COUNTDOWN))


func test_backward_jump_playing_to_waiting_room_is_invalid() -> void:
	assert_false(MatchStateRulesScript.is_valid_transition(PLAYING, WAITING_ROOM))


func test_backward_jump_match_end_to_countdown_is_invalid() -> void:
	assert_false(MatchStateRulesScript.is_valid_transition(MATCH_END, COUNTDOWN))


func test_backward_jump_match_end_to_playing_is_invalid() -> void:
	assert_false(MatchStateRulesScript.is_valid_transition(MATCH_END, PLAYING))


func test_backward_jump_countdown_to_waiting_room_is_invalid() -> void:
	assert_false(MatchStateRulesScript.is_valid_transition(COUNTDOWN, WAITING_ROOM))


# --- state_name -----------------------------------------------------------------

func test_state_name_for_every_known_state() -> void:
	assert_eq(MatchStateRulesScript.state_name(WAITING_ROOM), "WAITING_ROOM")
	assert_eq(MatchStateRulesScript.state_name(COUNTDOWN), "COUNTDOWN")
	assert_eq(MatchStateRulesScript.state_name(PLAYING), "PLAYING")
	assert_eq(MatchStateRulesScript.state_name(MATCH_END), "MATCH_END")


func test_state_name_for_an_out_of_range_value_does_not_crash() -> void:
	assert_eq(MatchStateRulesScript.state_name(99), "UNKNOWN(99)")
	assert_eq(MatchStateRulesScript.state_name(-1), "UNKNOWN(-1)")
