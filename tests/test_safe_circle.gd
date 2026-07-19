extends GutTest
## Unit tests for the TK-P2-06 Safe Circle boundary (gameplay-engineer):
## characters/components/SafeCircleRules.gd (pure boundary math) and
## characters/components/MovementComponent.gd's apply_safe_circle_boundary()
## role gate + its _physics_process() wiring (owner vs non-owner authority
## gate, mirrors tests/test_camera_mode.gd's own Player.tscn
## owner("1")/non-owner("2") pattern).
##
## managers/GameManager.gd's own host-side correction half
## (_physics_process()/correct_tiger_position()) needs a live multiplayer
## SERVER context (multiplayer.is_server()) and is NOT covered here -- same
## "host_validate()/host_apply() need a live scene tree + multiplayer
## context, covered by the manual 2-instance pipeline proof, not GUT" scope
## line tests/test_tag_sequence.gd's own class doc already draws for the
## equivalent GameManager host-only methods.

const SafeCircleRulesScript := preload("res://characters/components/SafeCircleRules.gd")
const MovementComponentScript := preload("res://characters/components/MovementComponent.gd")
const GameManagerScript := preload("res://managers/GameManager.gd")
const PlayerScene := preload("res://characters/Player.tscn")

const ROLE_TIGER: StringName = &"tiger"
const ROLE_OUTER: StringName = &"outer"


## TK-P2-33: reset the shared-process root MultiplayerAPI to a pristine default
## before this file's Player.tscn + GameManager scene-tree tests, so
## is_multiplayer_authority() behaves as "offline" regardless of what an
## earlier-run test file left behind (this file previously relied on an
## alphabetically-earlier file's reset; making it explicit keeps it order-
## independent). See tests/test_role_state_machine.gd's own before_all() for the
## full writeup.
func before_all() -> void:
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), NodePath(""))


# --- SafeCircleRules.horizontal_distance (pure) -----------------------------

func test_horizontal_distance_ignores_y() -> void:
	var dist: float = SafeCircleRulesScript.horizontal_distance(Vector3(3.0, 99.0, 4.0))
	assert_almost_eq(dist, 5.0, 0.0001, "3-4-5 triangle on the XZ plane -- Y must never factor in")


func test_horizontal_distance_respects_custom_center() -> void:
	var dist: float = SafeCircleRulesScript.horizontal_distance(Vector3(13.0, 0.0, 4.0), Vector3(10.0, 0.0, 0.0))
	assert_almost_eq(dist, 5.0, 0.0001)


# --- SafeCircleRules.is_inside (pure) ---------------------------------------

func test_is_inside_true_at_center() -> void:
	assert_true(SafeCircleRulesScript.is_inside(Vector3.ZERO, 5.0))


func test_is_inside_true_well_inside() -> void:
	assert_true(SafeCircleRulesScript.is_inside(Vector3(2.0, 0.0, 2.0), 5.0))


func test_is_inside_true_exactly_on_boundary() -> void:
	assert_true(SafeCircleRulesScript.is_inside(Vector3(5.0, 0.0, 0.0), 5.0),
		"exactly at the wall must still count as inside (<=, not <)")


func test_is_inside_false_just_outside() -> void:
	assert_false(SafeCircleRulesScript.is_inside(Vector3(5.001, 0.0, 0.0), 5.0))


func test_is_inside_false_well_outside() -> void:
	assert_false(SafeCircleRulesScript.is_inside(Vector3(50.0, 0.0, 0.0), 5.0))


func test_is_inside_ignores_height() -> void:
	assert_true(SafeCircleRulesScript.is_inside(Vector3(1.0, 500.0, 1.0), 5.0),
		"the wall must behave as infinite height -- jumping must not let a Tiger escape sooner")


# --- SafeCircleRules.clamp_to_circle (pure) ---------------------------------

func test_clamp_returns_unchanged_position_when_already_inside() -> void:
	var pos: Vector3 = Vector3(1.0, 3.0, 1.0)
	var result: Vector3 = SafeCircleRulesScript.clamp_to_circle(pos, 5.0)
	assert_eq(result, pos)


func test_clamp_returns_unchanged_position_exactly_on_boundary() -> void:
	var pos: Vector3 = Vector3(5.0, 2.0, 0.0)
	var result: Vector3 = SafeCircleRulesScript.clamp_to_circle(pos, 5.0)
	assert_eq(result, pos, "exactly at radius must be a no-op, matching is_inside()'s own <=")


func test_clamp_projects_straight_out_position_back_onto_the_boundary() -> void:
	var result: Vector3 = SafeCircleRulesScript.clamp_to_circle(Vector3(10.0, 0.0, 0.0), 5.0)
	assert_almost_eq(result.x, 5.0, 0.0001)
	assert_almost_eq(result.z, 0.0, 0.0001)


func test_clamp_preserves_y_untouched() -> void:
	var result: Vector3 = SafeCircleRulesScript.clamp_to_circle(Vector3(10.0, 7.5, 0.0), 5.0)
	assert_almost_eq(result.y, 7.5, 0.0001, "the boundary is horizontal-only -- Y must never be touched")


func test_clamp_preserves_direction_for_a_diagonal_overshoot() -> void:
	var overshoot: Vector3 = Vector3(8.0, 0.0, 6.0) # distance 10, direction (0.8, 0.6)
	var result: Vector3 = SafeCircleRulesScript.clamp_to_circle(overshoot, 5.0)
	assert_almost_eq(result.x, 4.0, 0.0001) # 0.8 * 5.0
	assert_almost_eq(result.z, 3.0, 0.0001) # 0.6 * 5.0


func test_clamp_result_is_exactly_radius_from_center() -> void:
	var result: Vector3 = SafeCircleRulesScript.clamp_to_circle(Vector3(123.0, 0.0, -45.0), 5.0)
	var dist: float = Vector2(result.x, result.z).length()
	assert_almost_eq(dist, 5.0, 0.0001)


func test_clamp_respects_custom_center() -> void:
	var result: Vector3 = SafeCircleRulesScript.clamp_to_circle(Vector3(20.0, 0.0, 0.0), 5.0, Vector3(10.0, 0.0, 0.0))
	assert_almost_eq(result.x, 15.0, 0.0001,
		"clamped point must sit radius=5 out from the custom center (10,_,0), along +X")
	assert_almost_eq(result.z, 0.0, 0.0001)


func test_clamp_degenerate_zero_radius_returns_center() -> void:
	var result: Vector3 = SafeCircleRulesScript.clamp_to_circle(Vector3(3.0, 1.0, 0.0), 0.0)
	assert_almost_eq(result.x, 0.0, 0.0001)
	assert_almost_eq(result.y, 1.0, 0.0001, "Y still preserved even in the degenerate fallback")
	assert_almost_eq(result.z, 0.0, 0.0001)


func test_clamp_degenerate_negative_radius_returns_center() -> void:
	var result: Vector3 = SafeCircleRulesScript.clamp_to_circle(Vector3(3.0, 0.0, 4.0), -1.0)
	assert_almost_eq(result.x, 0.0, 0.0001)
	assert_almost_eq(result.z, 0.0, 0.0001)


# --- MovementComponent.apply_safe_circle_boundary() (bare instance) --------
# Same "bare `.new()`, never added to a tree" testability shape
# tests/test_jump_rules.gd's own step_jump() section already documents --
# apply_safe_circle_boundary() takes exactly the values _physics_process()
# would have read (role, position) and never touches `_body`.

var _movement: Node
var _player: CharacterBody3D


func after_each() -> void:
	if is_instance_valid(_movement):
		_movement.free()
		_movement = null


func test_safe_circle_radius_default_tunable() -> void:
	_movement = MovementComponentScript.new()
	assert_eq(_movement.safe_circle_radius, 5.0,
		"safe_circle_radius must be an @export tunable defaulting to the locked Game_Balance.md value, not hard-coded")


func test_apply_safe_circle_boundary_outer_role_never_clamped() -> void:
	_movement = MovementComponentScript.new()
	var far_outside: Vector3 = Vector3(999.0, 0.0, 0.0)
	var result: Vector3 = _movement.apply_safe_circle_boundary(ROLE_OUTER, far_outside)
	assert_eq(result, far_outside, "an Outer must always be returned unchanged -- design ruling point 2, free to roam")


func test_apply_safe_circle_boundary_tiger_role_inside_unchanged() -> void:
	_movement = MovementComponentScript.new()
	var inside: Vector3 = Vector3(1.0, 0.0, 1.0)
	var result: Vector3 = _movement.apply_safe_circle_boundary(ROLE_TIGER, inside)
	assert_eq(result, inside)


func test_apply_safe_circle_boundary_tiger_role_outside_gets_clamped() -> void:
	_movement = MovementComponentScript.new()
	var result: Vector3 = _movement.apply_safe_circle_boundary(ROLE_TIGER, Vector3(50.0, 0.0, 0.0))
	assert_almost_eq(result.x, 5.0, 0.0001, "must clamp to the default safe_circle_radius (5.0)")


func test_apply_safe_circle_boundary_uses_the_configured_radius_not_a_hardcoded_one() -> void:
	_movement = MovementComponentScript.new()
	_movement.safe_circle_radius = 2.0
	var result: Vector3 = _movement.apply_safe_circle_boundary(ROLE_TIGER, Vector3(50.0, 0.0, 0.0))
	assert_almost_eq(result.x, 2.0, 0.0001,
		"a retuned safe_circle_radius must actually change the clamp, not fall back to a hardcoded 5.0")


func test_apply_safe_circle_boundary_unrecognized_role_treated_as_outer() -> void:
	# Fail-safe consistency with MovementComponent.set_role()'s own
	# unrecognized-role default (Outer profile, not Tiger) -- an unrecognized
	# role must never accidentally gain the MORE restrictive Tiger
	# confinement either.
	_movement = MovementComponentScript.new()
	var far_outside: Vector3 = Vector3(999.0, 0.0, 0.0)
	var result: Vector3 = _movement.apply_safe_circle_boundary(&"not_a_real_role", far_outside)
	assert_eq(result, far_outside)


# --- MovementComponent._physics_process() wiring -- owner vs non-owner -----
# Mirrors tests/test_camera_mode.gd's own Player.tscn owner("1")/non-owner("2")
# pattern: headless GUT's SceneMultiplayer own id == 1 (no live ENet peer),
# so naming a Player "1" makes it THIS test's own/owned Player
# (is_multiplayer_authority() == true, the case the boundary clamp must
# apply to); naming it "2" simulates a remote peer's copy (authority 2 != own
# id 1), which must run ZERO local physics at all (TK-P1-06 invariant) --
# including this new boundary clamp. Calling _physics_process() directly
# (rather than waiting real engine frames) drives the exact same code path
# deterministically -- no live input is pressed in headless GUT, so
# horizontal velocity from input is always zero and only the manually-set
# starting `position` + the boundary clamp determine the result.

func test_owned_tiger_player_physics_tick_clamps_position_to_the_boundary() -> void:
	_player = PlayerScene.instantiate()
	_player.name = "1" # headless GUT's own multiplayer id == 1 -> owner
	add_child_autofree(_player)
	_player.set_role(ROLE_TIGER)
	_player.position = Vector3(999.0, 0.0, 0.0)

	var movement_component: Node = _player.get_node("MovementComponent")
	movement_component._physics_process(1.0 / 60.0)

	assert_almost_eq(_player.position.x, movement_component.safe_circle_radius, 0.01,
		"an owned Tiger's own physics tick must clamp its position back inside the boundary")


func test_owned_outer_player_physics_tick_never_clamped() -> void:
	_player = PlayerScene.instantiate()
	_player.name = "1"
	add_child_autofree(_player)
	# default role is Outer -- do not call set_role()
	_player.position = Vector3(999.0, 0.0, 0.0)

	var movement_component: Node = _player.get_node("MovementComponent")
	movement_component._physics_process(1.0 / 60.0)

	assert_almost_eq(_player.position.x, 999.0, 0.01,
		"an Outer must never be clamped by the Safe Circle, regardless of distance from center")


func test_non_owned_tiger_player_physics_tick_is_a_complete_no_op() -> void:
	_player = PlayerScene.instantiate()
	_player.name = "2" # non-owner (headless own id == 1)
	add_child_autofree(_player)
	_player.set_role(ROLE_TIGER)
	_player.position = Vector3(999.0, 0.0, 0.0)

	var movement_component: Node = _player.get_node("MovementComponent")
	movement_component._physics_process(1.0 / 60.0)

	assert_almost_eq(_player.position.x, 999.0, 0.01,
		"a non-owned Player must run ZERO local physics (TK-P1-06 invariant) -- the boundary clamp must not run on a peer's copy of a Player it does not own")


# --- GameManager.SAFE_CIRCLE_CORRECTION_TOLERANCE_M (code-review + ----------
# network-engineer fix, post-handoff): regression coverage for the finding
# that the HOST-SIDE correction check must use a real tolerance margin on top
# of safe_circle_radius, or an honest Tiger resting exactly at the wall
# (the owner's own clamp pins `position` to EXACTLY the radius, the single
# most common resting state this boundary creates) misreads as "outside" on
# ~half of every tick after float replication round-trip, firing a reliable
# correction RPC against an already-compliant client every tick, not a rare
# edge case. This section exercises the pure SafeCircleRules math
# GameManager._physics_process() actually calls (is_inside(pos,
# safe_circle_radius + tolerance)), NOT GameManager itself -- GameManager's
# host-only wiring needs a live multiplayer.is_server() context and stays out
# of GUT's scope here, same line tests/test_tag_sequence.gd's own class doc
# draws for the equivalent GameManager host-only methods.

func test_safe_circle_correction_tolerance_is_a_small_positive_margin() -> void:
	assert_true(GameManagerScript.SAFE_CIRCLE_CORRECTION_TOLERANCE_M > 0.0,
		"the host-side check must have real slack, not an exact <=, or it misfires against an honest Tiger resting at the wall")
	assert_true(GameManagerScript.SAFE_CIRCLE_CORRECTION_TOLERANCE_M < 1.0,
		"the tolerance must stay small enough that a REAL breach (a client that skipped its own clamp) is still caught well before it becomes visually meaningful")


func test_is_inside_with_tolerance_absorbs_float_replication_noise_at_the_wall() -> void:
	var radius: float = 5.0
	var tolerance: float = GameManagerScript.SAFE_CIRCLE_CORRECTION_TOLERANCE_M
	# A few ULP past the true radius -- exactly the float32 replication noise
	# an honest, wall-pinned Tiger's position produces after round-tripping
	# through MultiplayerSynchronizer, per the review finding.
	var noisy_position: Vector3 = Vector3(radius + 0.0001, 0.0, 0.0)
	assert_false(SafeCircleRulesScript.is_inside(noisy_position, radius),
		"sanity: an exact (no-tolerance) check DOES read this as outside -- this is the bug the tolerance fixes")
	assert_true(SafeCircleRulesScript.is_inside(noisy_position, radius + tolerance),
		"WITH the host's tolerance margin, the same noisy-but-honest position must read as inside")


func test_is_inside_with_tolerance_still_catches_a_real_breach() -> void:
	var radius: float = 5.0
	var tolerance: float = GameManagerScript.SAFE_CIRCLE_CORRECTION_TOLERANCE_M
	# A client that actually skipped its own local clamp lands many
	# centimeters+ outside, not a few ULP -- must still be caught.
	var real_breach_position: Vector3 = Vector3(radius + 0.5, 0.0, 0.0)
	assert_false(SafeCircleRulesScript.is_inside(real_breach_position, radius + tolerance),
		"a real breach (0.5m past the wall) must still read as outside even with the tolerance margin")


func test_correction_target_still_snaps_to_the_true_radius_not_the_tolerance_widened_one() -> void:
	# clamp_to_circle() must always target the TRUE radius -- the tolerance
	# only widens the "should I bother correcting" check above, never where a
	# correction actually lands.
	var radius: float = 5.0
	var result: Vector3 = SafeCircleRulesScript.clamp_to_circle(Vector3(radius + 0.5, 0.0, 0.0), radius)
	assert_almost_eq(result.x, radius, 0.0001)


# --- GameManager._apply_tiger_position_correction node resolution (TK-P2-33) --
# POSITIVE-SIDE-EFFECT regression coverage, same bug CLASS as TK-P2-32 /
# TK-BUG-P2-01 (glue that resolves "which live node does this RPC broadcast's
# result apply to" being silently wrong under green pure-function tests). The
# section above covers the PURE tolerance/boundary math GameManager's host-side
# correction calls; this section covers the separate scene-tree step
# _apply_tiger_position_correction() performs -- resolving Players/<peer_id> off
# the "Players" root and writing the corrected position ONLY if this peer owns
# that node (is_multiplayer_authority() gate) -- the exact same "resolve a
# peer-id to a live node under a broadcast, act only on the correct owned node"
# shape as both prior bugs, previously unasserted at the observable-effect
# level. Real Player.tscn instances (no mocks).
#
# SETUP is decoupled from GameManager._ready() -- _apply_tiger_position_
# correction() depends ONLY on GameManager's `_players_root`, so the real
# Player.tscn Tigers are spawned under an in-tree "Players" root (so each
# Player's own authority resolves) and that root is injected into a GameManager
# NOT added to the tree, so its host-only _ready() / _physics_process()
# (CountdownManager wiring, match-end watch, the Safe-Circle host correction
# loop) never run and cannot fire a competing correction mid-test. See
# tests/test_tag_sequence.gd's own "apply_role_switch" SETUP note for the full
# rationale (this is the same helper shape).

func _build_players_root() -> Node:
	var root := Node3D.new()
	add_child_autofree(root)
	var players := Node3D.new()
	players.name = "Players"
	root.add_child(players)
	return players


func _make_game_manager(players: Node) -> Node:
	var gm: Node = GameManagerScript.new()
	autofree(gm)
	gm._players_root = players
	return gm


func _spawn_correction_player(players: Node, peer_name: String, pos: Vector3) -> CharacterBody3D:
	var p: CharacterBody3D = PlayerScene.instantiate()
	p.name = peer_name
	players.add_child(p)
	p.set_role(ROLE_TIGER)
	p.position = pos
	return p


func test_apply_tiger_position_correction_writes_only_to_the_owned_resolved_node() -> void:
	var players: Node = _build_players_root()
	var gm: Node = _make_game_manager(players)

	# Owned Tiger (name "1" == headless GUT own id).
	var owned: CharacterBody3D = _spawn_correction_player(players, "1", Vector3(5.0, 0.0, 0.0))

	gm._apply_tiger_position_correction(1, Vector3(4.0, 0.0, 0.0))

	assert_almost_eq(owned.position.x, 4.0, 0.001,
		"the correction must resolve Players/1 and land on THAT owned node's position -- the observable effect must hit the correct node")


func test_apply_tiger_position_correction_is_a_no_op_on_a_non_owned_node() -> void:
	var players: Node = _build_players_root()
	var gm: Node = _make_game_manager(players)

	# Named "2" -- NOT this peer's id, so is_multiplayer_authority() is false:
	# position is owner-authoritative one-way sync, so this peer must never write
	# a Player it does not own (even though the node resolves fine).
	var remote: CharacterBody3D = _spawn_correction_player(players, "2", Vector3(4.0, 0.0, 0.0))

	gm._apply_tiger_position_correction(2, Vector3(0.0, 0.0, 0.0))

	assert_almost_eq(remote.position.x, 4.0, 0.001,
		"a Player this peer does not own must be left untouched by the correction (authority gate on the resolved node)")
