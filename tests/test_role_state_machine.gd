extends GutTest
## Unit tests for the TK-P2-04 Role state machine (gameplay-engineer):
## characters/RoleRules.gd (pure valid-role guard), characters/Player.gd's
## set_role()/`role_changed` signal, and characters/components/
## MovementComponent.gd's new per-role speed profile.
##
## Investigation for this card found the Role SM's core mechanics already
## landed as groundwork from TK-P2-03/TK-P2-16 (Player.set_role() propagating
## to AbilityController, GameManager.apply_role_switch() calling it at Tag
## Sequence steps 4+5) -- what was genuinely missing, and what this file
## covers, is: (1) an explicit valid-transition guard (RoleRules), (2) the
## per-role MovementComponent speed profile ("property" swap per design doc
## §5 step 3 / §6 balance table, previously unwired), and (3) the
## `role_changed` signal hook TK-P2-05 needs for its camera swap.
##
## RoleRules.is_valid_role() and MovementComponent.speed_profile_multiplier()
## are pure statics (no scene tree needed, same pattern as every other pure
## helper in this codebase). Player.set_role()'s guard + distribution +
## signal, and MovementComponent.set_role()'s profile selection, need a real
## Player.tscn instance (touches sibling @onready components) -- same
## PlayerScene.instantiate() + add_child_autofree() pattern
## tests/test_ability_system.gd already uses.

const RoleRulesScript := preload("res://characters/RoleRules.gd")
const MovementScript := preload("res://characters/components/MovementComponent.gd")
const PlayerScene := preload("res://characters/Player.tscn")

const ROLE_TIGER: StringName = &"tiger"
const ROLE_OUTER: StringName = &"outer"


## PRE-EXISTING test-suite ordering hazard, discovered while writing this
## card's tests (NOT introduced by this card, not a NetworkManager production
## bug -- flagged to tools-devops/network-engineer as a followup, see this
## card's handoff note): GUT runs every tests/*.gd script in ONE shared
## process/SceneTree. tests/test_network_manager.gd's host()/join() tests
## assign a REAL ENetMultiplayerPeer to `get_tree().get_multiplayer()` (the
## SAME root MultiplayerAPI every node in every OTHER test script also uses)
## and then clear it back to null on teardown -- but empirically (verified
## with a standalone repro), Godot's SceneMultiplayer treats "never had a
## peer" (is_server() conveniently defaults true, offline-friendly) and "had
## a real peer, now cleared" (is_server() now correctly reports FALSE,
## get_unique_id() errors -- a real disconnected client, correctly, should
## NOT still claim to be the server) as two DIFFERENT internal states, not
## the same "offline" state. Once ANY test file assigns a real peer, EVERY
## later-run script sharing that process (alphabetically-later than
## test_network_manager.gd, which is exactly where this file sorts) inherits
## the "disconnected", not "offline", state -- breaking any Player.tscn
## instantiation that touches is_multiplayer_authority()/get_unique_id()
## (CameraComponent._ready(), AbilityController._enter_tree(), etc.) with
## engine errors GUT (correctly) treats as test failures. This is invisible
## in production (a real process only ever hosts/joins/stays offline ONCE
## for its whole lifetime) and was invisible in this suite until now only
## because every EXISTING Player.tscn-touching test script
## (test_ability_system.gd) happens to sort alphabetically BEFORE
## test_network_manager.gd, not because it was actually safe.
##
## Fix (test-file-local only -- does NOT touch networking/NetworkManager.gd
## or any production code/authority model, per this agent's scope limits):
## reset the SceneTree's MultiplayerAPI to a brand-new instance before this
## file's Player.tscn-touching tests run, restoring the pristine "offline"
## default regardless of what any earlier-run test script left behind.
func before_all() -> void:
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), NodePath(""))


# --- RoleRules.is_valid_role (pure static) ---------------------------------

func test_outer_is_a_valid_role() -> void:
	assert_true(RoleRulesScript.is_valid_role(ROLE_OUTER))


func test_tiger_is_a_valid_role() -> void:
	assert_true(RoleRulesScript.is_valid_role(ROLE_TIGER))


func test_unknown_role_is_invalid() -> void:
	assert_false(RoleRulesScript.is_valid_role(&"not_a_real_role"))


func test_empty_stringname_is_invalid() -> void:
	assert_false(RoleRulesScript.is_valid_role(&""))


# --- MovementComponent.speed_profile_multiplier (pure static) --------------

func test_speed_profile_multiplier_outer_balance_values() -> void:
	# Game_Balance.md §2: Human walk 4.0 / sprint 6.0 -> x1.5.
	assert_almost_eq(MovementScript.speed_profile_multiplier(4.0, 6.0), 1.5, 0.0001)


func test_speed_profile_multiplier_tiger_balance_values() -> void:
	# Tiger walk/sprint both capped at 4.0 -> x1.0 (sprint = no advantage).
	assert_almost_eq(MovementScript.speed_profile_multiplier(4.0, 4.0), 1.0, 0.0001)


func test_speed_profile_multiplier_guards_zero_walk() -> void:
	assert_eq(MovementScript.speed_profile_multiplier(0.0, 6.0), 1.0,
		"a degenerate/misconfigured zero walk_speed must not divide-by-zero -- fail safe to x1.0")


# --- MovementComponent.set_role (bare instance -- touches only self fields) -
# Mirrors test_tag_sequence.gd's own bare-instance TagAbility tests: set_role()
# only ever reads/writes this component's own @export tunables, never the
# @onready `_body`/`_camera_rig` (those stay unresolved on a bare `.new()`
# never added to a tree), so it is safe to call directly without a live Player.

var _movement: Node


func after_each() -> void:
	if is_instance_valid(_movement):
		_movement.free()
		_movement = null


func test_set_role_outer_applies_human_speed_profile() -> void:
	_movement = MovementScript.new()
	_movement.set_role(ROLE_OUTER)
	assert_eq(_movement.walk_speed, _movement.outer_walk_speed)
	assert_almost_eq(
		_movement.sprint_multiplier,
		_movement.outer_sprint_speed / _movement.outer_walk_speed,
		0.0001
	)


func test_set_role_tiger_applies_tiger_speed_profile() -> void:
	_movement = MovementScript.new()
	_movement.set_role(ROLE_TIGER)
	assert_eq(_movement.walk_speed, _movement.tiger_walk_speed)
	assert_almost_eq(
		_movement.sprint_multiplier,
		_movement.tiger_sprint_speed / _movement.tiger_walk_speed,
		0.0001
	)


func test_set_role_unrecognized_value_fails_safe_to_outer_profile() -> void:
	# Should not be reachable via Player.set_role() (RoleRules guards it
	# upstream), but this method's own fail-safe default is asserted directly
	# per its own doc comment.
	_movement = MovementScript.new()
	_movement.set_role(&"not_a_real_role")
	assert_eq(_movement.walk_speed, _movement.outer_walk_speed)


func test_tiger_walk_speed_is_capped_at_or_below_outer_walk_speed() -> void:
	# Game_Balance.md §3 locked intent: Tiger is a hunt-not-chase stalker, never
	# faster than a Human at either walk or (capped) sprint.
	_movement = MovementScript.new()
	assert_true(_movement.tiger_walk_speed <= _movement.outer_walk_speed)
	assert_true(_movement.tiger_sprint_speed <= _movement.outer_sprint_speed)


# --- Player.set_role() -- valid-transition guard + distribution + signal ---

## _player instances below are freed automatically by add_child_autofree()
## (same teardown pattern tests/test_ability_system.gd's Player.tscn tests
## use) -- no separate after_each needed for them.
var _player: CharacterBody3D


func test_player_starts_as_outer_with_outer_speed_profile() -> void:
	_player = PlayerScene.instantiate()
	# Naming contract (TK-BUG-P1-01, node.name == str(peer_id)): set BEFORE
	# entering the tree so Player._enter_tree() derives real owner authority
	# instead of tripping its own non-numeric-name tripwire (same pattern
	# tests/test_ability_system.gd already uses for its Player.tscn tests).
	_player.name = "2"
	add_child_autofree(_player)
	assert_eq(_player.role, ROLE_OUTER)
	var movement: Node = _player.get_node("MovementComponent")
	assert_eq(movement.walk_speed, movement.outer_walk_speed,
		"MovementComponent must self-apply the Outer profile at spawn, same as AbilityController's own catalog build")


func test_set_role_tiger_updates_role_and_distributes_to_movement_and_ability_controller() -> void:
	_player = PlayerScene.instantiate()
	# Naming contract (TK-BUG-P1-01, node.name == str(peer_id)): set BEFORE
	# entering the tree so Player._enter_tree() derives real owner authority
	# instead of tripping its own non-numeric-name tripwire (same pattern
	# tests/test_ability_system.gd already uses for its Player.tscn tests).
	_player.name = "2"
	add_child_autofree(_player)

	_player.set_role(ROLE_TIGER)

	assert_eq(_player.role, ROLE_TIGER)
	var movement: Node = _player.get_node("MovementComponent")
	assert_eq(movement.walk_speed, movement.tiger_walk_speed,
		"set_role(tiger) must swap MovementComponent to the Tiger speed profile (the 'property' half of this card)")

	var ability_controller: Node = _player.get_node("AbilityController")
	assert_true(ability_controller._abilities.has(&"tag"),
		"set_role(tiger) must still rebuild the AbilityController catalog to Tiger's (TagAbility) -- unchanged TK-P2-16/03 behavior")


func test_set_role_emits_role_changed_signal_with_new_role() -> void:
	_player = PlayerScene.instantiate()
	# Naming contract (TK-BUG-P1-01, node.name == str(peer_id)): set BEFORE
	# entering the tree so Player._enter_tree() derives real owner authority
	# instead of tripping its own non-numeric-name tripwire (same pattern
	# tests/test_ability_system.gd already uses for its Player.tscn tests).
	_player.name = "2"
	add_child_autofree(_player)
	watch_signals(_player)

	_player.set_role(ROLE_TIGER)

	# role_changed must fire with the new role -- this is the hook TK-P2-05
	# needs for its camera swap.
	assert_signal_emitted_with_parameters(_player, "role_changed", [ROLE_TIGER])


func test_set_role_rejects_invalid_role_and_leaves_state_unchanged() -> void:
	_player = PlayerScene.instantiate()
	# Naming contract (TK-BUG-P1-01, node.name == str(peer_id)): set BEFORE
	# entering the tree so Player._enter_tree() derives real owner authority
	# instead of tripping its own non-numeric-name tripwire (same pattern
	# tests/test_ability_system.gd already uses for its Player.tscn tests).
	_player.name = "2"
	add_child_autofree(_player)
	watch_signals(_player)

	_player.set_role(&"not_a_real_role")

	# set_role() deliberately GameLog.error()s (-> push_error()) on an invalid
	# role -- fail LOUDLY per its own doc, not silently. assert_push_error()
	# both confirms that happened and tells GUT this push_error was expected,
	# so it does not also fail the test as an "unexpected error".
	assert_push_error("not a valid role")
	assert_eq(_player.role, ROLE_OUTER, "an invalid role must be rejected -- role must stay unchanged")
	assert_signal_not_emitted(_player, "role_changed",
		"an invalid/rejected role must never emit role_changed -- listeners (TK-P2-05) must only ever observe real transitions")


func test_set_role_is_idempotent_when_reapplying_the_same_role() -> void:
	_player = PlayerScene.instantiate()
	# Naming contract (TK-BUG-P1-01, node.name == str(peer_id)): set BEFORE
	# entering the tree so Player._enter_tree() derives real owner authority
	# instead of tripping its own non-numeric-name tripwire (same pattern
	# tests/test_ability_system.gd already uses for its Player.tscn tests).
	_player.name = "2"
	add_child_autofree(_player)

	_player.set_role(ROLE_OUTER) # already Outer -- should be a harmless no-op rebuild

	assert_eq(_player.role, ROLE_OUTER)
	var movement: Node = _player.get_node("MovementComponent")
	assert_eq(movement.walk_speed, movement.outer_walk_speed)
