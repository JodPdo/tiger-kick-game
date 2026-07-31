extends GutTest
## Unit tests for the TK-P2-16 Step 3 Ability System scaffold:
## characters/abilities/Ability.gd, HumanAbility.gd, TigerAbility.gd, and
## AbilityCatalog.gd.
##
## Only node-independent logic is covered here: AbilityCatalog is a pure
## static registry (same testable pattern as managers/TigerSelector.gd and
## networking/SpawnPointUtil.gd), and Ability/HumanAbility/TigerAbility are
## plain Node subclasses with no scene-tree dependencies in their default
## (scaffold) bodies, so they can be instantiated directly with `.new()`.
## Live wiring (AbilityController rebuilding ability children from the
## catalog, the 3 RPC endpoints, role plumbing on Player) needs a running
## multiplayer session and is covered by the manual 2-window verification
## in this card, not GUT.
##
## NOTE: Requires the GUT addon (TK-PX-07), same as the other tests here.

const AbilityScript := preload("res://characters/abilities/Ability.gd")
const HumanAbilityScript := preload("res://characters/abilities/HumanAbility.gd")
const TigerAbilityScript := preload("res://characters/abilities/TigerAbility.gd")
const AbilityCatalogScript := preload("res://characters/abilities/AbilityCatalog.gd")
const KickAbilityScript := preload("res://characters/abilities/KickAbility.gd")
const TagAbilityScript := preload("res://characters/abilities/TagAbility.gd")
const PounceAbilityScript := preload("res://characters/abilities/PounceAbility.gd")
const PlayerScene := preload("res://characters/Player.tscn")

const ROLE_TIGER: StringName = &"tiger"
const ROLE_OUTER: StringName = &"outer"


# --- AbilityCatalog.abilities_for_role (pure static) ---------------------------

func test_tiger_role_has_tag_registered() -> void:
	# TK-P2-03: Tiger's catalog now has its first real entry -- TagAbility
	# (the Tag ACTION, step 1 of the 7-step Tag Sequence). This supersedes
	# the old scaffold assertion (TK-P2-16) that Tiger's catalog was empty,
	# same "registering IS the DoD landing" supersession
	# test_outer_role_has_kick_registered() below already documents for
	# Outer/Kick.
	#
	# TK-P2-18: Tiger's catalog now also has PounceAbility (the burst dash) --
	# see test_tiger_role_has_pounce_registered() below for that entry's own
	# assertion. Crouch/Lean/Peek (TK-P3-05) are still the cards that append
	# the rest of Tiger's design doc §6 catalog.
	var result: Array = AbilityCatalogScript.abilities_for_role(ROLE_TIGER)
	assert_eq(result.size(), 2, "Tiger catalog should have exactly two entries (TagAbility, PounceAbility) at this step")
	assert_eq(result[0], TagAbilityScript, "Tiger's first catalog entry should be TagAbility.gd")


func test_tiger_role_has_pounce_registered() -> void:
	# TK-P2-18: Pounce is Tiger's second catalog entry, appended after Tag
	# (see AbilityCatalog.gd's own doc: "add ability = 1 file + 1 catalog
	# line" -- this is that line landing for Pounce, same DoD Kick/Tag's own
	# registration tests already document).
	var result: Array = AbilityCatalogScript.abilities_for_role(ROLE_TIGER)
	assert_true(result.has(PounceAbilityScript), "Tiger's catalog must include PounceAbility.gd")


func test_outer_role_has_kick_registered() -> void:
	# TK-P2-01: Outer's catalog now has its first real entry -- KickAbility.
	# This test supersedes the old scaffold assertion (TK-P2-16) that Outer's
	# catalog was empty; Kick registering here IS the "add ability = 1 file +
	# 1 catalog line" DoD (design doc §7 Step 4) actually landing.
	var result: Array = AbilityCatalogScript.abilities_for_role(ROLE_OUTER)
	assert_eq(result.size(), 1, "Outer catalog should have exactly one entry (KickAbility) at this step")
	assert_eq(result[0], KickAbilityScript, "Outer's single catalog entry should be KickAbility.gd")


func test_unknown_role_returns_empty_array_not_null() -> void:
	var result: Array = AbilityCatalogScript.abilities_for_role(&"not_a_real_role")
	assert_eq(result, [], "an unrecognized role must fail safe to no abilities, never null/crash")


func test_abilities_for_role_returns_a_fresh_array_each_call() -> void:
	# Mutating a previously-returned Array must never leak into the next call
	# -- AbilityController relies on being handed an independent Array it can
	# freely iterate without corrupting the catalog for the next Player/role
	# switch. ROLE_TIGER now ships two real entries (TagAbility TK-P2-03,
	# PounceAbility TK-P2-18) -- the assertion below checks the SAME
	# independence property that used to be checked against an empty array,
	# just against a non-empty one now.
	var first: Array = AbilityCatalogScript.abilities_for_role(ROLE_TIGER)
	first.append("scratch_entry_that_should_not_leak")
	var second: Array = AbilityCatalogScript.abilities_for_role(ROLE_TIGER)
	assert_eq(second.size(), 2, "abilities_for_role must return an independent Array on every call -- the scratch append above must not leak in")
	assert_false(second.has("scratch_entry_that_should_not_leak"), "a previously-returned Array's mutation must never leak into the next call's result")


# --- Ability base class defaults (safe/conservative scaffold behavior) --------

var _ability: Ability


func after_each() -> void:
	if is_instance_valid(_ability):
		_ability.free()
		_ability = null


func test_ability_default_resolution_is_host_authoritative() -> void:
	_ability = AbilityScript.new()
	assert_eq(_ability.resolution, AbilityScript.Resolution.HOST_AUTHORITATIVE,
		"forgetting to declare resolution must fail safe to HOST_AUTHORITATIVE, never LOCAL_ONLY")


func test_ability_can_activate_defaults_true() -> void:
	_ability = AbilityScript.new()
	assert_true(_ability.can_activate({}), "base Ability.can_activate has nothing to block by default")


func test_ability_host_validate_defaults_to_rejected() -> void:
	_ability = AbilityScript.new()
	var verdict: Dictionary = _ability.host_validate({})
	assert_false(verdict.get("ok", true), "a bare/unconfigured Ability must fail-closed (never auto-approve)")


func test_ability_id_defaults_to_empty_stringname() -> void:
	_ability = AbilityScript.new()
	assert_eq(_ability.ability_id, &"", "ability_id must be design-set per concrete ability, blank on the base class")


func test_ability_cooldown_defaults_to_zero() -> void:
	_ability = AbilityScript.new()
	assert_eq(_ability.cooldown_sec, 0.0)


func test_ability_lifecycle_hooks_are_safe_no_ops() -> void:
	# Every virtual method must be callable on a bare Ability without a scene
	# tree/multiplayer context and without raising -- this only asserts "did
	# not crash" (GUT fails the test automatically on an unhandled error).
	_ability = AbilityScript.new()
	_ability.on_activate_local({})
	_ability.host_apply(null)
	_ability.on_confirmed(null)
	_ability.on_rejected("some_reason")
	assert_true(true, "all Ability virtual hooks ran without error on a bare instance")


# --- HumanAbility / TigerAbility subclassing -----------------------------------

func test_human_ability_is_an_ability() -> void:
	_ability = HumanAbilityScript.new()
	assert_true(_ability is AbilityScript, "HumanAbility must extend Ability")


func test_tiger_ability_is_an_ability() -> void:
	_ability = TigerAbilityScript.new()
	assert_true(_ability is AbilityScript, "TigerAbility must extend Ability")


func test_human_ability_inherits_host_authoritative_default() -> void:
	_ability = HumanAbilityScript.new()
	assert_eq(_ability.resolution, AbilityScript.Resolution.HOST_AUTHORITATIVE)


# --- AbilityController authority = server (TK-P2-16 Step 3 blocker fix) --------
# Tripwire for Fix 1 (network-engineer, design doc section 4 amended
# 2026-07-05): AbilityController._enter_tree() calls
# set_multiplayer_authority(1), overriding the OWNING-PEER authority that
# Player.gd's own _enter_tree() recursively assigns (int(name), recursive) --
# so the ability RPC surface is host-authoritative even on a client-OWNED
# Player. Without this fix, @rpc("authority") on the controller would mean
# "the owning client", dropping the host's confirm/reject and letting a client
# forge rpc_confirm (S1 server-authority inversion).
#
# We instantiate a real Player.tscn named "2" -- the deterministic naming
# contract (node.name == str(peer_id), PlayerSpawner) makes this a
# CLIENT-owned Player (peer 2), exactly the case the bug bit. This runs with
# the headless GUT SceneMultiplayer (own id = 1); set_multiplayer_authority is
# a purely local Node property, so the values are meaningful without a live
# ENet peer.

func test_ability_controller_authority_is_server_on_client_owned_player() -> void:
	var player: CharacterBody3D = PlayerScene.instantiate()
	# Set the owner-peer name BEFORE entering the tree so Player._enter_tree()
	# derives authority 2 (the client) for the whole subtree first, then
	# AbilityController._enter_tree() overrides its own subtree back to 1.
	player.name = "2"
	add_child_autofree(player)

	var controller: Node = player.get_node("AbilityController")
	assert_eq(controller.get_multiplayer_authority(), 1,
		"AbilityController must be host-authoritative (peer 1) even on a client-owned Player -- Fix 1: _enter_tree set_multiplayer_authority(1)")


func test_player_root_keeps_owner_authority_when_controller_overrides() -> void:
	# Invariant guard (TK-BUG-P1-01): Fix 1 must ONLY re-target the controller's
	# own subtree. The Player root and its MultiplayerSynchronizer must still
	# report the OWNING peer (2), or owner-sync (position/rotation/pose) would
	# break.
	var player: CharacterBody3D = PlayerScene.instantiate()
	player.name = "2"
	add_child_autofree(player)

	assert_eq(player.get_multiplayer_authority(), 2,
		"Player root must keep owner (peer 2) authority -- Fix 1 must not touch the root (TK-BUG-P1-01 invariant)")
	var sync: Node = player.get_node("MultiplayerSynchronizer")
	assert_eq(sync.get_multiplayer_authority(), 2,
		"MultiplayerSynchronizer must keep owner (peer 2) authority so owner-sync replicates FROM the owning peer")

