extends GutTest
## Unit tests for networking/ArenaBarrierRules.gd -- the Start-Match readiness-
## barrier GRACE-RELEASE decision (TK-P2-30: extend the grace for a healthy-but-
## slow/backgrounded peer instead of force-disconnecting it).
##
## Only the pure decision logic is tested here (node-independent, no live
## peers/RPC/Timer node) -- same "pure static helper" testability split every
## other decision-logic file in this codebase follows (see
## tests/test_round_rules.gd, tests/test_safe_circle.gd, tests/test_stagger_rules.gd).
## networking/PlayerSpawner.gd's own host-only wiring (the reused ArenaReadyGrace
## Timer, the NetworkManager.get_connected_peer_ids() query, the actual
## disconnect_peer() + barrier spawn) needs a live multiplayer server context and
## a TestArena scene tree, and is exercised by the headless slow-join net probe
## (tests/net/run_spawn_probe_slowjoin.sh) + a human 2-instance pass, not GUT --
## same scope line every other Rules test in this repo draws.

const ArenaBarrierRulesScript := preload("res://networking/ArenaBarrierRules.gd")

const EXTEND := ArenaBarrierRulesScript.GraceAction.EXTEND
const RELEASE := ArenaBarrierRulesScript.GraceAction.RELEASE

const MAX_EXT := 3


func _decide(still_unready: Array, connected_ids: Array, extensions_used: int) -> int:
	return ArenaBarrierRulesScript.decide_grace_action(
		still_unready, connected_ids, extensions_used, MAX_EXT)


# --- the core fix: a still-connected slow peer is EXTENDED, not killed ---------

func test_extend_when_the_lone_unready_peer_is_still_connected() -> void:
	# The exact TK-P2-30 case: one expected peer has not sent _rpc_arena_ready
	# yet, but it is still connected at the ENet layer (alive, just slow /
	# backgrounded). We have budget left -> EXTEND, do NOT force-disconnect it.
	assert_eq(_decide([2], [2], 0), EXTEND,
		"a healthy-but-slow peer (still connected) with budget left must be granted more grace, not kicked")


func test_extend_when_at_least_one_of_several_unready_peers_is_still_connected() -> void:
	# 2 and 3 are still unready; 3 dropped off the transport but 2 is still
	# connected -> at least one live laggard -> EXTEND (hold the barrier).
	assert_eq(_decide([2, 3], [2], 1), EXTEND)


func test_extend_is_granted_up_to_but_not_past_the_cap() -> void:
	# At the last allowed extension index we still extend...
	assert_eq(_decide([2], [2], MAX_EXT - 1), EXTEND,
		"the final extension within budget must still be granted")


# --- the deadlock-protection fallback: RELEASE cases ---------------------------

func test_release_when_extension_budget_is_exhausted_even_if_still_connected() -> void:
	# A peer that is STILL connected but has never readied across the entire
	# extension budget is treated as genuinely wedged (ENet alive, game thread
	# stuck) -> RELEASE (fall back to the original force-disconnect + spawn), so
	# one hung peer can never hold the match hostage forever.
	assert_eq(_decide([2], [2], MAX_EXT), RELEASE,
		"a still-connected peer that burned the whole extension budget must stop blocking the match")


func test_release_when_the_only_unready_peer_is_no_longer_connected() -> void:
	# 2 is unready AND no longer in the connected set -> no live evidence to wait
	# on -> RELEASE now (peer_disconnected pruning normally handles this; we do
	# not extend on a peer that is provably gone).
	assert_eq(_decide([2], [], 0), RELEASE)


func test_release_when_all_unready_peers_are_gone_even_with_budget_left() -> void:
	assert_eq(_decide([2, 3], [99], 0), RELEASE,
		"none of the still-unready peers are connected -> nothing alive to wait for -> release")


func test_release_when_there_is_nobody_left_to_wait_on() -> void:
	# Empty still_unready == every expected peer is ready (or was pruned) ->
	# RELEASE (the caller then does the host-only / all-ready spawn).
	assert_eq(_decide([], [2, 3], 0), RELEASE)


func test_release_when_nobody_unready_and_no_one_connected() -> void:
	assert_eq(_decide([], [], 0), RELEASE)


# --- boundary / robustness ----------------------------------------------------

func test_budget_boundary_is_inclusive_release_at_exactly_max() -> void:
	# extensions_used == max_extensions is the first index that must RELEASE
	# (>=, so we never grant a (max+1)-th extension).
	assert_eq(_decide([2], [2], MAX_EXT), RELEASE)
	assert_eq(_decide([2], [2], MAX_EXT + 5), RELEASE,
		"any count at or past the cap releases -- never loops forever")


func test_zero_max_extensions_means_original_behavior_immediate_release() -> void:
	# With a cap of 0, the very first grace elapse releases (i.e. the pre-TK-P2-30
	# force-disconnect-then-spawn behavior) even for a still-connected peer --
	# proves the extension is fully gated by the cap and this is a superset of the
	# old behavior, recoverable by config.
	assert_eq(ArenaBarrierRulesScript.decide_grace_action([2], [2], 0, 0), RELEASE)


func test_connected_ids_may_legitimately_contain_ids_not_in_unready() -> void:
	# connected_ids is the full peer roster (ready + unready); an id that is
	# connected AND ready simply is not in still_unready. Only a still-unready id
	# being connected triggers EXTEND.
	assert_eq(_decide([3], [2, 3], 0), EXTEND,
		"3 is unready and connected -> extend (2 being connected+ready is irrelevant)")
	assert_eq(_decide([3], [2], 0), RELEASE,
		"3 is unready but only the ready peer 2 is connected -> nothing alive to wait for -> release")
