extends GutTest
## Unit tests for characters/Player.gd -- pure, node-independent movement
## math only (TK-P1-02: walk/sprint speed, gravity integration).
##
## WHY THIS EXISTS (testability): CharacterBody3D.move_and_slide() needs a
## live scene tree/physics world, and Input.get_vector() needs real input
## state, so the real _physics_process() can't run under GUT headless.
## The speed/sprint/gravity DECISIONS are extracted as static, dependency-
## injected functions (compute_velocity, apply_gravity) so they can be
## tested with plain values -- no node, no Input, no physics tick required.
##
## NOTE: Requires the GUT addon (TK-PX-07), same as tests/test_tiger_assignment.gd.

const PlayerScript := preload("res://characters/Player.gd")

const WALK_SPEED: float = 5.0       # TDD §11 Player Speed baseline
const SPRINT_MULTIPLIER: float = 1.4  # TDD §11 Sprint Multiplier


# --- compute_velocity: walking ------------------------------------------------

func test_walk_forward_uses_walk_speed() -> void:
	# Input.get_vector's forward axis is negative-y (move_forward is the
	# "negative y" arg), matching Godot's -Z forward.
	var input_dir: Vector2 = Vector2(0.0, -1.0)
	var result: Vector3 = PlayerScript.compute_velocity(
		input_dir, WALK_SPEED, SPRINT_MULTIPLIER, false
	)
	assert_eq(result, Vector3(0.0, 0.0, -WALK_SPEED),
		"walking forward at walk_speed must not apply the sprint multiplier")


func test_walk_right_uses_walk_speed_on_x() -> void:
	var input_dir: Vector2 = Vector2(1.0, 0.0)
	var result: Vector3 = PlayerScript.compute_velocity(
		input_dir, WALK_SPEED, SPRINT_MULTIPLIER, false
	)
	assert_eq(result, Vector3(WALK_SPEED, 0.0, 0.0))


func test_no_input_gives_zero_velocity() -> void:
	var result: Vector3 = PlayerScript.compute_velocity(
		Vector2.ZERO, WALK_SPEED, SPRINT_MULTIPLIER, false
	)
	assert_eq(result, Vector3.ZERO)


func test_velocity_y_is_always_zero_horizontal_only() -> void:
	# vertical motion is gravity's job (apply_gravity), never compute_velocity's
	var result: Vector3 = PlayerScript.compute_velocity(
		Vector2(1.0, 1.0), WALK_SPEED, SPRINT_MULTIPLIER, true
	)
	assert_eq(result.y, 0.0)


# --- compute_velocity: sprint --------------------------------------------------

func test_sprint_forward_applies_multiplier() -> void:
	var input_dir: Vector2 = Vector2(0.0, -1.0)
	var result: Vector3 = PlayerScript.compute_velocity(
		input_dir, WALK_SPEED, SPRINT_MULTIPLIER, true
	)
	assert_eq(result, Vector3(0.0, 0.0, -WALK_SPEED * SPRINT_MULTIPLIER),
		"sprinting must multiply walk_speed by sprint_multiplier")


func test_sprint_is_strictly_faster_than_walk() -> void:
	var input_dir: Vector2 = Vector2(0.0, -1.0)
	var walk: Vector3 = PlayerScript.compute_velocity(
		input_dir, WALK_SPEED, SPRINT_MULTIPLIER, false
	)
	var sprint: Vector3 = PlayerScript.compute_velocity(
		input_dir, WALK_SPEED, SPRINT_MULTIPLIER, true
	)
	assert_true(sprint.length() > walk.length(),
		"sprint speed must exceed walk speed given the same input")


func test_sprint_with_no_input_still_zero() -> void:
	var result: Vector3 = PlayerScript.compute_velocity(
		Vector2.ZERO, WALK_SPEED, SPRINT_MULTIPLIER, true
	)
	assert_eq(result, Vector3.ZERO,
		"holding sprint with no directional input must not move the player")


func test_diagonal_input_scales_both_axes() -> void:
	var input_dir: Vector2 = Vector2(0.5, -0.5)
	var result: Vector3 = PlayerScript.compute_velocity(
		input_dir, WALK_SPEED, SPRINT_MULTIPLIER, false
	)
	assert_eq(result, Vector3(0.5 * WALK_SPEED, 0.0, -0.5 * WALK_SPEED))


# --- apply_gravity --------------------------------------------------------------

func test_gravity_accumulates_while_airborne() -> void:
	var gravity: float = 9.8
	var delta: float = 1.0 / 60.0
	var result: float = PlayerScript.apply_gravity(0.0, gravity, delta, false)
	assert_almost_eq(result, -gravity * delta, 0.0001,
		"one physics tick airborne must subtract gravity*delta from y velocity")


func test_gravity_accumulates_over_multiple_ticks() -> void:
	var gravity: float = 9.8
	var delta: float = 1.0 / 60.0
	var velocity_y: float = 0.0
	for _i in range(10):
		velocity_y = PlayerScript.apply_gravity(velocity_y, gravity, delta, false)
	assert_almost_eq(velocity_y, -gravity * delta * 10, 0.0001)


func test_grounded_clamps_negative_velocity_to_zero() -> void:
	var result: float = PlayerScript.apply_gravity(-5.0, 9.8, 1.0 / 60.0, true)
	assert_eq(result, 0.0,
		"landing (grounded + falling) must clamp vertical velocity to 0, not stack")


func test_grounded_does_not_clamp_upward_velocity() -> void:
	# e.g. a jump impulse applied the same frame is_on_floor() is still true
	# from the previous tick -- must not be zeroed out.
	var result: float = PlayerScript.apply_gravity(8.0, 9.8, 1.0 / 60.0, true)
	assert_almost_eq(result, 8.0 - 9.8 * (1.0 / 60.0), 0.0001)


func test_grounded_with_zero_velocity_still_applies_gravity() -> void:
	# resting exactly at 0 (not yet negative) still gets pulled down this tick;
	# is_on_floor() will clamp it again next tick once it goes negative.
	var gravity: float = 9.8
	var delta: float = 1.0 / 60.0
	var result: float = PlayerScript.apply_gravity(0.0, gravity, delta, true)
	assert_almost_eq(result, -gravity * delta, 0.0001)
