extends GutTest
## Unit tests for networking/DedicatedHostRules.gd -- the TEST-HARNESS-ONLY
## dedicated-host self-spawn decision (TK-P3-10): should the host spawn a Player
## for its OWN peer id?
##
## Only the pure decision logic is tested here (node-independent, no live
## peer/RPC/MultiplayerSpawner) -- same "pure static helper" testability split
## every other decision-logic file in this codebase follows (see
## tests/test_arena_barrier_rules.gd, tests/test_round_rules.gd,
## tests/test_tiger_assignment.gd). networking/PlayerSpawner.gd's own host-only
## wiring (the actual spawn() skip in _do_initial_barrier_spawn(), reading
## NetworkManager.dedicated_host_no_self_spawn) needs a live server + a TestArena
## scene tree and is exercised by the headless net probes + the bot harness
## (tests/net/), not GUT -- same scope line every other Rules test in this repo
## draws.
##
## The load-bearing INVARIANT these assertions defend: the flag is a strict
## no-op unless BOTH the opt-in is set AND we are the server, so no real
## shipped-game session (flag false) and no client (not server) can ever have a
## body suppressed -- only a deliberately-opted-in dedicated host skips its own.

const DedicatedHostRulesScript := preload("res://networking/DedicatedHostRules.gd")


func _spawns_own(is_server: bool, flag: bool) -> bool:
	return DedicatedHostRulesScript.host_spawns_own_player(is_server, flag)


# --- the ONLY case that skips: opted-in dedicated host ------------------------

func test_dedicated_host_with_flag_set_does_not_spawn_its_own_player() -> void:
	# The whole point of TK-P3-10: server + flag => skip the host's own body so
	# it can never be picked/tagged as Tiger and softlock a match.
	assert_false(_spawns_own(true, true),
		"a server that opted into dedicated-host mode must NOT spawn its own Player")


# --- every other combination MUST still spawn (strict no-op guarantee) --------

func test_real_host_default_flag_still_spawns_its_own_player() -> void:
	# The shipped game: a real human clicks Host, flag defaults false -> they
	# always get their own Player, exactly as before this card.
	assert_true(_spawns_own(true, false),
		"a normal host (flag off) must always spawn its own Player -- this card is a strict no-op for real sessions")


func test_client_never_has_its_body_suppressed_even_if_flag_somehow_true() -> void:
	# Defense in depth: the flag is host-authoritative session config, but even
	# if a non-server ever evaluated this, it must NOT be treated as a skip --
	# only the SERVER's own id is the dedicated-host body.
	assert_true(_spawns_own(false, true),
		"a non-server must never skip a spawn on account of the dedicated-host flag")


func test_client_with_flag_off_spawns_normally() -> void:
	assert_true(_spawns_own(false, false),
		"the ordinary non-server, flag-off case spawns normally")


# --- truth-table completeness / robustness ------------------------------------

func test_skip_requires_both_conditions_true() -> void:
	# Exhaustive 2x2: exactly ONE of the four combinations returns "skip".
	var skip_count: int = 0
	for is_server in [true, false]:
		for flag in [true, false]:
			if not _spawns_own(is_server, flag):
				skip_count += 1
	assert_eq(skip_count, 1,
		"exactly one of the four (is_server, flag) combinations may suppress the host's own spawn")
