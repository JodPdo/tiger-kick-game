extends GutTest
## Unit tests for characters/abilities/KickRules.gd (TK-P2-01) and the
## owner-side cooldown prediction on characters/abilities/KickAbility.gd.
##
## Only node-independent logic is covered here (design doc §3 testability
## note): KickRules is a pure static helper (same pattern as
## managers/TigerSelector.gd / networking/SpawnPointUtil.gd), and
## KickAbility.can_activate()/on_rejected() touch nothing but their own
## `_owner_last_fire_ms`/`cooldown_sec` members -- no scene tree, no
## multiplayer context, so a bare `KickAbility.new()` (never added to a
## tree, @onready `_body` left unresolved) is safe to exercise directly, same
## as tests/test_ability_system.gd's bare Ability instances. host_apply()/
## on_confirmed() DO need a live scene tree + multiplayer context and are
## covered by the manual 2-instance pipeline proof in this card's handoff
## note instead.
##
## TK-P2-32 (gameplay-engineer, bug fix): host_validate() itself IS covered
## below now (the "--- KickAbility.host_validate role filter ---" section),
## despite the note above -- unlike can_activate()/on_rejected(), the bug
## this card fixes lives entirely in host_validate()'s candidate-building
## loop (a role filter on live sibling Players), so a real Player.tscn scene
## tree is unavoidable to exercise it meaningfully. Same
## `PlayerScene.instantiate()` + `add_child_autofree()` pattern
## tests/test_ability_system.gd and tests/test_role_state_machine.gd already
## use for their own Player.tscn-touching tests -- multiplayer.is_server()
## defaults true offline (headless GUT, no peer ever assigned), which is all
## host_validate()'s own assert requires.

const KickRulesScript := preload("res://characters/abilities/KickRules.gd")
const KickAbilityScript := preload("res://characters/abilities/KickAbility.gd")
const PlayerScene := preload("res://characters/Player.tscn")
const GameManagerScript := preload("res://managers/GameManager.gd")
const CountdownManagerScript := preload("res://managers/CountdownManager.gd")
const MatchStateRulesScript := preload("res://managers/MatchStateRules.gd")


# --- KickRules.is_in_range (pure) ------------------------------------------

func test_is_in_range_true_at_exactly_the_boundary() -> void:
	# Inclusive boundary (<=), per KickRules.gd's own doc comment.
	assert_true(KickRulesScript.is_in_range(Vector3.ZERO, Vector3(1.5, 0, 0), 1.5))


func test_is_in_range_true_when_closer_than_range() -> void:
	assert_true(KickRulesScript.is_in_range(Vector3.ZERO, Vector3(1.0, 0, 0), 1.5))


func test_is_in_range_false_when_farther_than_range() -> void:
	assert_false(KickRulesScript.is_in_range(Vector3.ZERO, Vector3(1.51, 0, 0), 1.5))


func test_is_in_range_ignores_which_point_is_the_kicker() -> void:
	# Distance is symmetric -- a(b) must equal b(a).
	var a: Vector3 = Vector3(2, 0, 0)
	var b: Vector3 = Vector3(0, 0, 0)
	assert_eq(KickRulesScript.is_in_range(a, b, 1.5), KickRulesScript.is_in_range(b, a, 1.5))


# --- KickRules.nearest_target (pure) ---------------------------------------

func test_nearest_target_picks_the_closest_candidate_in_range() -> void:
	var candidates: Array = [
		{"id": "2", "position": Vector3(1.4, 0, 0)},
		{"id": "3", "position": Vector3(0.5, 0, 0)},
	]
	var result: Dictionary = KickRulesScript.nearest_target(Vector3.ZERO, candidates, 1.5)
	assert_eq(result.get("id"), "3", "the CLOSER in-range candidate should win, not the first in the array")


func test_nearest_target_ignores_candidates_out_of_range() -> void:
	var candidates: Array = [
		{"id": "2", "position": Vector3(5.0, 0, 0)}, # way out of range
	]
	var result: Dictionary = KickRulesScript.nearest_target(Vector3.ZERO, candidates, 1.5)
	assert_true(result.is_empty(), "an out-of-range-only candidate list must return an empty Dictionary, never null/crash")


func test_nearest_target_returns_empty_dictionary_for_no_candidates() -> void:
	var result: Dictionary = KickRulesScript.nearest_target(Vector3.ZERO, [], 1.5)
	assert_true(result.is_empty())


func test_nearest_target_tie_resolves_to_first_in_array() -> void:
	var candidates: Array = [
		{"id": "2", "position": Vector3(1.0, 0, 0)},
		{"id": "3", "position": Vector3(0.0, 1.0, 0)}, # exact same distance (1.0) from origin
	]
	var result: Dictionary = KickRulesScript.nearest_target(Vector3.ZERO, candidates, 1.5)
	assert_eq(result.get("id"), "2", "an exact distance tie should resolve to whichever candidate appears first")


# --- KickRules.can_fire (pure cooldown ledger) ------------------------------

func test_can_fire_true_when_never_fired_before() -> void:
	assert_true(KickRulesScript.can_fire(-1, 0.6, 1000))


func test_can_fire_false_immediately_after_firing() -> void:
	assert_false(KickRulesScript.can_fire(1000, 0.6, 1050), "50ms after a 0.6s-cooldown fire must still be on cooldown")


func test_can_fire_true_once_cooldown_has_fully_elapsed() -> void:
	assert_true(KickRulesScript.can_fire(1000, 0.6, 1600), "exactly cooldown_sec later should be allowed again (inclusive)")


func test_can_fire_true_well_after_cooldown_elapsed() -> void:
	assert_true(KickRulesScript.can_fire(1000, 0.6, 5000))


func test_can_fire_zero_cooldown_always_allows() -> void:
	assert_true(KickRulesScript.can_fire(1000, 0.0, 1000), "cooldown_sec == 0.0 must never block a fire")


# --- KickAbility.host_validate role filter (TK-P2-32 bug fix) --------------
# Regression coverage for the bug this card fixes: host_validate()'s
# candidate-building loop used to accept EVERY other CharacterBody3D under the
# Players root with no role filter at all, so an Outer's Kick could land on
# (and be host-CONFIRMED against) ANOTHER OUTER instead of the Tiger whenever
# that Outer happened to be the nearest candidate to the kicker. This was
# invisible at N=2 (where "nearest other player" trivially IS the Tiger) --
# it only surfaces once a 3rd player is present, which every prior
# human-pass/probe run at N=2 never exercised. Each test below builds a real
# "Players" root with a MIX of roles so KickRules.nearest_target() would have
# a wrong (non-Tiger) candidate to pick if host_validate() no longer filtered
# by role -- a test that only used one Outer + one Tiger would NOT catch this
# regression (see the class doc SCOPE NOTE this card's fix updates).
#
# Needs a real Player.tscn scene tree (role lives on the live CharacterBody3D,
# not anything KickRules' pure statics touch) -- same
# `PlayerScene.instantiate()` + `add_child_autofree()` pattern
# tests/test_ability_system.gd and tests/test_role_state_machine.gd already
# use. host_validate()'s own `assert(multiplayer.is_server())` is satisfied
# for free: headless GUT's SceneMultiplayer defaults to server=true offline
# (no ENet peer is ever assigned in this file).

const ROLE_TIGER: StringName = &"tiger"
const ROLE_OUTER: StringName = &"outer"

var _kick_players_root: Node3D
var _kick_kicker: CharacterBody3D


## Instantiates a real Player.tscn under `_kick_players_root`, named/positioned/
## role-assigned as requested. Player.gd defaults to Outer (Player.gd:106), so
## `set_role()` is only called when a non-default role is actually needed.
func _spawn_kick_candidate(peer_name: String, role: StringName, position: Vector3) -> CharacterBody3D:
	var player: CharacterBody3D = PlayerScene.instantiate()
	# Naming contract (TK-BUG-P1-01, node.name == str(peer_id)): set BEFORE
	# entering the tree, same pattern the other Player.tscn-touching test
	# files already use.
	player.name = peer_name
	_kick_players_root.add_child(player)
	player.global_position = position
	if role != ROLE_OUTER:
		player.set_role(role)
	return player


func test_host_validate_targets_the_tiger_even_when_a_closer_outer_exists() -> void:
	_kick_players_root = Node3D.new()
	add_child_autofree(_kick_players_root)

	_kick_kicker = _spawn_kick_candidate("1", ROLE_OUTER, Vector3.ZERO)
	# Deliberately CLOSER to the kicker than the Tiger -- this is exactly the
	# wrong-target regression: an un-filtered KickRules.nearest_target() would
	# pick THIS Outer over the Tiger below.
	_spawn_kick_candidate("2", ROLE_OUTER, Vector3(0.3, 0, 0))
	var tiger: CharacterBody3D = _spawn_kick_candidate("3", ROLE_TIGER, Vector3(1.0, 0, 0))

	var ability_controller: Node = _kick_kicker.get_node("AbilityController")
	var kick_ability: KickAbility = ability_controller._abilities[&"kick"]

	var verdict: Dictionary = kick_ability.host_validate({"sender_id": 1})

	assert_true(verdict.get("ok", false), "a Tiger IS in range -- host_validate must accept the kick")
	var result: Dictionary = verdict.get("result", {})
	assert_eq(String(result.get("target_id")), String(tiger.name),
		"Kick must land on the TIGER, not the objectively closer Outer candidate (TK-P2-32 regression)")


func test_host_validate_never_substitutes_an_in_range_outer_when_no_tiger_is_reachable() -> void:
	_kick_players_root = Node3D.new()
	add_child_autofree(_kick_players_root)

	_kick_kicker = _spawn_kick_candidate("1", ROLE_OUTER, Vector3.ZERO)
	_spawn_kick_candidate("2", ROLE_OUTER, Vector3(0.5, 0, 0)) # in range, but not the Tiger
	_spawn_kick_candidate("3", ROLE_TIGER, Vector3(10.0, 0, 0)) # the Tiger, but out of range

	var ability_controller: Node = _kick_kicker.get_node("AbilityController")
	var kick_ability: KickAbility = ability_controller._abilities[&"kick"]

	var verdict: Dictionary = kick_ability.host_validate({"sender_id": 1})

	assert_false(verdict.get("ok", false),
		"no Tiger is in range -- an in-range Outer must never be accepted as a substitute target")
	assert_eq(verdict.get("reason"), "no_target_in_range")


# --- KickAbility.host_validate match-state gate (TK-BUG-P3-02 consistency) --
# The human's bug report for TagAbility's own identical gap explicitly flagged
# Kick's stagger-applying path too, "for consistency/future-proofing" -- see
# characters/abilities/KickAbility.gd's own doc on _game_manager()/the new
# host_validate() gate. Unlike the role-filter tests above (a bare
# "_kick_players_root", no arena needed), KickAbility._game_manager() walks up
# to _kick_players_root's PARENT looking for a "GameManager" sibling -- so
# these two tests build a full mirror of world/TestArena.tscn's own shape (an
# arena root with "Players"/"CountdownManager"/"GameManager" children, exactly
# tests/test_match_end_flow.gd's own _build_arena()/_add_game_manager() shape)
# rather than reusing _kick_players_root directly, so GameManager's own
# host-only _ready() (which DOES run for real here, unlike this file's other
# tests) resolves its own sibling lookups without crashing.

func _build_kick_arena_with_game_manager(match_state: int) -> Node:
	var arena := Node3D.new()
	add_child_autofree(arena)
	var players := Node3D.new()
	players.name = "Players"
	arena.add_child(players)
	var countdown := CountdownManagerScript.new()
	countdown.name = "CountdownManager"
	arena.add_child(countdown)
	var gm := GameManagerScript.new()
	gm.name = "GameManager"
	arena.add_child(gm)
	# _ready() (0 Players present at that moment) armed the match-ready watch
	# -- suppress it (this test drives match_state directly, same "not this
	# card's scope" reasoning tests/test_match_end_flow.gd's own
	# _add_game_manager() helper documents) before spawning any candidates.
	gm._countdown_started = true
	gm.match_state = match_state
	return arena


func test_host_validate_rejects_a_kick_once_the_match_has_ended() -> void:
	var arena: Node = _build_kick_arena_with_game_manager(MatchStateRulesScript.State.MATCH_END)
	_kick_players_root = arena.get_node("Players")

	_kick_kicker = _spawn_kick_candidate("1", ROLE_OUTER, Vector3.ZERO)
	_spawn_kick_candidate("2", ROLE_TIGER, Vector3(1.0, 0, 0))

	var ability_controller: Node = _kick_kicker.get_node("AbilityController")
	var kick_ability: KickAbility = ability_controller._abilities[&"kick"]

	var verdict: Dictionary = kick_ability.host_validate({"sender_id": 1})

	assert_false(verdict.get("ok", false), "a Kick attempted after MATCH_END must be rejected")
	assert_eq(verdict.get("reason"), "match_not_playing")


func test_host_validate_still_accepts_a_kick_while_playing_with_a_gamemanager_present() -> void:
	var arena: Node = _build_kick_arena_with_game_manager(MatchStateRulesScript.State.PLAYING)
	_kick_players_root = arena.get_node("Players")

	_kick_kicker = _spawn_kick_candidate("1", ROLE_OUTER, Vector3.ZERO)
	var tiger: CharacterBody3D = _spawn_kick_candidate("2", ROLE_TIGER, Vector3(1.0, 0, 0))

	var ability_controller: Node = _kick_kicker.get_node("AbilityController")
	var kick_ability: KickAbility = ability_controller._abilities[&"kick"]

	var verdict: Dictionary = kick_ability.host_validate({"sender_id": 1})

	assert_true(verdict.get("ok", false), "match is PLAYING -- must not block an otherwise-legal kick")
	assert_eq(String(verdict.get("result", {}).get("target_id")), String(tiger.name))


func test_host_validate_still_accepts_a_kick_when_no_gamemanager_exists_in_the_scene() -> void:
	# Fail-OPEN when GameManager is simply absent (see KickAbility._game_manager()'s
	# own doc) -- Kick must not newly REQUIRE a GameManager to function; every
	# OTHER test in this file (predating this gate) relies on exactly this,
	# using the bare _kick_players_root shape (no arena/GameManager at all).
	_kick_players_root = Node3D.new()
	add_child_autofree(_kick_players_root)

	_kick_kicker = _spawn_kick_candidate("1", ROLE_OUTER, Vector3.ZERO)
	var tiger: CharacterBody3D = _spawn_kick_candidate("2", ROLE_TIGER, Vector3(1.0, 0, 0))

	var ability_controller: Node = _kick_kicker.get_node("AbilityController")
	var kick_ability: KickAbility = ability_controller._abilities[&"kick"]

	var verdict: Dictionary = kick_ability.host_validate({"sender_id": 1})

	assert_true(verdict.get("ok", false), "no GameManager present -- must not block an otherwise-legal kick")
	assert_eq(String(verdict.get("result", {}).get("target_id")), String(tiger.name))


# --- KickAbility.on_confirmed() Kick Stagger targeting (TK-BUG-P2-01 bug fix)
# Regression coverage for the bug this card fixes: on_confirmed() runs, via
# AbilityController's rpc_confirm `call_local` broadcast, in the context of
# the KICKER's own KickAbility node (Kick is a HumanAbility living on the
# ACTING OUTER's own AbilityController/Player subtree) -- so `_body` inside
# on_confirmed() is ALWAYS the kicker's own Player node, never the target's.
# The pre-fix version gated directly on `_body.role == RoleRules.TIGER` and
# `String(_body.name) == String(target_id)` -- both permanently false for the
# node this code actually runs on (the kicker is by definition never the
# Tiger it just kicked, and never equal to its own target_id), so
# MovementComponent.start_stagger() was structurally unreachable at any N.
# Live-tested: 12 kicks landed on the Tiger, zero stagger, zero
# "[KICK] stagger applied locally" log line (see this card's own backlog
# note). This is the SAME bug CLASS as TK-P2-32 above (dead/misrouted wiring
# invisible to green unit tests) -- the pure StaggerRules math stays correct
# in isolation; the defect is entirely in on_confirmed()'s node resolution
# under a real broadcast, which is exactly what a scene-tree-level test (not
# a mock) is needed to exercise.
#
# Same `PlayerScene.instantiate()` + `add_child_autofree()` +
# `_spawn_kick_candidate()` scene-tree pattern the TK-P2-32 section above
# already established, reused here rather than inventing a new one.
# `is_multiplayer_authority()` needs no live ENet peer to be meaningful
# offline: headless GUT's own SceneMultiplayer defaults to unique_id 1 (see
# tests/test_ability_system.gd's own authority tests, e.g.
# test_player_root_keeps_owner_authority_when_controller_overrides), and
# Player._enter_tree() derives each Player's own multiplayer authority from
# `int(name)` -- so a Player named "1" reports is_multiplayer_authority() ==
# true (this local/headless peer "owns" it), and a Player named anything else
# reports false, with no networking setup required.
#
# LOAD-BEARING: these assertions read the TARGET Tiger's own
# MovementComponent.is_staggered() (the actual OBSERVABLE side effect this
# card's fix must produce), not just "on_confirmed() ran without crashing".
# Against the pre-fix `_body`-anchored gates, test_on_confirmed_stagger_
# applies_to_the_resolved_target_not_the_kicker() below fails RED (the Tiger
# named "1" is never `_body` -- `_body` is always the kicker -- so neither
# pre-fix gate ever passes and start_stagger() is never called on anything);
# against the fix, it passes GREEN.

func test_on_confirmed_stagger_applies_to_the_resolved_target_not_the_kicker() -> void:
	_kick_players_root = Node3D.new()
	add_child_autofree(_kick_players_root)

	# Kicker: an Outer, deliberately NOT named "1" -- must never be the one
	# who ends up staggered.
	var kicker: CharacterBody3D = _spawn_kick_candidate("2", ROLE_OUTER, Vector3.ZERO)
	# Target: a Tiger named "1" -- the local headless-GUT peer's own id, so
	# is_multiplayer_authority() reports true for it (see section doc above),
	# simulating "this machine owns the Tiger that just got kicked".
	var tiger: CharacterBody3D = _spawn_kick_candidate("1", ROLE_TIGER, Vector3(1.0, 0, 0))

	var ability_controller: Node = kicker.get_node("AbilityController")
	var kick_ability: KickAbility = ability_controller._abilities[&"kick"]

	var tiger_movement: Node = tiger.get_node("MovementComponent")
	var kicker_movement: Node = kicker.get_node("MovementComponent")
	assert_false(tiger_movement.is_staggered(), "sanity: the Tiger must not already be staggered before on_confirmed() runs")

	kick_ability.on_confirmed({"kicker_id": 2, "target_id": tiger.name})

	assert_true(tiger_movement.is_staggered(),
		"TK-BUG-P2-01: on_confirmed() must resolve+stagger the TARGET Player (the Tiger), not identity-match _body -- MovementComponent.is_staggered() should now be true")
	assert_false(kicker_movement.is_staggered(),
		"the KICKER's own MovementComponent must never be staggered -- confirms the fix resolves the TARGET, not _body")


func test_on_confirmed_does_nothing_when_this_local_peer_does_not_own_the_target() -> void:
	_kick_players_root = Node3D.new()
	add_child_autofree(_kick_players_root)

	var kicker: CharacterBody3D = _spawn_kick_candidate("2", ROLE_OUTER, Vector3.ZERO)
	# Target Tiger named "3" -- NOT the local headless-GUT peer's own id (1),
	# so is_multiplayer_authority() must report false for it: simulates a 3rd
	# peer's own window observing a kick that landed on someone ELSE's Tiger
	# -- it still runs on_confirmed() (the broadcast reaches everyone) but
	# must apply no local physics effect of its own.
	var tiger: CharacterBody3D = _spawn_kick_candidate("3", ROLE_TIGER, Vector3(1.0, 0, 0))

	var ability_controller: Node = kicker.get_node("AbilityController")
	var kick_ability: KickAbility = ability_controller._abilities[&"kick"]

	kick_ability.on_confirmed({"kicker_id": 2, "target_id": tiger.name})

	var tiger_movement: Node = tiger.get_node("MovementComponent")
	assert_false(tiger_movement.is_staggered(),
		"a peer that does not own the targeted Player must never apply a local stagger, even though it still runs on_confirmed() via the broadcast")


func test_on_confirmed_ignores_a_non_tiger_target_even_if_locally_owned() -> void:
	_kick_players_root = Node3D.new()
	add_child_autofree(_kick_players_root)

	var kicker: CharacterBody3D = _spawn_kick_candidate("2", ROLE_OUTER, Vector3.ZERO)
	# An Outer named "1" (locally owned) -- host_validate() would never
	# actually confirm a kick against a non-Tiger (TK-P2-32's role filter),
	# but this defense-in-depth gate must still hold on its own if it ever
	# somehow ran against an Outer id.
	var outer: CharacterBody3D = _spawn_kick_candidate("1", ROLE_OUTER, Vector3(1.0, 0, 0))

	var ability_controller: Node = kicker.get_node("AbilityController")
	var kick_ability: KickAbility = ability_controller._abilities[&"kick"]

	kick_ability.on_confirmed({"kicker_id": 2, "target_id": outer.name})

	var outer_movement: Node = outer.get_node("MovementComponent")
	assert_false(outer_movement.is_staggered(), "Kick Stagger must never apply to a non-Tiger target, even when locally owned")


func test_on_confirmed_does_not_crash_when_the_target_node_is_gone() -> void:
	_kick_players_root = Node3D.new()
	add_child_autofree(_kick_players_root)

	var kicker: CharacterBody3D = _spawn_kick_candidate("2", ROLE_OUTER, Vector3.ZERO)
	var ability_controller: Node = kicker.get_node("AbilityController")
	var kick_ability: KickAbility = ability_controller._abilities[&"kick"]

	# "9" was never spawned under _kick_players_root -- simulates the target
	# disconnecting between the kick landing and this confirm arriving.
	kick_ability.on_confirmed({"kicker_id": 2, "target_id": "9"})
	assert_true(true, "on_confirmed must not crash when the confirmed target_id no longer resolves to a live node")


# --- KickAbility owner-side cooldown prediction (can_activate/on_rejected) -

var _kick: KickAbility


func after_each() -> void:
	if is_instance_valid(_kick):
		_kick.free()
		_kick = null


func test_kick_ability_defaults() -> void:
	_kick = KickAbilityScript.new()
	assert_eq(_kick.ability_id, &"kick", "KickAbility must set its own ability_id (overridden in _init, not the base default)")
	assert_eq(_kick.input_action, &"kick")
	assert_eq(_kick.cooldown_sec, 0.6)
	assert_eq(_kick.kick_range_m, 1.5, "Game_Balance.md Kick range")
	assert_eq(_kick.resolution, Ability.Resolution.HOST_AUTHORITATIVE, "Kick must stay HOST_AUTHORITATIVE (design doc §3: kick decides the game)")


func test_kick_ability_is_a_human_ability() -> void:
	_kick = KickAbilityScript.new()
	assert_true(_kick is HumanAbility, "KickAbility must extend HumanAbility, per AbilityCatalog's Outer registration")


func test_can_activate_true_before_ever_firing() -> void:
	_kick = KickAbilityScript.new()
	assert_true(_kick.can_activate({}))


func test_can_activate_false_immediately_after_a_predicted_fire() -> void:
	_kick = KickAbilityScript.new()
	_kick._owner_last_fire_ms = Time.get_ticks_msec()
	assert_false(_kick.can_activate({}), "owner-predicted cooldown must block an immediate second activation")


func test_on_rejected_clears_the_owner_predicted_cooldown() -> void:
	_kick = KickAbilityScript.new()
	_kick._owner_last_fire_ms = Time.get_ticks_msec()
	assert_false(_kick.can_activate({}), "sanity: cooldown should be active before the rejection")
	_kick.on_rejected("no_target_in_range")
	assert_true(_kick.can_activate({}), "on_rejected must roll back the owner-predicted cooldown -- the kick never actually landed")

