extends GutTest
## Unit tests for characters/components/JumpRules.gd (TK-P2-10) and the
## node-independent parts of characters/components/MovementComponent.gd's
## jump wiring (`_is_jumping` / `is_jumping()` / `step_jump()`).
##
## Only node-independent logic is covered here (design doc §3 testability
## note, same pattern as tests/test_kick_rules.gd): JumpRules is a pure
## static helper -- no scene tree, no Input, no live physics tick required.
## MovementComponent.step_jump() (below) mutates instance state
## (`_is_jumping`) but needs no CharacterBody3D/scene tree/Input either --
## it takes exactly the values _physics_process() would have read, so a
## bare `MovementComponent.new()` (never added to a tree, @onready `_body`/
## `_camera_rig` left unresolved) is safe to exercise directly, same as
## tests/test_kick_rules.gd's bare KickAbility instances.
##
## CODE-REVIEW FIX (S2, this file's own regression coverage): the review on
## this card caught that clearing `_is_jumping` on `is_grounded` ALONE (no
## velocity-direction check) made `JumpRules.can_jump()`'s own is_jumping
## guard dead code once wired into _physics_process -- a stale
## is_on_floor()-true tick while still RISING would silently clear the flag
## and permit a mid-air re-jump, even though can_jump() itself (tested below)
## stayed green throughout. This is the Phase-1 lesson verbatim (see
## CURRENT_PHASE.md's [0.28] audit note: pure-function-only tests can miss
## glue bugs) -- the "MovementComponent step_jump() wiring" section below
## exercises the ACTUAL ordering/gating decision, not just the pure
## can_jump()/jump_velocity() statics it wraps.

const JumpRulesScript := preload("res://characters/components/JumpRules.gd")
const MovementComponentScript := preload("res://characters/components/MovementComponent.gd")


# --- JumpRules.can_jump (pure) ----------------------------------------------

func test_can_jump_true_when_grounded_and_not_jumping() -> void:
	assert_true(JumpRulesScript.can_jump(true, false))


func test_can_jump_false_when_not_on_floor() -> void:
	assert_false(JumpRulesScript.can_jump(false, false),
		"mid-air (not on floor) must never allow a jump, regardless of the is_jumping flag")


func test_can_jump_false_when_already_jumping_even_if_on_floor() -> void:
	# Defense-in-depth case per the class doc: is_on_floor() can lag a frame
	# right after leaving the ground -- the tracked _is_jumping flag must
	# still block a second jump even if is_on_floor() briefly reports true.
	assert_false(JumpRulesScript.can_jump(true, true))


func test_can_jump_false_when_neither_grounded_nor_flagged_jumping_is_consistent() -> void:
	# Both signals must agree for a jump to be allowed -- this is the
	# "no double-jump mid-air" DoD guard exercised directly.
	assert_false(JumpRulesScript.can_jump(false, true))


# --- JumpRules.jump_velocity (pure) -----------------------------------------

func test_jump_velocity_returns_the_configured_jump_speed() -> void:
	assert_eq(JumpRulesScript.jump_velocity(5.0), 5.0)


func test_jump_velocity_is_positive_for_a_positive_jump_speed() -> void:
	assert_true(JumpRulesScript.jump_velocity(7.5) > 0.0,
		"a jump impulse must be upward (+Y), never downward/zero, for any positive jump_speed")


# --- MovementComponent jump tunable + is_jumping() getter -------------------

var _movement: Node


func after_each() -> void:
	if is_instance_valid(_movement):
		_movement.free()
		_movement = null


func test_jump_speed_default_tunable() -> void:
	_movement = MovementComponentScript.new()
	assert_eq(_movement.jump_speed, 5.0, "jump_speed must be an @export tunable, not hard-coded")


func test_is_jumping_false_by_default() -> void:
	_movement = MovementComponentScript.new()
	assert_false(_movement.is_jumping(),
		"a freshly created MovementComponent must not report is_jumping before any jump has fired")


# --- MovementComponent.step_jump() wiring (S2 regression coverage) ---------
# step_jump() IS the real _physics_process ordering (landing-clear then
# jump-trigger), extracted so it is reachable without a live physics tick --
# see MovementComponent.gd's own doc on step_jump() for the full ordering
# rationale this section pins down.

func test_step_jump_fires_when_grounded_and_not_already_jumping() -> void:
	_movement = MovementComponentScript.new()
	_movement.jump_speed = 5.0
	var result: float = _movement.step_jump(true, 0.0, true)
	assert_eq(result, 5.0, "a grounded jump input must set velocity.y to jump_speed")
	assert_true(_movement.is_jumping(), "step_jump must set is_jumping true the instant a jump fires")


func test_step_jump_does_not_fire_without_jump_input() -> void:
	_movement = MovementComponentScript.new()
	var result: float = _movement.step_jump(true, 0.0, false)
	assert_eq(result, 0.0, "no jump input must leave velocity.y untouched")
	assert_false(_movement.is_jumping())


func test_step_jump_ignores_jump_input_while_mid_air() -> void:
	_movement = MovementComponentScript.new()
	var result: float = _movement.step_jump(false, -2.0, true)
	assert_eq(result, -2.0, "a jump press while not grounded must not alter vertical velocity")
	assert_false(_movement.is_jumping())


func test_step_jump_no_double_jump_mid_air_even_with_stale_grounded_true() -> void:
	# CODE-REVIEW REGRESSION (S2): this is the exact bug the review caught.
	# Simulate the tick right after a jump fires: is_grounded reads TRUE
	# (Godot's own is_on_floor() lag while still rising -- see the class
	# doc), but velocity.y is still clearly positive (rising, not landing).
	# A second jump press on this same stale-grounded tick must NOT be
	# allowed to re-fire -- if the landing-clear ordering regresses back to
	# gating on is_grounded alone, this assertion catches it (this exact
	# scenario is the one manual flat-ground testing cannot repro).
	_movement = MovementComponentScript.new()
	_movement.jump_speed = 5.0

	# Tick 1: real jump, grounded, no input residue.
	var v1: float = _movement.step_jump(true, 0.0, true)
	assert_eq(v1, 5.0)
	assert_true(_movement.is_jumping())

	# Tick 2: still rising (velocity.y > 0), but is_on_floor() stale-true --
	# a second jump press here must be rejected, and is_jumping must remain
	# true (NOT cleared by the stale grounded reading).
	var v2: float = _movement.step_jump(true, 3.0, true)
	assert_eq(v2, 3.0, "a stale grounded=true while still rising must not grant a second jump impulse")
	assert_true(_movement.is_jumping(),
		"is_jumping must NOT be cleared by a stale is_grounded=true tick while velocity.y is still positive (rising)")


func test_step_jump_real_landing_clears_the_flag_same_tick() -> void:
	_movement = MovementComponentScript.new()
	_movement.jump_speed = 5.0
	_movement.step_jump(true, 0.0, true)
	assert_true(_movement.is_jumping(), "sanity: jumping after the first tick")

	# A real landing: grounded AND velocity.y has gone <= 0 (falling/at rest).
	var v: float = _movement.step_jump(true, -1.0, false)
	assert_eq(v, -1.0)
	assert_false(_movement.is_jumping(), "a real landing (grounded + non-upward velocity) must clear is_jumping")


func test_step_jump_same_tick_land_then_jump_still_works() -> void:
	_movement = MovementComponentScript.new()
	_movement.jump_speed = 5.0
	_movement.step_jump(true, 0.0, true)
	assert_true(_movement.is_jumping())

	# Same tick: landing (velocity.y <= 0, grounded) AND a fresh jump press --
	# the landing-clear must run BEFORE the jump-trigger check so this still
	# fires (no missed-input frame on a same-tick land-then-jump).
	var v: float = _movement.step_jump(true, -1.0, true)
	assert_eq(v, 5.0, "landing and pressing jump on the very same tick must still launch the body")
	assert_true(_movement.is_jumping())
