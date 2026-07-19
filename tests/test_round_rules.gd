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

# TK-P2-33: scene-tree-level regression coverage for RoundManager.start_new_
# round()'s actual node resolution (see the "start_new_round" section below).
const PlayerScene := preload("res://characters/Player.tscn")
const RoundManagerScript := preload("res://managers/RoundManager.gd")

const ROLE_TIGER: StringName = &"tiger"
const ROLE_OUTER: StringName = &"outer"


## TK-P2-33: reset the shared-process root MultiplayerAPI to a pristine default
## before this file's Player.tscn + RoundManager scene-tree tests -- see
## tests/test_role_state_machine.gd's own before_all() for the full writeup of
## the shared-process multiplayer-state hazard.
func before_all() -> void:
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), NodePath(""))


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


# --- RoundManager.start_new_round node resolution (TK-P2-33) -----------------
# POSITIVE-SIDE-EFFECT regression coverage, same bug CLASS as TK-P2-32 /
# TK-BUG-P2-01 (glue that resolves "which live node does this RPC broadcast's
# result apply to" being silently wrong under green pure-function tests). The
# tests above cover the PURE timer/re-pick logic (RoundRules + TigerSelector);
# this section covers the separate scene-tree step RoundManager.start_new_
# round() performs on a timer-driven Tiger swap -- resolving the just-expired
# and newly-picked Player nodes off the "Players" root and calling set_role()
# on the CORRECT node -- which nothing asserted at the observable-effect level
# before this card. Real Player.tscn instances (no mocks).
#
# SETUP is decoupled from RoundManager._ready() -- start_new_round() depends
# ONLY on RoundManager's `_players_root`, so the real Player.tscn instances are
# spawned under an in-tree "Players" root (so each Player's own authority
# resolves) and that root is injected into a RoundManager NOT added to the tree,
# so its host-only _ready() (role_changed watchers) and _physics_process()
# (the round timer) never run and cannot interfere. Same helper shape as
# tests/test_tag_sequence.gd's own "apply_role_switch" SETUP note describes.

func _spawn_player(players: Node, peer_name: String, role: StringName) -> CharacterBody3D:
	var p: CharacterBody3D = PlayerScene.instantiate()
	p.name = peer_name
	players.add_child(p)
	if role != ROLE_OUTER:
		p.set_role(role)
	return p


func _build_players_root() -> Node:
	var root := Node3D.new()
	add_child_autofree(root)
	var players := Node3D.new()
	players.name = "Players"
	root.add_child(players)
	return players


func _make_round_manager(players: Node) -> Node:
	var rm: Node = RoundManagerScript.new()
	autofree(rm)
	rm._players_root = players
	return rm


func test_start_new_round_flips_the_two_resolved_players_to_the_correct_roles() -> void:
	var players: Node = _build_players_root()
	var rm: Node = _make_round_manager(players)

	var old_tiger: CharacterBody3D = _spawn_player(players, "1", ROLE_TIGER) # current Tiger
	var new_tiger: CharacterBody3D = _spawn_player(players, "2", ROLE_OUTER)
	var bystander: CharacterBody3D = _spawn_player(players, "3", ROLE_OUTER)

	assert_eq(old_tiger.role, ROLE_TIGER, "sanity: the just-expired Tiger is the Tiger before the restart")

	rm.start_new_round(1, 2)

	assert_eq(new_tiger.role, ROLE_TIGER,
		"start_new_round must resolve Players/2 and crown IT the new Tiger -- the observable role must land on the correct node, not just run without crashing")
	assert_eq(old_tiger.role, ROLE_OUTER,
		"start_new_round must resolve Players/1 and flip the just-expired Tiger back to Outer")
	assert_eq(bystander.role, ROLE_OUTER,
		"a Player not involved in the round restart must be left untouched (timeout swap touches exactly two nodes)")
