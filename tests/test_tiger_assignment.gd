extends GutTest
## Unit tests for managers/TigerSelector.gd — first-Tiger selection & role assignment.
##
## Covers TK-P2-09 (สุ่มเสือตัวแรก, host-authoritative). Only the pure decision
## logic is tested here (node-independent, no live peers/RPC). Live cross-instance
## "everyone sees the same Tiger" verification belongs to Integration/QA, not GUT.
##
## NOTE: Requires the GUT addon (TK-PX-07). Until then CI skips it, but this file
## is ready to run. RNG is injected + seeded so every test is deterministic.

const TigerSelectorScript := preload("res://managers/TigerSelector.gd")

# TK-P2-33: scene-tree-level regression coverage for GameManager.assign_first_
# tiger()'s actual node resolution (see the "assign_first_tiger" section below).
const PlayerScene := preload("res://characters/Player.tscn")
const GameManagerScript := preload("res://managers/GameManager.gd")

const ROLE_TIGER: StringName = &"tiger"
const ROLE_OUTER: StringName = &"outer"

const FOUR_PEERS: Array = [1, 2, 3, 4]  # host id 1 + three clients

var _rng: RandomNumberGenerator


## TK-P2-33: reset the shared-process root MultiplayerAPI to a pristine default
## before this file's Player.tscn + GameManager scene-tree tests, so
## is_multiplayer_authority()/get_unique_id() behave as "offline" regardless of
## what an earlier-run test file (test_network_manager.gd) left behind -- see
## tests/test_role_state_machine.gd's own before_all() for the full writeup.
func before_all() -> void:
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), NodePath(""))


func before_each() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = 12345  # fixed seed => deterministic tests


# --- core requirement: always exactly ONE tiger among 4 peers -----------------

func test_exactly_one_tiger_with_4_peers() -> void:
	var tiger: int = TigerSelectorScript.pick_first_tiger(FOUR_PEERS, _rng)
	var roles: Dictionary = TigerSelectorScript.build_role_map(FOUR_PEERS, tiger)
	assert_eq(TigerSelectorScript.count_tigers(roles), 1,
		"a valid round must have exactly one Tiger")
	assert_eq(roles.size(), FOUR_PEERS.size(),
		"every peer must be assigned a role (tiger or outer)")


func test_chosen_tiger_is_one_of_the_peers() -> void:
	# repeat many times: the pick must always be a real member of the pool
	for _i in range(500):
		var tiger: int = TigerSelectorScript.pick_first_tiger(FOUR_PEERS, _rng)
		assert_true(FOUR_PEERS.has(tiger),
			"picked Tiger %d must be one of the connected peers" % tiger)


func test_all_peers_can_become_tiger() -> void:
	# fairness: over many draws every peer should get picked at least once
	var seen: Dictionary = {}
	for _i in range(2000):
		seen[TigerSelectorScript.pick_first_tiger(FOUR_PEERS, _rng)] = true
	for id in FOUR_PEERS:
		assert_true(seen.has(id),
			"peer %d should be selectable as Tiger (no one is excluded)" % id)


# --- edge cases ---------------------------------------------------------------

func test_single_peer_becomes_tiger() -> void:
	var tiger: int = TigerSelectorScript.pick_first_tiger([7], _rng)
	assert_eq(tiger, 7, "with one player, that player is the Tiger")


func test_empty_pool_returns_no_id() -> void:
	var tiger: int = TigerSelectorScript.pick_first_tiger([], _rng)
	assert_eq(tiger, TigerSelectorScript.NO_ID,
		"empty peer list returns NO_ID (-1), no crash")


func test_role_map_with_stale_tiger_id_has_zero_tigers() -> void:
	# if the chosen id already left, no one is wrongly marked Tiger
	var roles: Dictionary = TigerSelectorScript.build_role_map(FOUR_PEERS, 999)
	assert_eq(TigerSelectorScript.count_tigers(roles), 0,
		"a stale/absent tiger_id must not mark any peer as Tiger (caller re-picks)")


# --- anti-repeat (optional, tuned in Phase 3) ---------------------------------

func test_anti_repeat_avoids_previous_tiger() -> void:
	# with >1 candidates, avoiding the previous Tiger must always hold
	for _i in range(500):
		var tiger: int = TigerSelectorScript.pick_first_tiger(FOUR_PEERS, _rng, 2)
		assert_ne(tiger, 2, "anti-repeat: previous Tiger (2) must not be picked again")


func test_anti_repeat_ignored_when_single_candidate() -> void:
	# can't avoid the only player -> still returns them (no infinite loop / -1)
	var tiger: int = TigerSelectorScript.pick_first_tiger([5], _rng, 5)
	assert_eq(tiger, 5, "with one player, anti-repeat is ignored")


# --- determinism (proves host RNG is reproducible / injectable) ---------------

func test_same_seed_gives_same_pick() -> void:
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 42
	b.seed = 42
	assert_eq(
		TigerSelectorScript.pick_first_tiger(FOUR_PEERS, a),
		TigerSelectorScript.pick_first_tiger(FOUR_PEERS, b),
		"same seed must yield the same Tiger (host selection is reproducible)")


# --- GameManager.assign_first_tiger node resolution (TK-P2-33) ---------------
# POSITIVE-SIDE-EFFECT regression coverage, same bug CLASS as TK-P2-32 /
# TK-BUG-P2-01 (glue that resolves "which live node does this RPC broadcast's
# result apply to" being silently wrong under green pure-function tests). The
# tests above cover the PURE selection logic (managers/TigerSelector.gd); this
# section covers the separate scene-tree step managers/GameManager.gd's
# assign_first_tiger() RPC handler performs -- resolving each spawned Player off
# the "Players" root and calling set_role() on the CORRECT node -- which nothing
# asserted at the observable-effect level before this card. Real Player.tscn
# instances (no mocks), matching tests/test_kick_rules.gd's pattern.
#
# SETUP is decoupled from GameManager._ready() -- assign_first_tiger() depends
# ONLY on GameManager's `_players_root`, so the real Player.tscn instances are
# spawned under an in-tree "Players" root (so each Player's own authority
# resolves) and that root is injected into a GameManager NOT added to the tree,
# so its host-only _ready() (CountdownManager wiring + match-end watch + a
# possible RNG-driven first-Tiger broadcast) never runs. See
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


func _spawn_player(players: Node, peer_name: String, role: StringName, pos: Vector3) -> CharacterBody3D:
	var p: CharacterBody3D = PlayerScene.instantiate()
	p.name = peer_name
	players.add_child(p)
	p.global_position = pos
	if role != ROLE_OUTER:
		p.set_role(role)
	return p


func test_assign_first_tiger_crowns_the_named_peer_and_confirms_everyone_else_outer() -> void:
	var players: Node = _build_players_root()
	var gm: Node = _make_game_manager(players)

	# All at origin (inside the Safe Circle) so the host-side boundary
	# correction never fires against the chosen Tiger mid-test.
	var p1: CharacterBody3D = _spawn_player(players, "1", ROLE_OUTER, Vector3.ZERO)
	var p2: CharacterBody3D = _spawn_player(players, "2", ROLE_OUTER, Vector3.ZERO)
	var p3: CharacterBody3D = _spawn_player(players, "3", ROLE_OUTER, Vector3.ZERO)

	gm.assign_first_tiger(2)

	assert_eq(p2.role, ROLE_TIGER,
		"assign_first_tiger(2) must resolve Players/2 and make IT the Tiger -- the observable role must land on the correct node, not just run without crashing")
	assert_eq(p1.role, ROLE_OUTER, "every other resolved Player must be (re)confirmed Outer")
	assert_eq(p3.role, ROLE_OUTER, "every other resolved Player must be (re)confirmed Outer")

	var tiger_count: int = 0
	for c in players.get_children():
		if c.role == ROLE_TIGER:
			tiger_count += 1
	assert_eq(tiger_count, 1, "exactly one Player may be the Tiger after a first-Tiger assignment (no double/missing Tiger)")


func test_assign_first_tiger_reassigns_correctly_when_a_different_peer_is_chosen() -> void:
	var players: Node = _build_players_root()
	var gm: Node = _make_game_manager(players)

	var p1: CharacterBody3D = _spawn_player(players, "1", ROLE_TIGER, Vector3.ZERO) # already the Tiger
	var p2: CharacterBody3D = _spawn_player(players, "2", ROLE_OUTER, Vector3.ZERO)

	# A fresh assignment naming the OTHER peer must move the Tiger role onto the
	# newly-resolved node and demote the previously-Tiger node -- proving the
	# handler resolves the broadcast's tiger_id, not whatever was Tiger before.
	gm.assign_first_tiger(2)

	assert_eq(p2.role, ROLE_TIGER, "assign_first_tiger(2) must crown Players/2")
	assert_eq(p1.role, ROLE_OUTER, "the previously-Tiger Players/1 must be demoted to Outer by the same resolution pass")
