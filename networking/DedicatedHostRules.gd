class_name DedicatedHostRules
## Pure, node-independent decision for the TEST-HARNESS-ONLY dedicated-host
## opt-in (TK-P3-10) -- same "pure static helper, thin host-only shell" split
## every other decision-logic file in this codebase follows (see
## networking/ArenaBarrierRules.gd, managers/RoundRules.gd,
## managers/TigerSelector.gd, characters/RoleRules.gd,
## characters/components/StaggerRules.gd). The live host-only shell -- the actual
## spawn() call it gates -- lives on networking/PlayerSpawner.gd's
## _do_initial_barrier_spawn(); the flag it reads lives on the NetworkManager
## autoload (NetworkManager.dedicated_host_no_self_spawn -- see that var's doc
## for WHY the autoload, not the scene-local spawner, is its home).
##
## THE DECISION THIS ENCODES: should the host spawn a Player for its OWN peer id?
## Normally YES (a real human clicking Host always wants their own body). The one
## exception is a dedicated host running under the test harness: when the opt-in
## flag is set AND this instance is the server, the host spawns NOTHING for
## itself, so it can never be selected/tagged as Tiger and softlock a match.
##
## Crucially this ONLY ever affects the host's OWN self-spawn -- every other
## peer's spawn is decided elsewhere and is untouched. It defaults to spawning
## the host (flag false) so the shipped game is a strict no-op, and only skips
## when BOTH conditions hold, so it can never accidentally suppress a client's
## body (a client is not the server) or fire when nobody opted in.
static func host_spawns_own_player(is_server: bool, dedicated_host_no_self_spawn: bool) -> bool:
	return not (is_server and dedicated_host_no_self_spawn)
