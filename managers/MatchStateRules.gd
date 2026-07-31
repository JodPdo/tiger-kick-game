class_name MatchStateRules
## Pure, node-independent decision logic for the match-level state machine
## (TK-P2-15, gameplay-engineer): WaitingRoom -> Countdown -> Playing ->
## MatchEnd -> (back to) WaitingRoom. Same "pure static helper, thin caller"
## split every other state-transition file in this codebase already follows
## (see characters/RoleRules.gd's own fail-closed role-value guard -- this
## file's closest sibling in shape -- and managers/RoundRules.gd /
## managers/TagSequenceRules.gd for the wider "pure logic here, live host-only
## shell on the matching manager" convention).
##
## SCOPE / ARCHITECTURE NOTE (see managers/GameManager.gd's own class doc,
## "TK-P2-15 MATCH STATE MACHINE" section, for the full decision writeup):
## WAITING_ROOM here is a NOMINAL state as far as any live GameManager node
## is concerned. The actual pre-arena Waiting Room screen is a wholly
## separate scene (ui/WaitingRoom.gd/.tscn) that GameManager -- a node that
## only ever exists inside world/TestArena.tscn -- never runs during. The
## real WaitingRoom -> Countdown transition already happens, host-
## authoritatively and synced across every peer, via
## ui/WaitingRoom.gd's existing `_rpc_start_match()` call_local scene-switch
## broadcast (TK-P2-13) -- by the time a GameManager node exists at all, that
## edge has already fired. GameManager's own `match_state` var starts at
## WAITING_ROOM purely as a symbolic "we just came from there" starting
## value, then transitions to COUNTDOWN once GameManager confirms every
## expected Player has spawned into the arena. MATCH_END -> WAITING_ROOM is
## symmetric: GameManager broadcasts MATCH_END, then broadcasts a scene
## switch back to ui/WaitingRoom.tscn (mirroring world/TestArena.gd's own
## existing change_scene_to_file "return to menu" pattern), which frees the
## whole arena scene -- GameManager itself included -- so that last edge
## exists here purely to keep this transition table complete and
## self-documenting, not because live code ever reads
## `match_state == WAITING_ROOM` off a running GameManager instance.

enum State {
	WAITING_ROOM,
	COUNTDOWN,
	PLAYING,
	MATCH_END,
}

## Human-readable state names for log lines (index matches the enum order
## above) -- GameManager logs `state_name(new_state)`, never the raw int, so
## log lines stay readable without needing this file open side by side.
const STATE_NAMES: Array[String] = ["WAITING_ROOM", "COUNTDOWN", "PLAYING", "MATCH_END"]

## The single forward loop this match state machine ever follows -- a flat
## Dictionary (state -> next state), not a general graph, since every state
## here has exactly ONE legal next state. This SM is intentionally a strict
## cycle with no shortcuts (e.g. no COUNTDOWN -> MATCH_END, no skipping
## Playing) and no reverse edges other than the one closing MATCH_END ->
## WAITING_ROOM link.
const _NEXT_STATE: Dictionary = {
	State.WAITING_ROOM: State.COUNTDOWN,
	State.COUNTDOWN: State.PLAYING,
	State.PLAYING: State.MATCH_END,
	State.MATCH_END: State.WAITING_ROOM,
}


## True iff `to` is a legal next state from `from` -- either the one forward
## edge this SM's strict cycle allows, or `from == to` (an idempotent
## re-broadcast/re-application of the CURRENT state is treated as a no-op,
## not a violation -- mirrors how a re-applied role is a no-op elsewhere in
## this codebase, e.g. Player.set_role() design doc §5 step 3). Fails CLOSED
## (returns false) for anything else, including a skip-ahead (e.g.
## COUNTDOWN -> MATCH_END) or any other out-of-order jump -- same
## fail-closed posture characters/RoleRules.gd's own guard uses.
static func is_valid_transition(from: State, to: State) -> bool:
	if from == to:
		return true
	return _NEXT_STATE.get(from, -1) == to


## Human-readable name for `state`, for GameManager's own log lines. Returns
## an "UNKNOWN(n)" placeholder rather than crashing/indexing out of bounds if
## ever handed a value outside the enum (defensive -- state arrives over an
## RPC int parameter on the wire, not a typed enum, so a malformed/future
## value must not crash a receiving peer).
static func state_name(state: int) -> String:
	if state >= 0 and state < STATE_NAMES.size():
		return STATE_NAMES[state]
	return "UNKNOWN(%d)" % state
