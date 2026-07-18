class_name ArenaBarrierRules
## Pure, node-independent decision logic for the Start-Match readiness-barrier
## GRACE RELEASE (TK-P2-30) -- same "pure static helper, thin host-only shell"
## split every other decision-logic file in this codebase follows (see
## managers/RoundRules.gd, managers/TagSequenceRules.gd, managers/TigerSelector.gd,
## characters/RoleRules.gd, characters/components/SafeCircleRules.gd,
## characters/components/StaggerRules.gd). The live host-only shell (the
## Timer node, NetworkManager peer queries, the force-disconnect + spawn) lives
## on networking/PlayerSpawner.gd's _on_ready_grace_timeout() -- see that file's
## class doc for the full barrier picture.
##
## WHY THIS EXISTS (TK-P2-30, the "unfocused client force-disconnect" S2 bug):
## the original TK-P2-13 grace timer fired ONCE (ARENA_READY_GRACE_SEC, 8s) and
## then force-disconnected EVERY peer that had not yet announced arena readiness
## (_rpc_arena_ready). Root cause of the bug: when a client's OS window is
## unfocused/backgrounded during Start Match, the OS compositor + vsync throttle
## that occluded window's frame loop hard (down to a handful of fps, sometimes
## effectively paused while occluded). Godot drives BOTH scene-load completion
## AND the multiplayer poll/flush (which actually sends the queued reliable
## _rpc_arena_ready packet) from that same main loop, so a perfectly healthy but
## backgrounded client's readiness announcement can land WELL past 8s -- and the
## old timer killed it as if it had crashed. Observed live 2 of the last 5 test
## sessions, directly blocking the team's required human 2-instance passes.
##
## THE DECISION THIS ENCODES: at each grace elapse, a peer that is STILL
## CONNECTED at the ENet transport layer (present in multiplayer.get_peers()) is
## demonstrably NOT crashed -- its connection is alive, it is merely slow to load
## / throttled. Killing it is a false positive. So instead of force-disconnecting
## it we EXTEND the grace (keep the barrier held for everyone -- we must NOT spawn
## the ready peers and leave it behind, since spawning toward an absent peer is
## exactly the path-cache poison TK-P2-13's barrier exists to prevent), for a
## bounded number of extensions. Only once a peer has burned the WHOLE extension
## budget while STILL connected (genuinely wedged: ENet alive but its game thread
## never progresses) OR is no longer connected at all do we fall back to the
## original TK-P2-13 behavior (force-disconnect the still-unready + release), so
## one truly-hung peer can still never deadlock the match forever.
##
## Server authority is untouched: the HOST alone decides who is in the barrier
## and when it releases (it just waits longer, and only on transport-level
## evidence the peer is alive) -- a client can neither force an early release nor
## keep itself in past the hard cap.

enum GraceAction {
	EXTEND,   ## keep the barrier held and re-arm the grace timer for another interval
	RELEASE,  ## give up waiting: force-disconnect whoever is still unready, then spawn
}


## Decide what to do when a grace window elapses with `still_unready` peers not
## yet ready. Pure function of its inputs -- no engine/node/RPC state:
##   - still_unready:   peer ids the host is still waiting on (expected-but-not-ready).
##   - connected_ids:   peer ids currently connected at the ENet layer
##                      (NetworkManager.get_connected_peer_ids() == multiplayer.get_peers()).
##   - extensions_used: how many grace extensions have already been granted this barrier.
##   - max_extensions:  the hard cap on extensions before we give up on a still-connected peer.
##
## Returns EXTEND only when there is budget left AND at least one still-unready
## peer is still connected (alive, just slow). Returns RELEASE when there is
## nobody left to wait on, the budget is exhausted (a still-connected peer that
## never readied across the whole budget is treated as genuinely wedged), or
## every still-unready peer has already dropped off the transport (nothing to
## wait for -- the normal peer_disconnected pruning will have handled them, but
## we release rather than extend on no live evidence).
static func decide_grace_action(
		still_unready: Array,
		connected_ids: Array,
		extensions_used: int,
		max_extensions: int) -> GraceAction:
	if still_unready.is_empty():
		return GraceAction.RELEASE
	if extensions_used >= max_extensions:
		return GraceAction.RELEASE
	for id in still_unready:
		if connected_ids.has(id):
			return GraceAction.EXTEND
	return GraceAction.RELEASE
