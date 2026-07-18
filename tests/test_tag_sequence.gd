extends GutTest
## Unit tests for TK-P2-03 (Tag Sequence): the pure static helpers
## characters/abilities/TagAbilityRules.gd and managers/TagSequenceRules.gd,
## plus the owner-side cooldown prediction and bare-instance defaults on
## characters/abilities/TagAbility.gd.
##
## Only node-independent logic is covered here (design doc §3 testability
## note), same split test_kick_rules.gd documents for Kick: TagAbilityRules/
## TagSequenceRules are pure static helpers (no scene tree, no multiplayer
## context), and TagAbility.can_activate()/on_rejected() touch nothing but
## their own `_owner_last_fire_ms`/`cooldown_sec` members -- a bare
## `TagAbility.new()` would need a live Player/AbilityController tree for its
## @onready `_body`/`_tag_detector` (unlike KickAbility, which only caches
## `_body`), so those two @onready vars are NOT touched by the bare-instance
## tests below; only the plain script-level defaults/cooldown members are
## exercised, same shape as test_ability_system.gd's bare Ability instances.
## host_validate()/host_apply()/on_confirmed() DO need a live scene tree +
## multiplayer context (sibling Players, TagDetector, GameManager) and are
## covered by the manual 2-instance pipeline proof this card's handoff note
## calls for, not GUT.

const TagAbilityRulesScript := preload("res://characters/abilities/TagAbilityRules.gd")
const TagSequenceRulesScript := preload("res://managers/TagSequenceRules.gd")
const TagAbilityScript := preload("res://characters/abilities/TagAbility.gd")


# --- TagAbilityRules.can_fire (pure cooldown ledger) ------------------------

func test_can_fire_true_when_never_fired_before() -> void:
	assert_true(TagAbilityRulesScript.can_fire(-1, 0.6, 1000))


func test_can_fire_false_immediately_after_firing() -> void:
	assert_false(TagAbilityRulesScript.can_fire(1000, 0.6, 1050), "50ms after a 0.6s-cooldown fire must still be on cooldown")


func test_can_fire_true_once_cooldown_has_fully_elapsed() -> void:
	assert_true(TagAbilityRulesScript.can_fire(1000, 0.6, 1600), "exactly cooldown_sec later should be allowed again (inclusive)")


func test_can_fire_true_well_after_cooldown_elapsed() -> void:
	assert_true(TagAbilityRulesScript.can_fire(1000, 0.6, 5000))


func test_can_fire_zero_cooldown_always_allows() -> void:
	assert_true(TagAbilityRulesScript.can_fire(1000, 0.0, 1000), "cooldown_sec == 0.0 must never block a fire")


# --- TagSequenceRules.can_start_sequence (mandatory re-trigger guard) -------

func test_can_start_sequence_true_when_not_active() -> void:
	assert_true(TagSequenceRulesScript.can_start_sequence(false))


func test_can_start_sequence_false_when_already_active() -> void:
	assert_false(TagSequenceRulesScript.can_start_sequence(true), "a Tag Sequence already running must block a second one (TK-P2-02 boundary-jitter finding)")


# --- TagSequenceRules.is_valid_role_swap ------------------------------------

func test_is_valid_role_swap_true_for_two_distinct_valid_ids() -> void:
	assert_true(TagSequenceRulesScript.is_valid_role_swap(1, 2))


func test_is_valid_role_swap_false_when_old_equals_new() -> void:
	assert_false(TagSequenceRulesScript.is_valid_role_swap(2, 2), "a Tiger can never swap with itself")


func test_is_valid_role_swap_false_for_negative_old_id() -> void:
	assert_false(TagSequenceRulesScript.is_valid_role_swap(-1, 2))


func test_is_valid_role_swap_false_for_negative_new_id() -> void:
	assert_false(TagSequenceRulesScript.is_valid_role_swap(1, -1))


# --- TagSequenceRules.compute_exit_position (step 6 placeholder math) ------

func test_compute_exit_position_preserves_direction_and_y() -> void:
	# Standing 2m out along +X, 1.5m up -- exit should land at exit_radius_m
	# along that SAME +X direction, preserving Y.
	var result: Vector3 = TagSequenceRulesScript.compute_exit_position(Vector3(2.0, 1.5, 0.0), 6.0)
	assert_almost_eq(result.x, 6.0, 0.001)
	assert_almost_eq(result.y, 1.5, 0.001, "Y must be preserved -- no vertical teleport")
	assert_almost_eq(result.z, 0.0, 0.001)


func test_compute_exit_position_scales_to_exactly_exit_radius_m() -> void:
	var result: Vector3 = TagSequenceRulesScript.compute_exit_position(Vector3(1.0, 0.0, 1.0), 6.0)
	var horizontal_dist: float = Vector2(result.x, result.z).length()
	assert_almost_eq(horizontal_dist, 6.0, 0.001, "the resulting horizontal distance from center must equal exit_radius_m exactly")


func test_compute_exit_position_falls_back_to_default_direction_at_center() -> void:
	# current_position is exactly at the arena center -- "direction from
	# center" is undefined, so the function must fall back to default_direction.
	var result: Vector3 = TagSequenceRulesScript.compute_exit_position(Vector3.ZERO, 6.0, Vector3(1.0, 0.0, 0.0))
	assert_almost_eq(result.x, 6.0, 0.001)
	assert_almost_eq(result.z, 0.0, 0.001)


func test_compute_exit_position_falls_back_to_forward_when_default_direction_is_also_degenerate() -> void:
	# default_direction straight up (no horizontal component) is ALSO
	# degenerate once flattened -- must fall back to Vector3.FORWARD.
	var result: Vector3 = TagSequenceRulesScript.compute_exit_position(Vector3.ZERO, 6.0, Vector3.UP)
	var expected: Vector3 = Vector3.FORWARD * 6.0
	assert_almost_eq(result.x, expected.x, 0.001)
	assert_almost_eq(result.z, expected.z, 0.001)


# --- TagAbility bare-instance defaults + owner-side cooldown prediction ----
# Mirrors test_kick_rules.gd's own KickAbility bare-instance tests exactly:
# can_activate()/on_rejected() touch only `_owner_last_fire_ms`/`cooldown_sec`
# (plain script members), never the @onready `_body`/`_tag_detector` (which
# stay unresolved on a bare `.new()` never added to a tree) -- safe to call
# directly. on_activate_local() is NOT exercised here (it reads `_body.name`
# for a log line) -- that needs a live tree, same scope line KickAbility's
# own tests draw for its analogous scaffold.

var _tag: TagAbility


func after_each() -> void:
	if is_instance_valid(_tag):
		_tag.free()
		_tag = null


func test_tag_ability_defaults() -> void:
	_tag = TagAbilityScript.new()
	assert_eq(_tag.ability_id, &"tag", "TagAbility must set its own ability_id (overridden in _init, not the base default)")
	assert_eq(_tag.input_action, &"tag")
	assert_eq(_tag.cooldown_sec, 0.6)
	assert_eq(_tag.tag_range_m, 2.0, "matches TagDetectorComponent.tag_range_m's own placeholder default")
	assert_eq(_tag.resolution, Ability.Resolution.HOST_AUTHORITATIVE, "Tag must stay HOST_AUTHORITATIVE (design doc §3: Tag decides the game)")


func test_tag_ability_is_a_tiger_ability() -> void:
	_tag = TagAbilityScript.new()
	assert_true(_tag is TigerAbility, "TagAbility must extend TigerAbility, per AbilityCatalog's Tiger registration")


func test_can_activate_true_before_ever_firing() -> void:
	_tag = TagAbilityScript.new()
	assert_true(_tag.can_activate({}))


func test_can_activate_false_immediately_after_a_predicted_fire() -> void:
	_tag = TagAbilityScript.new()
	_tag._owner_last_fire_ms = Time.get_ticks_msec()
	assert_false(_tag.can_activate({}), "owner-predicted cooldown must block an immediate second activation")


func test_on_rejected_clears_the_owner_predicted_cooldown() -> void:
	_tag = TagAbilityScript.new()
	_tag._owner_last_fire_ms = Time.get_ticks_msec()
	assert_false(_tag.can_activate({}), "sanity: cooldown should be active before the rejection")
	_tag.on_rejected("no_target_in_range")
	assert_true(_tag.can_activate({}), "on_rejected must roll back the owner-predicted cooldown -- the tag never actually landed")


# --- AbilityCatalog registration (TK-P2-03) ---------------------------------

func test_tiger_role_has_tag_registered() -> void:
	# TK-P2-18: Tiger's catalog now has a second entry (PounceAbility)
	# alongside TagAbility -- see tests/test_ability_system.gd's own
	# test_tiger_role_has_tag_registered()/test_tiger_role_has_pounce_
	# registered() for the full catalog-registration coverage; this test
	# stays as a light TagAbility-specific sanity check (TagAbility.gd is
	# still present, still first).
	var result: Array = AbilityCatalog.abilities_for_role(&"tiger")
	assert_eq(result.size(), 2, "Tiger catalog should have exactly two entries (TagAbility, PounceAbility) at this step")
	assert_eq(result[0], TagAbilityScript, "Tiger's first catalog entry should be TagAbility.gd")
