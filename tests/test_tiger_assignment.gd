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

const FOUR_PEERS: Array = [1, 2, 3, 4]  # host id 1 + three clients

var _rng: RandomNumberGenerator


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
