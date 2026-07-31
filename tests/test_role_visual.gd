extends GutTest
## Unit tests for TK-P3-13's TEMPORARY role-visual cue (gameplay-engineer):
## characters/components/RoleVisualRules.gd (pure role -> color/scale
## decision) and characters/components/RoleVisualComponent.gd's `role_changed`
## subscription + `_apply_role_visual()` wiring.
##
## Mirrors tests/test_camera_mode.gd's Player.tscn instantiation pattern
## (PlayerScene.instantiate() + add_child_autofree(), node.name set BEFORE
## entering the tree so Player._enter_tree() derives real authority instead of
## tripping its own non-numeric-name tripwire).
##
## UNLIKE test_camera_mode.gd: this component is deliberately NOT gated on
## is_multiplayer_authority() (see RoleVisualComponent.gd's own class doc for
## why -- every peer must visually agree on which capsule is the Tiger, not
## just the owning peer's own screen), so both an owned ("1") and a non-owned
## ("2") Player must react identically here -- there is no "non-owned Player
## must be untouched" case to assert, unlike CameraComponent's.

const RoleVisualRulesScript := preload("res://characters/components/RoleVisualRules.gd")
const PlayerScene := preload("res://characters/Player.tscn")

const ROLE_TIGER: StringName = &"tiger"
const ROLE_OUTER: StringName = &"outer"


# --- RoleVisualRules.color_for_role / scale_for_role (pure statics) --------

func test_tiger_role_is_orange() -> void:
	assert_eq(RoleVisualRulesScript.color_for_role(ROLE_TIGER), RoleVisualRulesScript.TIGER_COLOR)


func test_outer_role_is_white() -> void:
	assert_eq(RoleVisualRulesScript.color_for_role(ROLE_OUTER), RoleVisualRulesScript.OUTER_COLOR)


func test_unrecognized_role_fails_safe_to_outer_color() -> void:
	assert_eq(RoleVisualRulesScript.color_for_role(&"not_a_real_role"), RoleVisualRulesScript.OUTER_COLOR,
		"an unrecognized role must never accidentally grant the Tiger color -- fail-safe to Outer/white")


func test_tiger_role_scale_is_2x() -> void:
	assert_almost_eq(RoleVisualRulesScript.scale_for_role(ROLE_TIGER), 2.0, 0.0001,
		"Tiger scale must reuse the Art Bible's locked 2.0m height ratio")


func test_outer_role_scale_is_unchanged() -> void:
	assert_almost_eq(RoleVisualRulesScript.scale_for_role(ROLE_OUTER), 1.0, 0.0001)


func test_unrecognized_role_fails_safe_to_outer_scale() -> void:
	assert_almost_eq(RoleVisualRulesScript.scale_for_role(&"not_a_real_role"), 1.0, 0.0001,
		"an unrecognized role must never accidentally grant the Tiger's bigger scale -- fail-safe to Outer/1.0")


# --- RoleVisualComponent -- owned Player (name "1" == headless own id) -----

var _player: CharacterBody3D


func test_owned_player_spawns_with_outer_default_visual() -> void:
	_player = PlayerScene.instantiate()
	_player.name = "1"
	add_child_autofree(_player)

	var mesh: MeshInstance3D = _player.get_node("MeshInstance3D")
	assert_eq(mesh.material_override.albedo_color, RoleVisualRulesScript.OUTER_COLOR,
		"default Outer role must apply immediately on spawn, not only on a later role_changed signal")
	assert_eq(mesh.scale, Vector3.ONE)


func test_owned_player_set_role_tiger_swaps_to_orange_and_2x_scale() -> void:
	_player = PlayerScene.instantiate()
	_player.name = "1"
	add_child_autofree(_player)

	_player.set_role(ROLE_TIGER)

	var mesh: MeshInstance3D = _player.get_node("MeshInstance3D")
	assert_eq(mesh.material_override.albedo_color, RoleVisualRulesScript.TIGER_COLOR)
	assert_eq(mesh.scale, Vector3(2.0, 2.0, 2.0))


func test_owned_player_set_role_back_to_outer_restores_default_visual() -> void:
	_player = PlayerScene.instantiate()
	_player.name = "1"
	add_child_autofree(_player)

	_player.set_role(ROLE_TIGER)
	_player.set_role(ROLE_OUTER)

	var mesh: MeshInstance3D = _player.get_node("MeshInstance3D")
	assert_eq(mesh.material_override.albedo_color, RoleVisualRulesScript.OUTER_COLOR)
	assert_eq(mesh.scale, Vector3.ONE)


func test_role_visual_reacts_via_role_changed_signal_not_a_second_direct_call() -> void:
	_player = PlayerScene.instantiate()
	_player.name = "1"
	add_child_autofree(_player)
	watch_signals(_player)

	_player.set_role(ROLE_TIGER)

	assert_signal_emitted_with_parameters(_player, "role_changed", [ROLE_TIGER])


# --- RoleVisualComponent -- NON-owned Player (name "2" != headless own id 1) -
## Unlike CameraComponent, a non-owned Player's copy of this component MUST
## still react -- every peer needs to see every OTHER Player's role visually,
## not just their own (see this component's own class doc).

func test_non_owned_player_set_role_tiger_still_swaps_visual() -> void:
	_player = PlayerScene.instantiate()
	_player.name = "2"
	add_child_autofree(_player)

	_player.set_role(ROLE_TIGER)

	var mesh: MeshInstance3D = _player.get_node("MeshInstance3D")
	assert_eq(mesh.material_override.albedo_color, RoleVisualRulesScript.TIGER_COLOR,
		"a non-owned Player's Tiger color must still apply -- every peer must visually agree on who the Tiger is")
	assert_eq(mesh.scale, Vector3(2.0, 2.0, 2.0),
		"a non-owned Player's Tiger scale must still apply -- every peer must visually agree on who the Tiger is")
