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

# TK-P2-33: scene-tree-level regression coverage for the Tag OUTCOME's actual
# node-resolution (see the "GameManager.apply_role_switch" section at the bottom
# of this file).
const PlayerScene := preload("res://characters/Player.tscn")
const GameManagerScript := preload("res://managers/GameManager.gd")

const ROLE_TIGER: StringName = &"tiger"
const ROLE_OUTER: StringName = &"outer"


## TK-P2-33: see tests/test_role_state_machine.gd's own before_all() for the
## full writeup of the shared-process multiplayer-state hazard this resets. In
## short: GUT runs every tests/*.gd in ONE SceneTree, and any earlier-run file
## that assigned a real ENet peer (tests/test_network_manager.gd) leaves the
## shared root MultiplayerAPI in a "disconnected" (not "offline") state, which
## breaks is_multiplayer_authority()/get_unique_id() for the Player.tscn +
## GameManager scene-tree tests added at the bottom of this file. Resetting to
## a pristine default interface makes this file order-independent, exactly as
## test_role_state_machine.gd/test_camera_mode.gd already do for their own
## Player.tscn tests.
func before_all() -> void:
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), NodePath(""))


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


# --- GameManager.apply_role_switch node resolution (TK-P2-33) ---------------
# POSITIVE-SIDE-EFFECT regression coverage for the bug CLASS that has now
# recurred twice in this codebase (TK-P2-32 host_validate() targeted the wrong
# player; TK-BUG-P2-01 on_confirmed()'s stagger gate checked the wrong node) --
# glue code that resolves "which live node under an RPC broadcast is the actual
# target" being silently wrong while 300+ pure-function GUT asserts stay green.
#
# TagAbility itself (TK-P2-03) is the OTHER host-authoritative "outcome changes
# who is the Tiger" surface, structurally the same shape as the two bugs above.
# But TagAbility.on_confirmed() is log-only -- the OBSERVABLE Tag outcome (the
# role swap every peer must agree on) is applied by
# managers/GameManager.gd's apply_role_switch(), which resolves BOTH the old and
# new Tiger's Player nodes off the shared "Players" root
# (players_root.get_node_or_null(str(id))) and calls set_role() on each. That
# resolution step is EXACTLY the kind of glue the two prior bugs lived in, yet
# before this card only the pure managers/TagSequenceRules.gd helpers were GUT-
# covered -- nothing asserted the role actually lands on the CORRECT resolved
# node. These tests instantiate real Player.tscn instances (no mocks) under a
# real "Players" root and assert the observable role flip landed on the right
# node, matching the TK-P2-32/TK-BUG-P2-01 pattern in tests/test_kick_rules.gd.
#
# SETUP (decoupled from GameManager's own _ready, deliberately): all three
# handlers under test here (apply_role_switch/assign_first_tiger/_apply_tiger_
# position_correction) depend ONLY on GameManager's `_players_root`. So these
# tests spawn the real Player.tscn instances under a real "Players" root IN the
# tree (so each Player's own is_multiplayer_authority()/_enter_tree authority
# resolves), then inject that root into a GameManager instance that is NOT added
# to the tree -- so GameManager's host-only _ready() (which since TK-P2-14/15
# wires a CountdownManager sibling + a match-end watch and can fire broadcast
# RPCs) never runs, and the stable, human-verified role RESOLUTION handler is
# exercised in isolation from that match-flow scaffolding. This mirrors how
# tests/test_kick_rules.gd calls KickAbility.on_confirmed() directly with a
# synthesized payload rather than driving a live rpc_confirm broadcast.
# Headless GUT's own multiplayer id is 1, so a Player named "1" reports
# is_multiplayer_authority() == true (this peer "owns" it) and any other name
# reports false -- no live ENet peer needed, same basis
# tests/test_kick_rules.gd / tests/test_safe_circle.gd already rely on.

## Builds a real, in-tree "Players" root (freed via add_child_autofree) that the
## injected GameManager below resolves its swaps against.
func _build_players_root() -> Node:
	var root := Node3D.new()
	add_child_autofree(root)
	var players := Node3D.new()
	players.name = "Players"
	root.add_child(players)
	return players


## A GameManager instance with `_players_root` injected but NOT added to the
## tree (see SETUP note) -- freed via autofree(). Its @onready _players_root is
## never resolved (never in a tree), so this manual assignment is authoritative.
func _make_game_manager(players: Node) -> Node:
	var gm: Node = GameManagerScript.new()
	autofree(gm)
	gm._players_root = players
	return gm


## Instantiates a real Player.tscn under `players`, named/positioned/role-
## assigned as requested. Same naming-contract (name BEFORE add_child) +
## default-Outer-so-only-set-non-default pattern tests/test_kick_rules.gd's own
## _spawn_kick_candidate() uses.
func _spawn_player(players: Node, peer_name: String, role: StringName, pos: Vector3) -> CharacterBody3D:
	var p: CharacterBody3D = PlayerScene.instantiate()
	p.name = peer_name
	players.add_child(p)
	p.global_position = pos
	if role != ROLE_OUTER:
		p.set_role(role)
	return p


func test_apply_role_switch_flips_the_two_resolved_players_to_the_correct_roles() -> void:
	var players: Node = _build_players_root()
	var gm: Node = _make_game_manager(players)

	# Old Tiger owned by this local peer (name "1" == headless GUT own id);
	# new Tiger + an untouched bystander are remote-owned.
	var old_tiger: CharacterBody3D = _spawn_player(players, "1", ROLE_TIGER, Vector3(1.0, 0.0, 0.0))
	var new_tiger: CharacterBody3D = _spawn_player(players, "2", ROLE_OUTER, Vector3(2.0, 0.0, 0.0))
	var bystander: CharacterBody3D = _spawn_player(players, "3", ROLE_OUTER, Vector3(3.0, 0.0, 0.0))

	assert_eq(old_tiger.role, ROLE_TIGER, "sanity: the old tiger is the Tiger before the swap")

	gm.apply_role_switch(1, 2, Vector3(6.0, 0.0, 0.0))

	assert_eq(new_tiger.role, ROLE_TIGER,
		"apply_role_switch must resolve Players/2 and make IT the new Tiger -- the observable 'who is the Tiger' outcome must land on the correct node, not just run without crashing")
	assert_eq(old_tiger.role, ROLE_OUTER,
		"apply_role_switch must resolve Players/1 and flip IT back to Outer")
	assert_eq(bystander.role, ROLE_OUTER,
		"a Player not named in the swap must be left untouched (resolution must be selective, not blanket)")


func test_apply_role_switch_teleports_only_the_owned_old_tiger_to_the_exit_position() -> void:
	var players: Node = _build_players_root()
	var gm: Node = _make_game_manager(players)

	var old_tiger: CharacterBody3D = _spawn_player(players, "1", ROLE_TIGER, Vector3(1.0, 0.0, 0.0))
	_spawn_player(players, "2", ROLE_OUTER, Vector3(2.0, 0.0, 0.0))

	gm.apply_role_switch(1, 2, Vector3(6.0, 0.0, 0.0))

	# The step-6 placeholder exit teleport is authority-gated -- it must apply to
	# the OWNED old tiger's own resolved node (name "1" == this peer's id).
	assert_almost_eq(old_tiger.position.x, 6.0, 0.001,
		"the resolved, owned old-tiger node must be teleported to the exit_position -- the observable step-6 side effect must land on the correct node")


func test_apply_role_switch_does_not_teleport_a_non_owned_old_tiger() -> void:
	var players: Node = _build_players_root()
	var gm: Node = _make_game_manager(players)

	# Old tiger named "9" -- NOT this peer's id, so is_multiplayer_authority()
	# is false for it: its role still flips (that is not authority-gated), but
	# position is owner-authoritative so this peer must not write it.
	var old_tiger: CharacterBody3D = _spawn_player(players, "9", ROLE_TIGER, Vector3(1.0, 0.0, 0.0))
	_spawn_player(players, "2", ROLE_OUTER, Vector3(2.0, 0.0, 0.0))

	gm.apply_role_switch(9, 2, Vector3(6.0, 0.0, 0.0))

	assert_eq(old_tiger.role, ROLE_OUTER, "role flip is not authority-gated -- it still resolves + applies on every peer")
	assert_almost_eq(old_tiger.position.x, 1.0, 0.001,
		"a non-owned old tiger's position must NOT be written locally -- only its own owning peer may move it (owner-authoritative position)")


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
