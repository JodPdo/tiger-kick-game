extends GutTest
## Regression coverage for TK-BUG-P3-01/02/03 (gameplay-engineer, filed from a
## human's CASE E bot-harness run, 2026-07-26) -- the MATCH_END edge of
## managers/GameManager.gd's own match-level state machine (TK-P2-15), which
## had never been live-exercised by GUT before this card (only the pure
## managers/MatchStateRules.gd transition-table guard was covered --
## tests/test_match_state_rules.gd's own class doc explicitly calls out that
## GameManager's own host-only wiring is NOT covered there). Per this card's
## own instruction (Test_Strategy.md section 8, "positive-effect assertion,
## not just no-crash" -- the exact wiring-glue gap this codebase has now hit
## 3 times, per TK-P2-15's own known_gap_accepted note), every test below
## asserts a REAL observable side effect (a role that did/did not flip, a
## round counter that did/did not advance, match_state that did/did not
## change), not just "ran without an error".
##
## SCOPE: covers managers/GameManager.gd's is_match_playing()/
## try_reserve_next_round()/_end_match()/start_tag_sequence()/_run_sequence()
## and managers/RoundManager.gd's own new GameManager coupling
## (_physics_process()'s gate, _on_round_timeout()'s gate). Does NOT cover
## TK-BUG-P3-01 (the WaitingRoom scene-switch race) -- that fix is a network-
## timing fix with no node-independent decision to unit test (the real "does
## the host really arrive first now" question needs a human 2-instance pass
## per this repo's established convention, not GUT); the DoD for that fix is
## the human's own CASE E re-run.
##
## SETUP: builds a REAL scene-tree arena (Node3D root + "Players" + a REAL
## managers/CountdownManager.gd sibling, mirroring world/TestArena.tscn's own
## shape) and adds a REAL managers/GameManager.gd (and, for the RoundManager
## tests, a REAL managers/RoundManager.gd too) as an actual child so its own
## host-only _ready() runs for real -- deliberately DIFFERENT from
## tests/test_tag_sequence.gd's own harness (there, GameManager is never
## added to the tree, specifically so _ready() does NOT run -- see that
## file's own SETUP doc). This file needs the OPPOSITE: the live match-flow
## wiring (the role_changed watch, the match-end gate) IS the thing under
## test. To keep _ready() from auto-starting a real Countdown (which would
## need real time to resolve), every arena is built with ZERO Players present
## -- _expected_first_tiger_roster_size becomes 1 (host only, offline
## default) with 0 Players spawned, so GameManager's own _ready() takes its
## "wait for a spawn" branch (arms an inert 12s grace Timer that never fires
## during a GUT run) rather than the "spawn everyone already present"
## synchronous branch. Every test then drives match_state/_round_count
## directly and/or spawns Players AFTER the fact (exercising the real
## child_entered_tree-driven watch wiring).
##
## SAFETY NOTE (match_end_grace_sec): _end_match() awaits
## get_tree().create_timer(match_end_grace_sec).timeout before calling
## return_to_waiting_room.rpc(), which performs a REAL
## get_tree().change_scene_to_file() -- inside a GUT run this would swap out
## the entire running test scene out from under the rest of the suite. Every
## test that can reach _end_match() sets match_end_grace_sec to a large value
## (NEVER_FIRES_SEC) so that timer provably cannot fire during this file's
## own (or any other file's) short run, and never awaits past the point where
## match_state flips to MATCH_END -- the scene-switch half of this flow is
## deliberately left to the human CASE E pass per the SCOPE note above.

const PlayerScene := preload("res://characters/Player.tscn")
const GameManagerScript := preload("res://managers/GameManager.gd")
const RoundManagerScript := preload("res://managers/RoundManager.gd")
const CountdownManagerScript := preload("res://managers/CountdownManager.gd")
const MatchStateRulesScript := preload("res://managers/MatchStateRules.gd")

const WAITING_ROOM := MatchStateRulesScript.State.WAITING_ROOM
const COUNTDOWN := MatchStateRulesScript.State.COUNTDOWN
const PLAYING := MatchStateRulesScript.State.PLAYING
const MATCH_END := MatchStateRulesScript.State.MATCH_END

const ROLE_TIGER: StringName = &"tiger"
const ROLE_OUTER: StringName = &"outer"

const NEVER_FIRES_SEC: float = 9999.0 # see class doc SAFETY NOTE


func before_all() -> void:
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), NodePath(""))


func _build_arena() -> Node:
	var arena := Node3D.new()
	add_child_autofree(arena)
	var players := Node3D.new()
	players.name = "Players"
	arena.add_child(players)
	var countdown := CountdownManagerScript.new()
	countdown.name = "CountdownManager"
	arena.add_child(countdown)
	return arena


func _add_game_manager(arena: Node) -> Node:
	var gm := GameManagerScript.new()
	gm.name = "GameManager"
	arena.add_child(gm)
	# _ready() (having seen 0 Players at that moment) armed
	# _on_player_entered_watch_first_tiger() -- if a test later spawns a
	# Player under "Players" (several of this file's own tests do, to drive
	# the real role_changed watch), that handler would see the roster
	# satisfied and call_deferred() a REAL _start_countdown(), racing this
	# file's own manually-set match_state with an unrelated, unwanted
	# WAITING_ROOM -> COUNTDOWN broadcast attempt. Setting _countdown_started
	# here (this file's harness is testing the MATCH_END edge, never the
	# match-ready -> Countdown edge -- that is TK-P2-14/15's own already-
	# covered scope) makes that handler's own early-return guard neutralize it
	# for every test built off this helper.
	gm._countdown_started = true
	return gm


func _add_round_manager(arena: Node) -> Node:
	var rm := RoundManagerScript.new()
	rm.name = "RoundManager"
	arena.add_child(rm)
	return rm


func _spawn_player(players: Node, peer_name: String, role: StringName) -> CharacterBody3D:
	var p: CharacterBody3D = PlayerScene.instantiate()
	p.name = peer_name
	players.add_child(p)
	if role != ROLE_OUTER:
		p.set_role(role)
	return p


# --- is_match_playing() ------------------------------------------------------

func test_is_match_playing_true_only_in_playing_state() -> void:
	var arena := _build_arena()
	var gm := _add_game_manager(arena)

	gm.match_state = WAITING_ROOM
	assert_false(gm.is_match_playing())
	gm.match_state = COUNTDOWN
	assert_false(gm.is_match_playing())
	gm.match_state = PLAYING
	assert_true(gm.is_match_playing())
	gm.match_state = MATCH_END
	assert_false(gm.is_match_playing())


# --- try_reserve_next_round() -- the TK-BUG-P3-02/03 gate --------------------

func test_try_reserve_next_round_true_when_playing_and_under_cap() -> void:
	var arena := _build_arena()
	var gm := _add_game_manager(arena)

	gm.match_state = PLAYING
	gm.rounds_per_match = 3
	gm._round_count = 1

	assert_true(gm.try_reserve_next_round())
	assert_eq(gm.match_state, PLAYING, "must not touch match_state when still under cap")
	assert_false(gm._match_ending, "must not trigger _end_match() when still under cap")


func test_try_reserve_next_round_false_when_not_playing_and_does_not_reend_match() -> void:
	var arena := _build_arena()
	var gm := _add_game_manager(arena)

	gm.match_state = MATCH_END
	gm.rounds_per_match = 3
	gm._round_count = 1

	assert_false(gm.try_reserve_next_round())
	assert_eq(gm.match_state, MATCH_END, "state must be untouched")
	assert_false(gm._match_ending,
		"TK-BUG-P3-02: a Tag/timeout arriving once the match has already ended must be a silent no-op, NOT a second match-end trigger")


func test_try_reserve_next_round_false_and_ends_match_when_cap_reached() -> void:
	var arena := _build_arena()
	var gm := _add_game_manager(arena)

	gm.match_state = PLAYING
	gm.rounds_per_match = 3
	gm._round_count = 3
	gm.match_end_grace_sec = NEVER_FIRES_SEC

	var ok: bool = gm.try_reserve_next_round()

	assert_false(ok, "the would-be 4th round must be refused")
	assert_eq(gm.match_state, MATCH_END,
		"TK-BUG-P3-03: reaching the cap while still PLAYING must trigger match end AS the refusal, not silently do nothing")
	assert_true(gm._match_ending)
	assert_eq(gm._round_count, 3, "the round counter must NOT advance for a round that never started")


func test_try_reserve_next_round_is_idempotent_against_a_second_call_at_cap() -> void:
	var arena := _build_arena()
	var gm := _add_game_manager(arena)

	gm.match_state = PLAYING
	gm.rounds_per_match = 2
	gm._round_count = 2
	gm.match_end_grace_sec = NEVER_FIRES_SEC

	assert_false(gm.try_reserve_next_round())
	assert_true(gm._match_ending)
	assert_false(gm.try_reserve_next_round(), "still refused")
	assert_true(gm._match_ending, "still true, unchanged by the second call")


# --- the real role_changed-driven round counter (closes the qa_verdict-      -
# --- flagged coverage gap: TK-P2-15's own known_gap_accepted note) ----------

func test_round_counter_advances_via_the_real_role_changed_watch() -> void:
	var arena := _build_arena()
	var gm := _add_game_manager(arena)
	var players: Node = arena.get_node("Players")

	gm.match_state = PLAYING
	assert_eq(gm._round_count, 0, "sanity: no round has started yet")

	var p1: CharacterBody3D = _spawn_player(players, "1", ROLE_OUTER)
	p1.set_role(ROLE_TIGER)

	assert_eq(gm._round_count, 1,
		"GameManager's real _on_any_player_role_changed_for_match_end watch (wired in its own _ready(), not a mock) must observe this and advance the counter")

	var p2: CharacterBody3D = _spawn_player(players, "2", ROLE_OUTER)
	p1.set_role(ROLE_OUTER)
	p2.set_role(ROLE_TIGER)

	assert_eq(gm._round_count, 2, "a second into-Tiger transition must advance the counter again")


func test_round_counter_does_not_advance_outside_playing() -> void:
	var arena := _build_arena()
	var gm := _add_game_manager(arena)
	var players: Node = arena.get_node("Players")

	gm.match_state = COUNTDOWN
	var p1: CharacterBody3D = _spawn_player(players, "1", ROLE_OUTER)
	p1.set_role(ROLE_TIGER)

	assert_eq(gm._round_count, 0, "a role flip outside PLAYING must never advance the match-end counter")


# --- start_tag_sequence()/_run_sequence() -- TK-BUG-P3-02 ------------------

func test_start_tag_sequence_refuses_and_leaves_the_lock_clear_when_match_already_ended() -> void:
	var arena := _build_arena()
	var gm := _add_game_manager(arena)
	var players: Node = arena.get_node("Players")

	var tiger: CharacterBody3D = _spawn_player(players, "1", ROLE_TIGER)
	var target: CharacterBody3D = _spawn_player(players, "2", ROLE_OUTER)
	gm.match_state = MATCH_END

	gm.start_tag_sequence(1, 2)

	# start_tag_sequence() deliberately GameLog.error()s (-> push_error()) on
	# this defense-in-depth rejection -- fail LOUDLY, not silently (mirrors
	# the pre-existing can_start_sequence() guard's own posture).
	# assert_push_error() both confirms that happened and tells GUT it was
	# expected.
	assert_push_error("not PLAYING")
	assert_false(gm._is_tag_sequence_active,
		"start_tag_sequence must refuse BEFORE ever setting the sequence-active lock -- it must not get stuck locked")
	assert_eq(tiger.role, ROLE_TIGER, "no role swap may happen -- the tagger's role must stay untouched")
	assert_eq(target.role, ROLE_OUTER, "no role swap may happen -- the target's role must stay untouched")


func test_run_sequence_refuses_the_swap_and_ends_the_match_when_the_round_cap_is_reached() -> void:
	var arena := _build_arena()
	var gm := _add_game_manager(arena)
	var rm := _add_round_manager(arena)
	var players: Node = arena.get_node("Players")

	gm.match_state = PLAYING
	gm.rounds_per_match = 2
	gm.throw_stub_sec = 0.01
	gm.transform_stub_sec = 0.01
	gm.match_end_grace_sec = NEVER_FIRES_SEC

	var p1: CharacterBody3D = _spawn_player(players, "1", ROLE_OUTER)
	var p2: CharacterBody3D = _spawn_player(players, "2", ROLE_OUTER)
	p1.set_role(ROLE_TIGER)
	assert_eq(gm._round_count, 1, "sanity: round 1 has started")

	gm.start_tag_sequence(1, 2)
	await wait_seconds(0.2)

	assert_eq(p2.role, ROLE_TIGER, "round 1's tag must produce a REAL swap -- round 2 must actually start")
	assert_eq(p1.role, ROLE_OUTER)
	assert_eq(gm._round_count, 2, "round 2 has now started")
	assert_eq(gm.match_state, PLAYING,
		"TK-BUG-P3-03: reaching _round_count == rounds_per_match by STARTING round 2 must NOT end the match immediately -- round 2 must get to actually play")

	gm.start_tag_sequence(2, 1)
	await wait_seconds(0.2)

	assert_eq(p2.role, ROLE_TIGER, "the would-be round 3 must be refused -- the current Tiger must NOT change")
	assert_eq(p1.role, ROLE_OUTER)
	assert_eq(gm._round_count, 2, "the round counter must stay at 2 -- a refused round never 'started'")
	assert_eq(gm.match_state, MATCH_END, "the match must end exactly when the round cap's final round concludes")
	assert_false(gm._is_tag_sequence_active, "the sequence lock must still be released even though the swap was refused")


# --- RoundManager's own new GameManager coupling (TK-BUG-P3-02/03) ---------

func test_round_manager_timeout_starts_a_new_round_when_under_cap() -> void:
	var arena := _build_arena()
	var gm := _add_game_manager(arena)
	var rm := _add_round_manager(arena)
	var players: Node = arena.get_node("Players")

	gm.match_state = PLAYING
	gm.rounds_per_match = 5
	gm._round_count = 1

	var p1: CharacterBody3D = _spawn_player(players, "1", ROLE_OUTER)
	var p2: CharacterBody3D = _spawn_player(players, "2", ROLE_OUTER)
	p1.set_role(ROLE_TIGER)

	rm._on_round_timeout()

	assert_eq(p1.role, ROLE_OUTER, "a normal timeout under the cap must still flip the expired Tiger back to Outer")
	assert_eq(p2.role, ROLE_TIGER, "...and hand the reign to the only other candidate")
	assert_eq(gm.match_state, PLAYING, "must not have touched match_state")


func test_round_manager_timeout_refuses_and_ends_the_match_when_cap_reached() -> void:
	var arena := _build_arena()
	var gm := _add_game_manager(arena)
	var rm := _add_round_manager(arena)
	var players: Node = arena.get_node("Players")

	gm.match_state = PLAYING
	gm.rounds_per_match = 1
	gm.match_end_grace_sec = NEVER_FIRES_SEC

	var p1: CharacterBody3D = _spawn_player(players, "1", ROLE_OUTER)
	_spawn_player(players, "2", ROLE_OUTER)
	p1.set_role(ROLE_TIGER)

	rm._on_round_timeout()

	assert_eq(p1.role, ROLE_TIGER,
		"TK-BUG-P3-02/03: a timeout that would exceed the round cap must NOT start a new round -- the current Tiger must be left as-is")
	assert_eq(gm.match_state, MATCH_END, "RoundManager's own timeout path must be able to trigger match end via GameManager")


func test_round_manager_physics_process_does_not_tick_or_timeout_once_match_state_leaves_playing() -> void:
	var arena := _build_arena()
	var gm := _add_game_manager(arena)
	var rm := _add_round_manager(arena)
	var players: Node = arena.get_node("Players")

	rm.round_duration_sec = 1.0
	var p1: CharacterBody3D = _spawn_player(players, "1", ROLE_OUTER)
	_spawn_player(players, "2", ROLE_OUTER)

	gm.match_state = PLAYING
	p1.set_role(ROLE_TIGER)

	gm.match_state = MATCH_END

	rm._physics_process(10.0)

	assert_eq(p1.role, ROLE_TIGER, "no timeout-driven swap may happen once match_state has left PLAYING")
	assert_almost_eq(rm._elapsed_sec, 0.0, 0.001, "elapsed time must not even accumulate once match_state has left PLAYING")
