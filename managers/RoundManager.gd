extends Node
## RoundManager (TK-P2-07, gameplay-engineer) -- scene-local (NOT an
## autoload) host-authoritative coordinator that owns the ROUND timer and the
## timer-driven Round Restart (re-pick a new Tiger when time runs out with
## no successful Tag). See Tiger_Kick_Project_Docs/02_Technical/TDD.pdf
## section 7 Round Flow and GDD section 2.2 core loop step 6.
##
## SCOPE: a round here is ONE Tiger's timed reign inside a single match's
## Playing state (see managers/GameManager.gd's own class doc for the same
## framing). This file does NOT implement the full match state machine
## (WaitingRoom -> Countdown -> Playing -> MatchEnd, TK-P2-15, a separate
## still-todo card) -- no global match-state enum is introduced here, no
## scoring/win-lose/ranking exists (GDD 5: none of that exists in
## Prototype). It also does NOT implement an alternate round-end condition
## (kick count, etc.) -- GDD 9 Open Questions leaves "which end condition is
## most fun" UNRESOLVED, deferred to Phase 3 (TK-P3-04); this file
## implements ONLY the timer baseline the GDD's core loop already commits to.
##
## PLACEMENT: a child of world/TestArena.tscn's root, sibling of
## Players/PlayerSpawner/GameManager -- mirrors GameManager.gd's own
## scene-local (not autoload) placement precedent (see that file's class
## doc). Reached the same way GameManager is: TestArena -> RoundManager.
##
## SIBLING ORDER MATTERS (real ordering hazard found while building this
## card, not just theoretical): in world/TestArena.tscn this node is placed
## BEFORE GameManager (right after PlayerSpawner), so RoundManager._ready()
## always runs BEFORE GameManager._ready(). Godot readies siblings in scene
## child order, and GameManager._ready() has a STANDALONE/OFFLINE-BOOT path
## (see that file's own doc) where it calls _try_assign_first_tiger()
## SYNCHRONOUSLY, inline, inside its own _ready() -- which broadcasts
## assign_first_tiger.rpc(...) (call_local) and therefore calls
## Player.set_role() on every already-spawned Player BEFORE returning. If
## RoundManager's own _ready() (which is what wires up the role_changed
## watch below) ran AFTER that, it would silently miss the very first
## Tiger's role_changed emission and the round-1 timer would never start.
## Placing RoundManager earlier guarantees its watch is wired before
## GameManager can possibly emit that first role_changed, regardless of
## which boot path (standalone vs staggered-connect vs Waiting-Room barrier)
## actually fires.
##
## ROUND-START / ROUND-RESET TRIGGER (per the card note: reuse or hook off
## GameManager's existing interim trigger rather than inventing a new one):
## rather than GameManager exposing a brand-new "first tiger assigned"/"tag
## sequence completed" signal (which would mean touching a reviewed,
## human-tested, live-RPC file for this card), RoundManager instead
## subscribes to the ALREADY-EXISTING characters/Player.gd role_changed
## signal (the exact same hook TK-P2-05's CameraComponent already subscribes
## to for its own FP/TP swap -- see that file's own doc) on every currently-
## spawned AND every future-spawned Player. Whenever ANY Player's role
## becomes Tiger -- whether that is GameManager's interim first-Tiger
## broadcast (TK-P2-09), a Tag Sequence's role swap (TK-P2-03's
## apply_role_switch), or this file's OWN timeout-driven start_new_round()
## broadcast below -- the round timer resets to 0 and (re)starts. This is a
## strict superset of "the round-loop RE-ROLL trigger (next round -> new
## Tiger) is TK-P2-07's job" that GameManager.gd's own doc calls out: this
## file both re-triggers the pick (timeout path) AND resets the clock for
## every Tiger change regardless of cause (timeout OR tag), which is what
## "one Tiger's TIMED reign" actually requires. Zero lines of
## GameManager.gd are touched by this card.
##
## PURE LOGIC lives in managers/RoundRules.gd (the elapsed-vs-duration
## comparison) -- this file is a thin host-only shell around it, same split
## as every other host_validate()/GameManager-shaped file in this codebase
## (KickAbility/KickRules, TagAbility/TagRules, TigerSelector,
## GameManager/TagSequenceRules).
##
## HOST-AUTHORITATIVE THROUGHOUT (CLAUDE.md server authority): the elapsed-
## time accumulation, the timeout decision, and the re-pick all only ever run
## on multiplayer.is_server() (see _ready()'s own guard, mirrors
## GameManager._ready()'s identical gate). The one broadcast every peer must
## OBSERVE (a timer-driven Tiger change) uses start_new_round, an
## @rpc("authority", "call_local", "reliable") -- same contract as
## GameManager.apply_role_switch/assign_first_tiger, so the host's own copy
## also applies the result instead of being special-cased.
##
## TIGER RE-PICK: reuses managers/TigerSelector.pick_first_tiger() exactly as
## the card's brief calls out ("reusable for re-rolling the Tiger each
## round") -- no generalization was needed; that function already accepts an
## avoid id for anti-repeat (pre-existing, tested by
## tests/test_tiger_assignment.gd's test_anti_repeat_avoids_previous_tiger),
## which this file passes the JUST-EXPIRED Tiger's id into, so a timed-out
## round does not (when at least 2 players are available) immediately hand
## the reign right back to the same Tiger who just failed to catch anyone --
## consistent with "start a NEW round" rather than "restart the same one".
## DESIGNER RULING (Change Log [0.46]): anti-repeat ON at timeout is APPROVED
## as a Phase 2 placeholder -- GDD 9 leaves the whole round-end feel open for
## Phase 3 tuning; TK-P3-04 may revisit (uniform-random or a weighted
## not-recently-Tiger bias) once real playtesting data exists.
##
## TK-BUG-P3-02/03 (gameplay-engineer, bug fix -- NEW, deliberate GameManager
## coupling): a human's CASE E bot-harness run (2026-07-26) found that a Tag
## Sequence could start-and-complete a role swap AFTER managers/GameManager.gd's
## own match_state had already flipped to MATCH_END, plus a related off-by-one
## where the FINAL round of a match got zero play time. Both bugs share one
## root cause: nothing anywhere ever asked "is a new round still allowed to
## start" BEFORE actually starting one. This file's own timeout-driven
## round-restart (_on_round_timeout() below) has EXACTLY the same exposure as
## the Tag Sequence did -- if the round timer expires during GameManager's
## match_end_grace_sec window (entirely possible with a short round_duration_sec
## test session, or even in ordinary play near a match's natural end), this
## file would broadcast start_new_round() and create a round GameManager never
## agreed to. Per this file's own longstanding "reuse the existing
## role_changed hook rather than touch a proven, reviewed, live-RPC file"
## discipline (see "ROUND-START / ROUND-RESET TRIGGER" above) -- that
## discipline was ABOUT AVOIDING UNNECESSARY coupling, not avoiding NECESSARY
## coupling. This bug is precisely the scenario RoundManager's previous ZERO
## GameManager-awareness allowed through, so a NEW, deliberate, MINIMAL,
## READ-ONLY coupling is warranted here (recorded per this repo's own
## architecture-decision-adjacent discipline, mirroring managers/GameManager.gd's
## own "AUTOLOAD-VS-SCENE-LOCAL DECISION" precedent for a "decide deliberately,
## don't silently avoid or silently add" call): this file now reads (never
## writes) GameManager's `is_match_playing()`/`try_reserve_next_round()`
## accessors via a new `_game_manager` sibling lookup (see below), exactly the
## same "reach a sibling via a relative NodePath" pattern `_players_root`
## already uses. Nothing here calls back INTO GameManager beyond those two
## read-oriented accessors (try_reserve_next_round() has the SAME
## may-trigger-_end_match()-as-a-side-effect shape whichever caller -- Tag or
## timeout -- happens to discover the cap has been reached); RoundManager still
## owns 100% of its own timer/re-pick logic and GameManager still owns 100% of
## match_state -- this is a read-only DEPENDENCY, not a merge of the two
## managers' scopes.

## Design-owned tunable (Game_Balance.md "Round length: 3-5 minutes", sourced
## "GDD (yet unset)" -- exact value NOT yet locked by design). @export per
## CLAUDE.md's "expose design-owned tunables, never hard-code" rule, same
## placeholder-pending-designer-lock posture GameManager.gd's own
## throw_stub_sec/transform_stub_sec use. 240.0s (4 min) sits in the middle
## of the GDD's stated 3-5 min range as a sensible Prototype placeholder.
@export var round_duration_sec: float = 240.0

## Cached "Players" root (sibling of this node under TestArena's root) --
## same relative-lookup pattern as managers/GameManager.gd's own
## _players_root.
@onready var _players_root: Node = get_node("../Players")

## Cached "GameManager" sibling (TK-BUG-P3-02/03, see class doc for the
## coupling reasoning) -- same relative-lookup pattern as _players_root above.
## SIBLING ORDER NOTE: this file is placed BEFORE GameManager in
## world/TestArena.tscn (see class doc "SIBLING ORDER MATTERS"), but that only
## constrains _ready() EXECUTION order, not node EXISTENCE -- by the time
## ANY sibling's _ready() runs, the whole scene's node tree already exists
## (a single scene instantiation adds every child synchronously before any of
## their _ready() calls fire), so this @onready get_node() resolves safely
## regardless of sibling order, the same way GameManager's own @onready
## `_countdown_manager` lookup already relies on.
@onready var _game_manager: Node = get_node("../GameManager")

## HOST-ONLY. Seconds elapsed in the CURRENT Tiger's reign. Reset to 0.0
## every time any Player's role becomes Tiger (see
## _on_any_player_role_changed()).
var _elapsed_sec: float = 0.0

## HOST-ONLY. True once a round is actually underway (at least one Tiger has
## ever been assigned this session) -- guards _physics_process() from
## ticking before the interim first-Tiger trigger has fired at all, and
## again if a timeout ever finds zero spawned Players to hand the reign to
## (see _on_round_timeout()).
var _round_running: bool = false

## HOST-ONLY. The current Tiger's peer id, or TigerSelector.NO_ID if no
## round is running yet. Used both as the anti-repeat avoid id and as the
## "who do we flip back to Outer" id when this file's own timer fires
## start_new_round().
var _current_tiger_id: int = TigerSelector.NO_ID

## HOST-ONLY. Single RandomNumberGenerator instance for this file's own
## timer-driven re-picks, created and randomize()'d EXACTLY ONCE, host-only
## -- same mandatory-RNG-ownership rule as GameManager._tiger_rng (clients
## must NEVER pick their own Tiger, or every machine could resolve a
## different "random" winner -> S1 desync).
var _round_rng: RandomNumberGenerator = null

## HOST-ONLY setup: wires the role_changed watch (see class doc) onto every
## Player already spawned at this moment (the standalone/offline-boot case,
## where PlayerSpawner -- an earlier sibling -- already spawned everyone
## synchronously before this node's own _ready() runs) plus every Player
## spawned later. Never runs any of this on a client -- clients only ever
## receive start_new_round's broadcast below, they never decide or track
## anything here.
func _ready() -> void:
	if not multiplayer.is_server():
		return

	_round_rng = RandomNumberGenerator.new()
	_round_rng.randomize() # ONE call, host-only -- see _round_rng doc above.

	for child in _players_root.get_children():
		_watch_player_role(child)
	_players_root.child_entered_tree.connect(_on_player_spawned)


## Fires whenever a new Player enters _players_root -- wires the SAME
## role_changed watch a spawn-time-present Player already got in _ready().
## No call_deferred() needed here (unlike GameManager's own
## child_entered_tree handler): connecting to a signal only needs the
## script's declared members to exist, which they do the instant the script
## is attached (well before add_child()/_enter_tree()/_ready() ever run) --
## nothing here depends on that Player's own @onready state being resolved
## yet.
func _on_player_spawned(node: Node) -> void:
	_watch_player_role(node)


## Connects player's role_changed signal to this file's handler. A given
## Player node is only ever added to _players_root once during its lifetime
## (PlayerSpawner queue_free()s on disconnect; any reconnect gets a brand
## new instance/node), so no double-connect guard is needed here.
func _watch_player_role(player: Node) -> void:
	player.role_changed.connect(_on_any_player_role_changed.bind(player))


## The actual round-start / round-reset trigger (see class doc). Runs for
## EVERY role_changed emission (Outer->Tiger and Tiger->Outer alike, since
## set_role() is called on both the old and new Tiger during any swap) but
## only acts on the transition INTO Tiger -- that is the one moment that
## means "a Tiger's timed reign just began", regardless of whether the cause
## was GameManager's first-Tiger assignment, a completed Tag Sequence, or
## this file's own timeout-driven start_new_round() below.
func _on_any_player_role_changed(new_role: StringName, player: Node) -> void:
	if new_role != RoleRules.TIGER:
		return
	_current_tiger_id = player.name.to_int()
	_elapsed_sec = 0.0
	_round_running = true
	GameLog.info("[ROUND] round (re)started: tiger=%d, duration=%.1fs" % [_current_tiger_id, round_duration_sec])


## HOST-ONLY: accumulates elapsed time for the current Tiger's reign and
## checks the round-end condition every physics tick. Mirrors
## GameManager._physics_process()'s own is_server() gate.
##
## TK-BUG-P3-02/03 fix: also stops ticking once GameManager reports the match
## is no longer PLAYING (see class doc for the coupling reasoning) -- without
## this, the round timer would keep accumulating (and could still time out)
## during GameManager's own match_end_grace_sec window, or before PLAYING even
## begins, and _on_round_timeout() would try to start a round GameManager
## never agreed to.
func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not _round_running:
		return
	if not _game_manager.is_match_playing():
		return

	_elapsed_sec += delta
	if RoundRules.has_round_timed_out(_elapsed_sec, round_duration_sec):
		_on_round_timeout()


## HOST-ONLY: the round-end-by-timer decision point (per the card: "Round
## Restart" per GDD section 2.2 step 6). Re-picks a Tiger among currently-
## spawned Players (anti-repeat avoiding the just-expired Tiger -- see class
## doc) and broadcasts the swap via start_new_round.rpc() below, same
## @rpc("authority", "call_local", "reliable") pattern as
## GameManager.apply_role_switch, so the host's own copy also applies the
## result instead of being special-cased.
func _on_round_timeout() -> void:
	if not _game_manager.try_reserve_next_round():
		# TK-BUG-P3-02/03: either the match ended out from under this timeout
		# (extremely unlikely given the _physics_process() gate above already
		# stops ticking once match_state leaves PLAYING, but checked here too
		# as the authoritative gate -- same "belt and suspenders" posture this
		# file's own start_new_round() reset-before-call_local comment already
		# uses) OR -- the actually-expected case -- this timeout IS the final
		# round (rounds_per_match) concluding: try_reserve_next_round() has
		# already triggered GameManager._end_match() as a side effect. Either
		# way, no new round starts here.
		GameLog.info("[ROUND] round timer expired but GameManager is not accepting a new round (match ending or already ended) -- not starting a new round")
		_round_running = false
		return

	var ids: Array = _current_player_ids()
	var new_tiger_id: int = TigerSelector.pick_first_tiger(ids, _round_rng, _current_tiger_id)
	if new_tiger_id == TigerSelector.NO_ID:
		# No spawned Players at all (e.g. everyone disconnected mid-round) --
		# nothing to hand the reign to. Stop ticking rather than re-log this
		# every physics frame; _on_any_player_role_changed() resumes the
		# round the moment a Tiger exists again (e.g. once GameManager or a
		# future reconnect flow assigns one).
		GameLog.error("[ROUND] round timer expired but no Players are spawned -- cannot start a new round; will resume once a Tiger exists again")
		_round_running = false
		return

	var old_tiger_id: int = _current_tiger_id
	GameLog.info("[ROUND] round timer expired (%.1fs) -- new tiger=%d (was %d)" % [round_duration_sec, new_tiger_id, old_tiger_id])
	# Reset now (belt-and-suspenders): start_new_round.rpc()'s call_local
	# execution below also runs Player.set_role() locally, which
	# re-triggers _on_any_player_role_changed() and resets these same
	# fields again -- this explicit reset does not depend on that ordering
	# to be correct.
	_elapsed_sec = 0.0
	start_new_round.rpc(old_tiger_id, new_tiger_id)


## HOST-ONLY: the peer ids of every Player CURRENTLY spawned under
## _players_root -- same Players/<id> naming-contract derivation as
## GameManager._current_player_ids() (TK-BUG-P1-01). Not shared via a common
## helper: this codebase's existing convention is each host-only manager
## keeps its own small derivation off its own _players_root reference (see
## GameManager.gd's own copy, TagDetectorComponent's own name.to_int()
## usage) rather than a shared utility -- managers/RosterHelper.gd is a
## DIFFERENT roster (the pre-spawn Waiting Room peer list), not this one
## (actually-spawned arena Players), so it is not reused here either.
func _current_player_ids() -> Array:
	var ids: Array = []
	for child in _players_root.get_children():
		ids.append(child.name.to_int())
	ids.sort()
	return ids


## Host -> everyone (design contract mirrors GameManager.apply_role_switch:
## call_local so the host's own copy also runs this instead of being
## special-cased). Flips exactly the two Players this round-restart
## concerns -- the just-expired Tiger back to Outer, the newly-picked one to
## Tiger -- rather than GameManager.assign_first_tiger's "re-confirm
## everyone" shape: no OTHER Player's role is touched by a timeout, so there
## is nothing to re-confirm for them. Unlike GameManager.apply_role_switch,
## this does NOT teleport the old Tiger outside the Safe Circle -- that
## placeholder exit is specifically Tag Sequence step 6 flavor ("you got
## caught and thrown out"); a round that simply timed out with nobody
## tagged has no such moment, and the old Tiger (now Outer) is already free
## to walk in/out of the circle like any other Outer per SafeCircleRules'
## own design ruling (it only ever confines the Tiger role).
@rpc("authority", "call_local", "reliable")
func start_new_round(old_tiger_id: int, new_tiger_id: int) -> void:
	var old_tiger: Node = _players_root.get_node_or_null(str(old_tiger_id))
	if old_tiger:
		old_tiger.set_role(RoleRules.OUTER)
	else:
		GameLog.error("[ROUND] start_new_round: old tiger Player %d not found (disconnected before the round timed out?) -- nothing to flip back" % old_tiger_id)

	var new_tiger: Node = _players_root.get_node_or_null(str(new_tiger_id))
	if new_tiger:
		new_tiger.set_role(RoleRules.TIGER)
	else:
		GameLog.error("[ROUND] start_new_round: new tiger Player %d not found (disconnected between the host's pick and this broadcast?)" % new_tiger_id)
