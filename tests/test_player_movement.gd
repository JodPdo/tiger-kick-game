extends GutTest
## Unit tests for characters/components/MovementComponent.gd -- pure,
## node-independent movement math only (TK-P1-02: walk/sprint speed, gravity
## integration; TK-P1-03: camera-relative yaw rotation).
##
## TK-P2-16 Step 1 (gameplay-engineer): these pure statics used to live on
## characters/Player.gd; they moved to MovementComponent.gd verbatim
## (behavior-preserving code move only) as part of the Ability System
## scaffold. Only the preload target below changed -- every assertion/
## expected value is IDENTICAL to before.
##
## WHY THIS EXISTS (testability): CharacterBody3D.move_and_slide() needs a
## live scene tree/physics world, and Input.get_vector() needs real input
## state, so the real _physics_process() can't run under GUT headless.
## The speed/sprint/gravity/rotation DECISIONS are extracted as static,
## dependency-injected functions (compute_velocity, apply_gravity,
## camera_relative_dir) so they can be tested with plain values -- no node,
## no Input, no physics tick, no SpringArm3D/CameraRig scene tree required.
##
## NOTE: Requires the GUT addon (TK-PX-07), same as tests/test_tiger_assignment.gd.

const PlayerScript := preload("res://characters/components/MovementComponent.gd")

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


# --- camera_relative_dir (TK-P1-03) --------------------------------------------
# Expected values below are computed independently via the standard
# right-hand-rule rotation-around-Y matrix (x' = x*cos(yaw) + z*sin(yaw),
# z' = -x*sin(yaw) + z*cos(yaw)) rather than by calling the function under
# test, so these assertions actually exercise Vector3.rotated()'s behavior
# and camera_relative_dir()'s axis/sign choices, not just restate them.

func test_camera_relative_dir_zero_yaw_is_identity() -> void:
	var input_dir: Vector2 = Vector2(0.0, -1.0) # forward
	var result: Vector3 = PlayerScript.camera_relative_dir(input_dir, 0.0)
	assert_eq(result, Vector3(0.0, 0.0, -1.0),
		"zero yaw must not rotate the input direction")


func test_camera_relative_dir_no_input_gives_zero_vector_at_any_yaw() -> void:
	var result: Vector3 = PlayerScript.camera_relative_dir(Vector2.ZERO, PI / 2.0)
	assert_eq(result, Vector3.ZERO)


func test_camera_relative_dir_y_is_always_zero() -> void:
	var result: Vector3 = PlayerScript.camera_relative_dir(Vector2(1.0, 1.0), 1.234)
	assert_eq(result.y, 0.0)


func test_camera_relative_dir_quarter_turn_forward() -> void:
	var yaw: float = PI / 2.0
	var input_dir: Vector2 = Vector2(0.0, -1.0) # forward
	var expected: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
	var result: Vector3 = PlayerScript.camera_relative_dir(input_dir, yaw)
	assert_almost_eq(result.x, expected.x, 0.0001)
	assert_almost_eq(result.z, expected.z, 0.0001)


func test_camera_relative_dir_half_turn_forward_becomes_backward() -> void:
	var yaw: float = PI
	var input_dir: Vector2 = Vector2(0.0, -1.0) # forward
	var result: Vector3 = PlayerScript.camera_relative_dir(input_dir, yaw)
	assert_almost_eq(result.x, 0.0, 0.0001)
	assert_almost_eq(result.z, 1.0, 0.0001,
		"a 180 degree yaw must flip 'forward' input into world +Z")


func test_camera_relative_dir_arbitrary_yaw_matches_rotation_matrix() -> void:
	var yaw: float = -0.7
	var input_dir: Vector2 = Vector2(0.6, -0.8)
	var expected: Vector3 = Vector3(
		input_dir.x * cos(yaw) + input_dir.y * sin(yaw),
		0.0,
		-input_dir.x * sin(yaw) + input_dir.y * cos(yaw)
	)
	var result: Vector3 = PlayerScript.camera_relative_dir(input_dir, yaw)
	assert_almost_eq(result.x, expected.x, 0.0001)
	assert_almost_eq(result.z, expected.z, 0.0001)


func test_camera_relative_dir_preserves_input_magnitude() -> void:
	var input_dir: Vector2 = Vector2(0.5, -0.5)
	var result: Vector3 = PlayerScript.camera_relative_dir(input_dir, 2.1)
	assert_almost_eq(result.length(), input_dir.length(), 0.0001,
		"rotation must not change the magnitude of the input direction")


# --- compute_velocity fed a pre-rotated (camera-relative) direction -----------

func test_compute_velocity_after_camera_relative_rotation_quarter_turn() -> void:
	# Regression for the _physics_process wiring: forward input (0,-1),
	# rotated 90 degrees of yaw, then scaled by walk_speed, must match doing
	# the rotation and scaling in either order.
	var yaw: float = PI / 2.0
	var input_dir: Vector2 = Vector2(0.0, -1.0)
	var rotated: Vector3 = PlayerScript.camera_relative_dir(input_dir, yaw)
	var result: Vector3 = PlayerScript.compute_velocity(
		Vector2(rotated.x, rotated.z), WALK_SPEED, SPRINT_MULTIPLIER, false
	)
	assert_almost_eq(result.x, -sin(yaw) * WALK_SPEED, 0.0001)
	assert_almost_eq(result.z, -cos(yaw) * WALK_SPEED, 0.0001)
	assert_eq(result.y, 0.0)


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
