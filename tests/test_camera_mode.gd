extends GutTest
## Unit tests for the TK-P2-05 FP/TP camera swap (gameplay-engineer):
## characters/components/CameraModeRules.gd (pure role -> mode decision) and
## characters/components/CameraComponent.gd's `role_changed` subscription +
## `_apply_camera_mode()` wiring.
##
## Mirrors tests/test_role_state_machine.gd's Player.tscn instantiation
## pattern (PlayerScene.instantiate() + add_child_autofree(), node.name set
## BEFORE entering the tree so Player._enter_tree() derives real authority
## instead of tripping its own non-numeric-name tripwire).
##
## AUTHORITY NOTE (see tests/test_ability_system.gd's own comment, same
## fact): headless GUT's SceneMultiplayer has own id == 1 with no live ENet
## peer. Naming a Player "1" therefore makes it THIS test's own/owned Player
## (is_multiplayer_authority() == true) -- exactly the case CameraComponent's
## `_apply_camera_mode()` is gated on. Naming a Player "2" simulates a
## NON-owned/remote peer's copy (authority 2 != own id 1) -- the case that
## must be a no-op, per design doc §5 step 3 ("จริงเฉพาะเครื่องเจ้าของ") and
## CameraModeRules.gd's own class doc.

const CameraModeRulesScript := preload("res://characters/components/CameraModeRules.gd")
const PlayerScene := preload("res://characters/Player.tscn")

const ROLE_TIGER: StringName = &"tiger"
const ROLE_OUTER: StringName = &"outer"


# --- CameraModeRules.is_first_person (pure static) -------------------------

func test_tiger_role_is_first_person() -> void:
	assert_true(CameraModeRulesScript.is_first_person(ROLE_TIGER))


func test_outer_role_is_not_first_person() -> void:
	assert_false(CameraModeRulesScript.is_first_person(ROLE_OUTER))


func test_unrecognized_role_fails_safe_to_third_person() -> void:
	assert_false(CameraModeRulesScript.is_first_person(&"not_a_real_role"),
		"an unrecognized role must never accidentally grant first-person -- fail-safe to third-person")


# --- CameraComponent -- owner-authority Player (name "1" == headless own id) -

var _player: CharacterBody3D


func test_owned_player_spawns_third_person_with_outer_default() -> void:
	_player = PlayerScene.instantiate()
	_player.name = "1"
	add_child_autofree(_player)

	var spring_arm: SpringArm3D = _player.get_node("CameraRig/SpringArm3D")
	var mesh: MeshInstance3D = _player.get_node("MeshInstance3D")
	assert_almost_eq(spring_arm.spring_length, 4.0, 0.0001,
		"default Outer role must keep the scene-authored TP spring length (Player.tscn's 4.0)")
	assert_true(mesh.visible, "third-person: the owning peer's own body mesh must stay visible")


func test_owned_player_set_role_tiger_swaps_to_first_person() -> void:
	_player = PlayerScene.instantiate()
	_player.name = "1"
	add_child_autofree(_player)

	_player.set_role(ROLE_TIGER)

	var spring_arm: SpringArm3D = _player.get_node("CameraRig/SpringArm3D")
	var mesh: MeshInstance3D = _player.get_node("MeshInstance3D")
	var camera_component: Node = _player.get_node("CameraComponent")
	assert_almost_eq(spring_arm.spring_length, camera_component.first_person_spring_length, 0.0001,
		"Tiger role must pull the spring arm in to the first-person length")
	assert_false(mesh.visible,
		"first-person: the owning peer's own body mesh must be hidden (camera would otherwise look out from inside it)")


func test_owned_player_set_role_back_to_outer_restores_third_person() -> void:
	_player = PlayerScene.instantiate()
	_player.name = "1"
	add_child_autofree(_player)

	_player.set_role(ROLE_TIGER)
	_player.set_role(ROLE_OUTER)

	var spring_arm: SpringArm3D = _player.get_node("CameraRig/SpringArm3D")
	var mesh: MeshInstance3D = _player.get_node("MeshInstance3D")
	assert_almost_eq(spring_arm.spring_length, 4.0, 0.0001,
		"swapping back to Outer must restore the original scene-authored TP distance, not a hardcoded second constant")
	assert_true(mesh.visible, "swapping back to Outer must re-show the owning peer's own body mesh")


func test_camera_mode_reacts_via_role_changed_signal_not_a_second_direct_call() -> void:
	# TK-P2-04 review nit: CameraComponent must react to `role_changed`
	# (signal-subscribe), not require Player.set_role() to also call it
	# directly -- assert the signal itself actually fires so this contract is
	# pinned (if a future refactor removes the emit, this test fails loudly
	# instead of the camera silently going stale).
	_player = PlayerScene.instantiate()
	_player.name = "1"
	add_child_autofree(_player)
	watch_signals(_player)

	_player.set_role(ROLE_TIGER)

	assert_signal_emitted_with_parameters(_player, "role_changed", [ROLE_TIGER])


# --- CameraComponent -- NON-owner-authority Player (name "2" != headless own id 1) -

func test_non_owned_player_set_role_tiger_does_not_touch_camera_or_mesh() -> void:
	# Design doc §5 step 3 ("จริงเฉพาะเครื่องเจ้าของ") + CameraModeRules.gd's
	# own class doc: a non-owning peer's copy of some OTHER Player must never
	# have its rig/mesh mutated by this -- only the owning peer's own
	# Camera3D is ever `current`, and mutating a non-owned copy's mesh
	# visibility would hide that Player's model from every OTHER peer's view.
	_player = PlayerScene.instantiate()
	_player.name = "2"
	add_child_autofree(_player)

	_player.set_role(ROLE_TIGER)

	var spring_arm: SpringArm3D = _player.get_node("CameraRig/SpringArm3D")
	var mesh: MeshInstance3D = _player.get_node("MeshInstance3D")
	assert_almost_eq(spring_arm.spring_length, 4.0, 0.0001,
		"a non-owned Player's spring arm must be untouched by this peer's own set_role() reaction")
	assert_true(mesh.visible,
		"a non-owned Player's body mesh must stay visible to every other peer regardless of its (Tiger) role")
