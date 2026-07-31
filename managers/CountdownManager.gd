extends Node
## CountdownManager (TK-P2-14, gameplay-engineer) -- scene-local (NOT an
## autoload) host-authoritative shell that owns the pre-match Countdown timer
## (synced "3 -> 2 -> 1", ending at 0) and broadcasts the displayed number to
## every peer. Same "pure static helper (CountdownRules.gd) + thin host-only
## shell (this file)" split as managers/RoundManager.gd/RoundRules.gd -- see
## RoundManager.gd's own class doc for the split rationale this file reuses
## verbatim.
##
## HOST-AUTHORITATIVE THROUGHOUT (CLAUDE.md server authority / this card's own
## DoD -- "client ไม่นับเอง กัน desync"): the elapsed-time accumulation and the
## whole-number tick decision only ever run on multiplayer.is_server() (see
## _physics_process()'s own guard). WHY clients never count down locally: if
## every peer ran its own local timer from countdown_duration_sec down to 0,
## ordinary per-machine frame-time drift (plus whichever peer's scene finished
## loading a frame later than another's) would have different machines
## displaying different numbers at the same wall-clock moment, and -- worse --
## reaching 0 (and therefore being ready for Playing) at slightly different
## times. The HOST alone decides which whole-number tick is currently showing
## and broadcasts it via `tick_changed`, an
## @rpc("authority", "call_local", "reliable") -- same contract as
## managers/GameManager.gd's apply_role_switch/assign_first_tiger/
## managers/RoundManager.gd's start_new_round -- so the host's own copy also
## displays the result instead of being special-cased.
##
## TRIGGER (deliberately NOT self-starting, unlike RoundManager's own
## role_changed auto-watch in _ready()): a Countdown only makes sense once
## GameManager's match state machine (TK-P2-15) decides Playing should begin
## -- e.g. once every expected Player has actually spawned into the arena.
## GameManager calls start_countdown() exactly once, host-only, from its own
## match-ready trigger (see managers/GameManager.gd's "TK-P2-15 MATCH STATE
## MACHINE" doc section for the exact call site) -- this file has no opinion
## about WHEN that is, only HOW to count down once told to.
##
## PLACEMENT: a child of world/TestArena.tscn's root, sibling of
## GameManager/RoundManager/PlayerSpawner/Players -- mirrors every other
## manager's own scene-local (not autoload) placement precedent (see
## RoundManager.gd's own class doc). GameManager reaches this the same way it
## reaches _players_root: a relative NodePath lookup to its own sibling.
##
## WHAT THIS BROADCASTS (and what it deliberately does NOT do): `tick_changed`
## carries only the current whole-number display value (3, 2, 1, 0) -- no HUD
## exists yet to render it (polish-agent/Phase-4 territory, same "log + hook
## comment, no visual yet" shape as GameManager._run_sequence()'s own TK-P4-0x
## stub steps), so today this only logs. `finished` is a LOCAL, host-only
## signal (never broadcast over RPC itself) -- GameManager's own host-only
## handler is the one thing that needs to react to "countdown is over" (by
## broadcasting the match state transition into PLAYING), so there is nothing
## for a non-host peer to independently listen for here; every peer instead
## simply observes the state transition GameManager itself broadcasts.

signal finished

## Design-owned placeholder tunable ("synced 3->2->1" per the card note) --
## @export per CLAUDE.md's "expose design-owned tunables, never hard-code"
## rule, same placeholder-pending-designer-lock posture every other Phase
## 2/3 tunable in this codebase uses (see managers/RoundManager.gd's own
## round_duration_sec doc). 3.0s matches the literal "3 -> 2 -> 1" the card
## title specifies.
@export var countdown_duration_sec: float = 3.0

## HOST-ONLY. True once start_countdown() has been called and the countdown
## has not yet finished -- guards _physics_process() from ticking before
## triggered, and start_countdown() itself from being re-entered mid-count
## (this card's scope has no restart/cancel semantics; a second call while
## already running is a no-op).
var _running: bool = false

## HOST-ONLY. Seconds elapsed since start_countdown() was called.
var _elapsed_sec: float = 0.0

## HOST-ONLY. The last whole-number tick value actually broadcast -- lets
## _physics_process() only fire tick_changed on a real CHANGE (once per
## second-boundary crossed), not every physics frame; -1 (never a real
## display value) so the very first tick (e.g. "3") always broadcasts even
## though the "previous" value technically does not exist yet.
var _last_broadcast_tick: int = -1


## HOST-ONLY entry point (see class doc TRIGGER). Starts (or, if already
## running, no-ops) the countdown and immediately broadcasts the first tick
## so every peer shows the starting number without waiting a physics frame.
func start_countdown() -> void:
	assert(multiplayer.is_server(), "CountdownManager.start_countdown must only ever run on the host (mirrors every other host-only entry point in this codebase's manager files)")
	if _running:
		return
	_elapsed_sec = 0.0
	_last_broadcast_tick = -1
	_running = true
	GameLog.info("[COUNTDOWN] starting (%.1fs)" % countdown_duration_sec)
	_broadcast_current_tick_if_changed()


## HOST-ONLY: accumulates elapsed time and re-checks the current tick + the
## countdown-end condition every physics tick, mirroring
## RoundManager._physics_process()'s own is_server()+running guard shape.
func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not _running:
		return

	_elapsed_sec += delta
	_broadcast_current_tick_if_changed()

	if CountdownRules.is_countdown_complete(_elapsed_sec, countdown_duration_sec):
		_running = false
		GameLog.info("[COUNTDOWN] complete")
		finished.emit()


func _broadcast_current_tick_if_changed() -> void:
	var tick: int = CountdownRules.display_number(_elapsed_sec, countdown_duration_sec)
	if tick == _last_broadcast_tick:
		return
	_last_broadcast_tick = tick
	tick_changed.rpc(tick)


## Host -> everyone (call_local so the host's own copy also runs this instead
## of being special-cased -- same pattern as every other broadcast RPC in
## this codebase's manager files). TK-P4/polish HOOK: this is the one place a
## future HUD countdown number should subscribe (e.g. by re-emitting this as
## a UI-facing signal) -- no HUD exists yet, so this only logs today.
@rpc("authority", "call_local", "reliable")
func tick_changed(value: int) -> void:
	GameLog.info("[COUNTDOWN] %d" % value)
