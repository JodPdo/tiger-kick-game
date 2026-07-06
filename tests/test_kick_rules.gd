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
## as tests/test_ability_system.gd's bare Ability instances. host_validate()/
## host_apply()/on_confirmed() DO need a live scene tree + multiplayer
## context (sibling Players, `multiplayer.is_server()`) and are covered by
## the manual 2-instance pipeline proof in this card's handoff note instead.

const KickRulesScript := preload("res://characters/abilities/KickRules.gd")
const KickAbilityScript := preload("res://characters/abilities/KickAbility.gd")


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

