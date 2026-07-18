extends GutTest
## Unit tests for characters/components/StaggerRules.gd (TK-P2-17) and the
## node-independent stagger-knockback seam on
## characters/components/MovementComponent.gd (start_stagger() /
## cancel_stagger() / resolve_stagger_knockback() / is_staggered(), plus the
## additive-not-overriding interaction with resolve_horizontal_velocity()).
##
## Only node-independent logic is covered here (design doc section 3
## testability note, same pattern as tests/test_kick_rules.gd /
## tests/test_pounce_rules.gd): StaggerRules is a pure static helper, and
## none of the MovementComponent methods under test touch _body/_camera_rig
## -- only the component's own _stagger_*/_pounce_* state -- so a bare
## MovementComponent.new() (never added to a tree, @onready members left
## unresolved) is safe to exercise directly, same as
## tests/test_pounce_rules.gd's own bare instances.
## characters/abilities/KickAbility.gd's on_confirmed() (the "am I the
## confirmed target" role/id gate + kicker-lookup wiring that actually calls
## start_stagger()) needs a live scene tree + multiplayer context and is NOT
## covered here -- see this card's handoff note for the manual 2-instance
## pass that exercises that instead.

const StaggerRulesScript := preload("res://characters/components/StaggerRules.gd")
const MovementComponentScript := preload("res://characters/components/MovementComponent.gd")


# --- StaggerRules.direction_away_from (pure) --------------------------------

func test_direction_away_from_points_from_kicker_to_target() -> void:
	var kicker: Vector3 = Vector3(0, 0, 0)
	var target: Vector3 = Vector3(2, 0, 0)
	var result: Vector3 = StaggerRulesScript.direction_away_from(kicker, target)
	assert_eq(result, Vector3(1, 0, 0), "direction must point away from the kicker, toward the target")


func test_direction_away_from_is_normalized() -> void:
	var result: Vector3 = StaggerRulesScript.direction_away_from(Vector3.ZERO, Vector3(3, 0, 4))
	assert_almost_eq(result.length(), 1.0, 0.001, "direction must always be unit length regardless of the source distance")


func test_direction_away_from_flattens_vertical_component() -> void:
	var result: Vector3 = StaggerRulesScript.direction_away_from(Vector3(0, 0, 0), Vector3(1, 5, 0))
	assert_eq(result.y, 0.0, "knockback direction must never carry a vertical component -- gravity/step_jump own the Y axis")


func test_direction_away_from_degenerate_same_position_is_safe() -> void:
	var same: Vector3 = Vector3(3, 1, -2)
	var result: Vector3 = StaggerRulesScript.direction_away_from(same, same)
	assert_eq(result, Vector3.ZERO, "coincident positions must not crash on normalized() and must yield zero direction")


# --- StaggerRules.decayed_speed (pure linear decay) -------------------------

func test_decayed_speed_full_at_zero_elapsed() -> void:
	assert_eq(StaggerRulesScript.decayed_speed(0, 300, 4.0), 4.0, "at the instant of impact, speed must be the full initial_speed")


func test_decayed_speed_negative_elapsed_treated_as_full() -> void:
	assert_eq(StaggerRulesScript.decayed_speed(-10, 300, 4.0), 4.0)


func test_decayed_speed_halfway_is_half_speed() -> void:
	assert_almost_eq(StaggerRulesScript.decayed_speed(150, 300, 4.0), 2.0, 0.001, "linear decay: halfway through the duration must be half the initial speed")


func test_decayed_speed_zero_at_exact_duration() -> void:
	assert_eq(StaggerRulesScript.decayed_speed(300, 300, 4.0), 0.0, "duration_ms is the inclusive end of the decay -- fully expired by then")


func test_decayed_speed_zero_past_duration() -> void:
	assert_eq(StaggerRulesScript.decayed_speed(9999, 300, 4.0), 0.0)


func test_decayed_speed_guards_zero_duration() -> void:
	assert_eq(StaggerRulesScript.decayed_speed(0, 0, 4.0), 0.0, "a degenerate zero duration must not divide by zero")


func test_decayed_speed_guards_negative_duration() -> void:
	assert_eq(StaggerRulesScript.decayed_speed(0, -50, 4.0), 0.0)


# --- MovementComponent stagger-knockback seam --------------------------------

var _movement: Node


func after_each() -> void:
	if is_instance_valid(_movement):
		_movement.free()
		_movement = null


func test_is_staggered_false_by_default() -> void:
	_movement = MovementComponentScript.new()
	assert_false(_movement.is_staggered(), "a freshly created MovementComponent must not report is_staggered before any stagger has started")


func test_start_stagger_marks_is_staggered_true() -> void:
	_movement = MovementComponentScript.new()
	_movement.start_stagger(Vector3(1, 0, 0), 4.0, 0.3)
	assert_true(_movement.is_staggered())


func test_resolve_stagger_knockback_zero_when_not_staggered() -> void:
	_movement = MovementComponentScript.new()
	var result: Vector3 = _movement.resolve_stagger_knockback(Time.get_ticks_msec())
	assert_eq(result, Vector3.ZERO)


func test_resolve_stagger_knockback_full_speed_at_impact() -> void:
	_movement = MovementComponentScript.new()
	_movement.start_stagger(Vector3(1, 0, 0), 4.0, 0.3)
	# Force a deterministic start clock so this does not depend on real
	# wall-clock timing between start_stagger() and the assertion below.
	_movement._stagger_start_ms = 1000
	var result: Vector3 = _movement.resolve_stagger_knockback(1000)
	assert_eq(result, Vector3(4.0, 0, 0), "at the instant of impact the knockback must be the full stagger_knockback_speed_mps, in the given direction")


func test_resolve_stagger_knockback_decays_over_time() -> void:
	_movement = MovementComponentScript.new()
	_movement.start_stagger(Vector3(1, 0, 0), 4.0, 0.3)
	_movement._stagger_start_ms = 1000
	var halfway: Vector3 = _movement.resolve_stagger_knockback(1150) # 150ms into a 300ms duration
	assert_almost_eq(halfway.length(), 2.0, 0.001, "halfway through the stagger duration, knockback speed must have decayed to half")


func test_resolve_stagger_knockback_expires_and_self_clears() -> void:
	_movement = MovementComponentScript.new()
	_movement.start_stagger(Vector3(1, 0, 0), 4.0, 0.3)
	_movement._stagger_start_ms = 1000

	var expired: Vector3 = _movement.resolve_stagger_knockback(1300)
	assert_eq(expired, Vector3.ZERO, "once the full duration has elapsed, knockback must be zero")
	assert_false(_movement.is_staggered(), "expiry must clear is_staggered (self-clearing, same shape Pounce burst expiry already has)")


func test_start_stagger_normalizes_direction() -> void:
	_movement = MovementComponentScript.new()
	_movement.start_stagger(Vector3(2, 0, 2), 4.0, 0.3)
	_movement._stagger_start_ms = 1000
	var result: Vector3 = _movement.resolve_stagger_knockback(1000)
	assert_almost_eq(result.length(), 4.0, 0.001, "knockback speed must be exactly stagger_knockback_speed_mps regardless of the input direction's original magnitude")


func test_start_stagger_flattens_vertical_component() -> void:
	_movement = MovementComponentScript.new()
	_movement.start_stagger(Vector3(1, 5, 0), 4.0, 0.3)
	_movement._stagger_start_ms = 1000
	var result: Vector3 = _movement.resolve_stagger_knockback(1000)
	assert_eq(result.y, 0.0, "the knockback must never carry a vertical component -- gravity/step_jump own the Y axis")


func test_start_stagger_degenerate_zero_direction_is_safe_but_still_staggered() -> void:
	_movement = MovementComponentScript.new()
	_movement.start_stagger(Vector3.ZERO, 4.0, 0.3)
	assert_true(_movement.is_staggered(), "the time window still starts even with a degenerate zero direction")
	var result: Vector3 = _movement.resolve_stagger_knockback(Time.get_ticks_msec())
	assert_eq(result, Vector3.ZERO)


func test_cancel_stagger_stops_it_immediately() -> void:
	_movement = MovementComponentScript.new()
	_movement.start_stagger(Vector3(1, 0, 0), 4.0, 0.3)
	assert_true(_movement.is_staggered())

	_movement.cancel_stagger()
	assert_false(_movement.is_staggered(), "cancel_stagger must clear is_staggered immediately")
	assert_eq(_movement.resolve_stagger_knockback(Time.get_ticks_msec()), Vector3.ZERO)


# --- resolve_horizontal_velocity: stagger is ADDITIVE, never an override ----
# This is the load-bearing "stagger, not stun" behavior this card exists to
# prove: unlike Pounce's burst (which OVERRIDES wasd_velocity outright, see
# tests/test_pounce_rules.gd), an active stagger must ADD its knockback on
# top of whatever WASD would otherwise produce, so the staggered player keeps
# full movement agency the entire time.

func test_resolve_horizontal_velocity_adds_stagger_on_top_of_wasd() -> void:
	_movement = MovementComponentScript.new()
	_movement.start_stagger(Vector3(1, 0, 0), 4.0, 0.3)
	_movement._stagger_start_ms = 1000

	var wasd: Vector3 = Vector3(0, 0, -5.0) # player still actively walking forward
	var result: Vector3 = _movement.resolve_horizontal_velocity(1000, wasd)
	assert_eq(result, Vector3(4.0, 0, -5.0), "stagger knockback must be ADDED to WASD, not replace it -- the player retains full input agency (no full stun)")


func test_resolve_horizontal_velocity_stagger_alone_with_no_wasd_input() -> void:
	_movement = MovementComponentScript.new()
	_movement.start_stagger(Vector3(1, 0, 0), 4.0, 0.3)
	_movement._stagger_start_ms = 1000

	var result: Vector3 = _movement.resolve_horizontal_velocity(1000, Vector3.ZERO)
	assert_eq(result, Vector3(4.0, 0, 0), "with no WASD input, the result is knockback alone")


func test_resolve_horizontal_velocity_unaffected_when_not_staggered() -> void:
	_movement = MovementComponentScript.new()
	var wasd: Vector3 = Vector3(1.0, 0.0, 2.0)
	var result: Vector3 = _movement.resolve_horizontal_velocity(1000, wasd)
	assert_eq(result, wasd, "with no stagger active, WASD velocity must pass through completely unchanged (regression guard for the Pounce-only tests)")


func test_resolve_horizontal_velocity_combines_pounce_override_and_stagger_add() -> void:
	# An edge case the architecture note flagged: a Tiger mid-Pounce-burst
	# gets kicked and staggered in the same instant. Pounce still overrides
	# the WASD baseline (same as always), and stagger still adds on top of
	# THAT -- the two seams compose without either being silently dropped.
	_movement = MovementComponentScript.new()
	_movement.start_pounce_burst(Vector3(0, 0, -1), 8.0, 0.35)
	_movement._pounce_end_ms = 1000 + int(0.35 * 1000.0) # deterministic, same pattern tests/test_pounce_rules.gd's own expiry test uses
	_movement.start_stagger(Vector3(1, 0, 0), 4.0, 0.3)
	_movement._stagger_start_ms = 1000

	var result: Vector3 = _movement.resolve_horizontal_velocity(1000, Vector3(0, 0, -5.0))
	assert_eq(result, Vector3(4.0, 0, -8.0), "pounce still overrides WASD, and the stagger knockback still adds on top of the pounce result")
