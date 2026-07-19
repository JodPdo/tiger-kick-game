extends Node
## GameManager (TK-P2-03, gameplay-engineer) -- scene-local (NOT an autoload)
## host-authoritative coordinator that owns ONLY the 7-step Tag Sequence and
## its "sequence active" lock. See
## Tiger_Kick_Project_Docs/02_Technical/Ability_System_Design.md section 5
## (Role-swap) and section 8 (ownership: "GameManager = owner of role + Tag
## Sequence 7 steps -- ability does not swallow match flow").
##
## PLACEMENT: a child of world/TestArena.tscn's root, sibling of
## Players/PlayerSpawner -- mirrors networking/PlayerSpawner.gd's own
## scene-local (not autoload) placement precedent (see that file's class
## doc). Reached from TagAbility via TagAbility._game_manager():
## Player -> Players -> TestArena -> GameManager.
##
## SCOPE (TK-P2-03 card note, flagged for architect placement review the
## same way TK-P2-02's sensor placement was): this node originally owned ONLY
## the Tag Sequence + its lock -- step 7 ("return to Playing") here still
## means exactly "clear this lock", nothing more, the Tag Sequence's own scope
## is unchanged. TK-P2-15 (see that section further down this doc) has since
## ADDED the full match-level state machine (WaitingRoom -> Countdown ->
## Playing -> MatchEnd) on top, so a global match-state enum now DOES exist on
## this file (`match_state`, backed by managers/MatchStateRules.gd) -- see the
## "TK-P2-15 (Match state machine, gameplay-engineer) ADDITION" doc section
## below for the full picture. Assigning the first Tiger (TK-P2-09) and the
## Role state machine itself (TK-P2-04, characters/RoleRules.gd) remain
## separate concerns this file only reacts to -- this file still does not
## decide who becomes Tiger on its own initiative outside of the Tag
## Sequence's own already-validated role swap and TK-P2-09's first-pick.
##
## Step 2 (throw-to-ground) and step 3 (transform-effect) below are TIMER
## STUBS ONLY -- Phase 4 polish (TK-P4-0x) replaces both with real
## animation/VFX; the "TK-P4-xx HOOK" comments mark exactly where, same
## shape as KickAbility.host_apply()'s own TK-P2-17 stagger hook comment.
## Step 6 (move the old tiger outside the Safe Circle) is a PLACEHOLDER
## teleport -- kept as-is by TK-P2-06 (the Safe Circle boundary itself,
## characters/components/SafeCircleRules.gd + the new _physics_process()/
## correct_tiger_position() below): exit_radius_m (6.0m) already lands
## outside safe_circle_radius (5.0m, TK-P2-06's locked value), and the old
## tiger's role has already flipped to Outer by the time this teleport runs
## (see apply_role_switch() below), so the new boundary clamp never fights
## this placeholder -- still not a REAL Safe-Circle-boundary-aware exit
## (e.g. shortest path out, or an actual gate), just no longer blocking on
## the boundary not existing.
##
## HOST-AUTHORITATIVE THROUGHOUT: every step's authoritative logic (the
## is_tag_sequence_active lock, the role assignment, the exit teleport) only
## ever runs on multiplayer.is_server() -- see start_tag_sequence()'s own
## assert. The one broadcast every peer must OBSERVE (the actual role swap +
## the step-6 exit placeholder) uses apply_role_switch, an
## @rpc("authority","call_local","reliable") exactly like design doc section
## 5 step 1 specifies (same call_local pattern as
## AbilityController.rpc_confirm, so the host's own copy also runs the swap
## locally instead of being special-cased).
##
## PURE LOGIC lives in managers/TagSequenceRules.gd (re-trigger guard,
## role-swap sanity, the step-6 exit-position placeholder math) -- this file
## is a thin host-only shell around it, same "decision logic has no opinion
## about callers" split as every other host_validate()/GameManager-shaped
## file in this codebase (KickAbility/KickRules, TagAbility/TagRules,
## TigerSelector).
##
## TK-P2-09 (สุ่มเสือตัวแรก, gameplay-engineer) ADDITION: this file now also
## owns assigning the FIRST Tiger of a round, per design doc §8 ("GameManager
## = เจ้าของ role + Tag Sequence 7 ขั้น"). Same node, same placement, same
## host-authoritative-only posture as apply_role_switch above -- see
## assign_first_tiger()/_try_assign_first_tiger() below. PURE selection logic
## (pick_first_tiger/build_role_map/count_tigers) lives in
## managers/TigerSelector.gd (pre-existing, see that file's own doc); this
## file only wires TigerSelector's pure output into a real broadcast, same
## split as TagSequenceRules above.
##
## TK-P2-06 (Safe Circle, gameplay-engineer) ADDITION: this file now also owns
## the HOST-SIDE best-effort correction half of the Safe Circle boundary
## (design ruling point 3, Change Log [0.42]) -- see _physics_process()/
## correct_tiger_position() below for what this is (a defense-in-depth
## backstop) and, importantly, is NOT (a hard containment guarantee against a
## deliberately modified client -- position stays owner-authoritative
## one-way sync; see that method's own doc, and `TK-P2-28`, filed for
## architect to rule on whether Phase 2 needs true host-authoritative
## position containment). The OWNER-SIDE local-prediction half lives on
## characters/components/MovementComponent.gd (role-gated, applies to an
## honest Tiger client's own movement every tick); the pure boundary math both
## halves share lives on characters/components/SafeCircleRules.gd (same
## "pure static helper, thin host-only shell" split every other file in this
## class doc already follows).
##
## FORMER INTERIM CALL SITE, NOW SUPERSEDED BY TK-P2-15 BELOW: this doc
## paragraph used to describe "once at round start" as approximated by "once
## every initially-connected peer's Player has actually spawned under
## ../Players" as the DIRECT trigger for the first-Tiger pick. That
## spawn-completion signal still exists and is still the right trigger --
## but it now starts the COUNTDOWN (see next doc section), not the pick
## itself; _try_assign_first_tiger() has moved one step later, to
## _on_countdown_finished().
##
## TK-P2-15 (Match state machine, gameplay-engineer) ADDITION -- WaitingRoom
## -> Countdown -> Playing -> MatchEnd: this file now also owns the
## match-level state machine layered ON TOP of everything documented above
## (the Tag Sequence, first-Tiger assignment, Safe Circle correction all keep
## their exact same scope and behavior; TK-P2-15 only changes WHEN
## _try_assign_first_tiger() fires and adds what happens once the match is
## over). Pure state-transition logic lives on the new
## managers/MatchStateRules.gd (valid-edge guard, same "pure static helper"
## split as characters/RoleRules.gd); the live host-only shell (state var,
## the broadcast, the round-count-based MatchEnd trigger, the return-to-
## WaitingRoom scene switch) lives here.
##
## FLOW: PlayerSpawner's readiness barrier finishes spawning everyone ->
## GameManager observes the same "every expected Player has spawned" signal
## the old first-Tiger trigger used (_on_player_entered_watch_match_ready(),
## renamed from _on_player_entered_watch_first_tiger()) -> broadcasts
## WAITING_ROOM -> COUNTDOWN and calls CountdownManager.start_countdown()
## (TK-P2-14, managers/CountdownManager.gd, a new sibling node under
## world/TestArena.tscn) -> once CountdownManager's `finished` signal fires
## (host-only), broadcasts COUNTDOWN -> PLAYING and immediately calls
## _try_assign_first_tiger() (per the card's own note: "เข้า Playing -> เรียก
## assign_first_tiger") -> RoundManager (TK-P2-07) takes over the
## round-to-round Tiger-swap loop exactly as it already did, unchanged -> once
## a MatchEnd trigger fires (see next paragraph), broadcasts PLAYING ->
## MATCH_END, waits match_end_grace_sec, then broadcasts a scene switch back
## to ui/WaitingRoom.tscn (mirroring world/TestArena.gd's own
## change_scene_to_file "return to menu" pattern) -- which frees this whole
## arena scene, GameManager included, closing the loop.
##
## MATCH-END TRIGGER (Phase 3 placeholder, per the card's own instruction: "ship
## a placeholder, designer locks the real value later" -- same pattern already
## used for Pounce/Stagger/Charged-Kick's tunables): the GDD is silent on match-
## length/end-condition (Game_Balance.md only locks a per-ROUND length, 3-5 min,
## already RoundManager's own scope -- TK-P2-07's own doc already flags GDD §9 as
## leaving round-END conditions open for TK-P3-04, and nothing anywhere defines a
## MATCH-end condition at all). This file picks the simplest defensible trigger:
## a FIXED NUMBER OF ROUNDS (`rounds_per_match`, @export, placeholder = 3).
## GameManager counts a "round" the exact same way RoundManager's own class doc
## already reasons about "a Tiger's timed reign began" -- by watching every
## Player's PRE-EXISTING role_changed signal (the identical hook RoundManager
## itself, and TK-P2-05's CameraComponent, already subscribe to) and counting
## every transition INTO Tiger while match_state == PLAYING, regardless of
## whether that transition was caused by GameManager's OWN first-Tiger pick, a
## completed Tag Sequence (also this file), or RoundManager's own independent
## timeout-driven start_new_round() broadcast -- the only way to observe ALL
## THREE causes uniformly without RoundManager exposing a new "round changed"
## signal of its own (which would mean touching that reviewed, human-tested, live-
## RPC file for this card, the same "don't touch a proven file if you don't have
## to" reasoning RoundManager's own doc gives for reusing Player.role_changed
## instead of a new GameManager signal). This is explicitly NOT a durable design
## decision -- TK-P3-04 (GDD Open Questions, balance tuning from real playtest
## data) owns picking the real match-end feel (fixed rounds vs. a total match
## timer vs. something else entirely).
##
## AUTOLOAD-VS-SCENE-LOCAL DECISION (open question carried forward from the
## original TK-P2-03 architect ruling / design doc §8a, explicitly required to
## be resolved by this card, not silently): GameManager STAYS scene-local (NOT
## promoted to an autoload). Reasoning: (1) nothing about this match SM actually
## needs to persist across the WaitingRoom<->Arena scene boundary -- every
## "hand-off" this SM needs is ALREADY carried by mechanisms that predate this
## card and are already human-tested: the WaitingRoom -> Arena edge is carried by
## ui/WaitingRoom.gd's existing _rpc_start_match() scene-switch broadcast
## (TK-P2-13), and this card's own new MATCH_END -> WaitingRoom edge is carried
## the exact same way, symmetrically, by this file's new return_to_waiting_room()
## broadcast (see below) -- neither edge needs a persistent node watching across
## the transition, both are "host broadcasts a synced scene switch" the same way
## TestArena.gd's own "return to MainMenu" flow already works; (2) promoting
## GameManager to an autoload is a project-wide architecture change (a new
## project.godot autoload entry reachable from every scene, including
## MainMenu/WaitingRoom where match-scoped state like `_is_tag_sequence_active`/
## `_tiger_rng`/`_round_count` would be meaningless most of the time) that
## CLAUDE.md and this agent's own contract (`.claude/agents/gameplay-engineer.md`
## §7 "MUST NOT ... hard-code tunables the GDD marks design-owned" / architecture
## changes need architect approval) require escalating to `architect` BEFORE
## implementing -- and per (1), nothing here actually NEEDS that change, so there
## is nothing to escalate; (3) staying scene-local keeps every one of this file's
## existing host-authoritative guarantees (the is_server() gates, the RPC
## call_local patterns, the whole reviewed/human-tested Tag Sequence + Safe Circle
## + first-Tiger surface) completely untouched -- a fresh GameManager instance is
## created every time a fresh TestArena is entered, with zero risk of stale
## match-scoped state leaking from a previous match into a new one (an autoload
## would need EXPLICIT reset logic on every "return to WaitingRoom" to avoid
## exactly that class of bug). Per this card's own instruction, this decision is
## recorded here AND in the card's own `notes` in `_backlog.json` -- NOT escalated
## to architect, since (a) is not the call being made.

## Seconds the stub throw-to-ground step "plays" before the transform stub
## starts. Placeholder pending TK-P4-0x real animation -- @export so
## producer/designer can retune without touching code (CLAUDE.md: expose
## design-owned tunables, never hard-code).
@export var throw_stub_sec: float = 0.6

## Seconds the stub transform-effect step "plays" before the role swap
## resolves. Same placeholder/@export reasoning as throw_stub_sec above.
@export var transform_stub_sec: float = 0.6

## PLACEHOLDER exit radius (meters from the arena center, world origin) the
## old tiger is teleported to for step 6 -- a rough "somewhere outside the
## ring" stand-in, NOT a real Safe-Circle-boundary-aware exit (e.g. shortest
## path out, or an actual gate). world/TestArena.tscn's own SafeCircleMarker
## (visual-only ring) and safe_circle_radius below (TK-P2-06's real, locked
## boundary value) both ship 5.0 -- picked slightly larger here on the same
## "give some margin" placeholder reasoning KickAbility/TagDetectorComponent's
## own placeholder tunables use elsewhere in this codebase (also keeps this
## placeholder teleport landing safely OUTSIDE the new Tiger-only boundary
## clamp below, though that clamp would not apply here anyway -- the old
## tiger's role has already flipped to Outer by the time this teleport runs).
## Flag for designer if a real boundary-aware exit is ever wanted (Phase 4
## polish candidate, not required by TK-P2-06's own scope).
@export var exit_radius_m: float = 6.0

## TK-P2-06 (Safe Circle, gameplay-engineer). Design-locked balance value
## (Tiger_Kick_Project_Docs/01_Design/Game_Balance.md §4 "Safe Circle
## radius" = 5.0m, Change Log [0.34]/[0.42] design ruling) -- @export per
## CLAUDE.md's "expose design-owned tunables" rule. This is GameManager's own
## copy for the HOST-SIDE authoritative correction half of the boundary (see
## _physics_process()/correct_tiger_position() below); characters/components/
## MovementComponent.gd keeps its own matching copy for the owner-side local
## prediction half. Independent per-file copies, not a shared constant --
## same convention exit_radius_m above already uses (Game_Balance.md's own
## "แก้ที่ไฟล์นี้ + Change Log + (ถ้ากระทบโค้ด) การ์ด" note: no single shared
## autoload exists in this codebase for design-locked values).
@export var safe_circle_radius: float = 5.0

## Tolerance margin (meters), HOST-SIDE ONLY, added to safe_circle_radius
## purely for the _physics_process() "is this Tiger's replicated position
## still inside the circle" check below -- the owner's own LOCAL clamp
## (MovementComponent.apply_safe_circle_boundary()) stays exact, no
## tolerance, since that one is local prediction, not something that fires
## network traffic.
##
## WHY THIS EXISTS (code-review + network-engineer review finding, both
## independently caught the same defect pre-handoff): an honest Tiger
## pressed against the wall has its OWNER-side clamp pin `position` to
## EXACTLY `safe_circle_radius` every tick -- the single most common resting
## state this boundary creates, not a rare edge case. That exact value then
## round-trips through MultiplayerSynchronizer float replication before the
## host ever reads it, landing a few ULP on either side of the true radius
## roughly half the time -- ordinary replication noise, not a real breach.
## Without slack, is_inside()'s exact `<=` would read that honest client as
## "outside" on ~half of every physics tick, firing a reliable,
## all-peers-targetable correct_tiger_position RPC 15-30x/sec/Tiger against a
## client that never did anything wrong. 0.05m is comfortably larger than any
## float32 replication noise at this arena's scale while still catching a
## REAL breach (a client that actually skipped its own local clamp, which
## would read many centimeters+ outside, not a few ULP) well before it
## becomes visually meaningful. correct_tiger_position's own CORRECTED
## position still snaps back to the exact `safe_circle_radius` (not
## `safe_circle_radius + tolerance`) -- the tolerance only widens the
## "should I bother correcting at all" check, never where a correction lands.
const SAFE_CIRCLE_CORRECTION_TOLERANCE_M: float = 0.05

## TK-P2-15 Phase 3 PLACEHOLDER match-end trigger (see class doc
## "MATCH-END TRIGGER" section for why a fixed round count, and why this is
## explicitly not a locked design value yet) -- @export per CLAUDE.md's
## "expose design-owned tunables, never hard-code" rule.
@export var rounds_per_match: int = 3

## TK-P2-15: seconds MATCH_END stays broadcast before GameManager switches
## every peer back to the Waiting Room -- a brief window for whatever future
## "Match Over" HUD polish-agent builds to actually be visible, same
## "placeholder timing, @export so it can be retuned without touching logic"
## posture as throw_stub_sec/transform_stub_sec above.
@export var match_end_grace_sec: float = 3.0

## TK-P2-15: scene switched to once a match ends -- mirrors
## ui/MainMenu.gd's own WAITING_ROOM_SCENE const and
## ui/WaitingRoom.gd's own MATCH_SCENE const (same "runtime-only scene
## switch via change_scene_to_file, one const per file that needs the path"
## convention already used throughout this codebase's scene-transition
## call sites).
const WAITING_ROOM_SCENE: String = "res://ui/WaitingRoom.tscn"

## TK-P2-15: fires whenever set_match_state() actually applies a (possibly
## no-op) transition, carrying the new MatchStateRules.State value. No
## subscriber exists yet in this card's scope (a HUD match-state indicator is
## polish-agent/Phase-4 territory, same posture as CountdownManager's own
## `tick_changed` hook comment) -- this is the obvious hook a future HUD would
## need, emitted locally on every peer inside set_match_state() itself so it
## fires identically host-side and client-side.
signal match_state_changed(new_state: MatchStateRules.State)

## TK-P2-15: this file's own current match state (see class doc's
## AUTOLOAD-VS-SCENE-LOCAL DECISION for why WAITING_ROOM is a nominal
## starting value here, not a state any live code branches on). Every peer's
## copy is kept in sync exclusively via set_match_state()'s
## @rpc("authority", "call_local", "reliable") broadcast below -- never
## written directly anywhere else, same "only ever mutated through the
## broadcast RPC, host decides, everyone applies" rule apply_role_switch/
## assign_first_tiger/RoundManager.start_new_round all already follow.
var match_state: MatchStateRules.State = MatchStateRules.State.WAITING_ROOM

## HOST-ONLY (TK-P2-15). True once _start_countdown() has run -- guards
## against re-entering the Countdown trigger a second time (mirrors
## _first_tiger_assigned's own idempotency-guard shape below).
var _countdown_started: bool = false

## HOST-ONLY (TK-P2-15). How many rounds (Tiger-assignment transitions while
## match_state == PLAYING) have been observed so far this match -- see class
## doc "MATCH-END TRIGGER". Compared against rounds_per_match to decide when
## to end the match.
var _round_count: int = 0

## HOST-ONLY (TK-P2-15). Guards return_to_waiting_room() the same way
## ui/WaitingRoom.gd's own _match_started guards _rpc_start_match() --
## change_scene_to_file() is deferred, so a duplicate/retried reliable RPC
## must not queue two scene switches.
var _match_ended_locally: bool = false

## Cached "CountdownManager" sibling (TK-P2-14, managers/CountdownManager.gd)
## under this node's parent (world/TestArena.tscn's root) -- same
## relative-lookup pattern as _players_root above.
@onready var _countdown_manager: Node = get_node("../CountdownManager")

## HOST-ONLY re-trigger guard (mandatory per TK-P2-02's human-test finding:
## boundary jitter re-fired tag_target_in_range/left_range repeatedly within
## the same second -- a cooldown ledger alone is NOT enough since this lock
## must hold for the sequence's FULL duration, not just one cooldown
## window). TagAbility.host_validate() reads this via is_sequence_active()
## below before ever attempting a new Tag.
var _is_tag_sequence_active: bool = false

## Cached "Players" root (sibling of this node under TestArena's root) --
## same relative-lookup pattern as networking/PlayerSpawner.gd's own
## _players_root (get_node(spawn_path)), just hardcoded to this scene's
## fixed tree shape (world/TestArena.tscn) rather than an @export NodePath,
## since GameManager (unlike PlayerSpawner) is not designed to be reused
## outside this one arena scene.
@onready var _players_root: Node = get_node("../Players")

## HOST-ONLY (TK-P2-09). How long to wait, after GameManager enters the tree,
## for every initially-connected peer's Player to actually appear under
## _players_root before giving up waiting for the stragglers and assigning
## the first Tiger among whoever HAS spawned. Mirrors
## networking/PlayerSpawner.gd's own ARENA_READY_GRACE_SEC rescue-timer
## pattern (a peer that crashes/hangs mid-load, or gets force-disconnected by
## THAT grace timer, must not deadlock this one forever) -- deliberately
## longer than PlayerSpawner's 8.0s since this wait starts at the same moment
## and must be able to observe PlayerSpawner's own barrier resolving first.
const FIRST_TIGER_SPAWN_WAIT_GRACE_SEC: float = 12.0

## HOST-ONLY (TK-P2-09): true once the first Tiger has been picked and
## broadcast -- guards against ever running the pick/broadcast a second time
## from this interim call site (the round-loop re-roll is TK-P2-07's job, a
## separate future entry point, not this guard).
var _first_tiger_assigned: bool = false

## HOST-ONLY (TK-P2-09): snapshot, taken once in _ready(), of how many
## Players this round expects to see spawned (host + every peer connected at
## that moment) before picking the first Tiger. See
## _on_player_entered_watch_first_tiger() for how this is consumed.
var _expected_first_tiger_roster_size: int = 0

## HOST-ONLY (TK-P2-09): true once FIRST_TIGER_SPAWN_WAIT_GRACE_SEC has
## elapsed without every expected Player spawning -- relaxes
## _on_player_entered_watch_first_tiger()'s condition so the very next
## spawn (or the current count, if already > 0) triggers assignment instead
## of waiting forever for a peer that will never arrive.
var _first_tiger_grace_elapsed: bool = false

## HOST-ONLY (TK-P2-09): the single RandomNumberGenerator instance used for
## the first-Tiger pick. Created and randomize()'d EXACTLY ONCE, here, on the
## host only -- this is the mandatory rule from the card note: clients must
## NEVER call randomize()/pick their own Tiger, or every machine could resolve
## a different "random" winner (S1 desync). Injected into
## TigerSelector.pick_first_tiger() exactly like tests/test_tiger_assignment.gd
## injects its own seeded RNG, so the same pure function is exercised in both
## contexts.
var _tiger_rng: RandomNumberGenerator = null


## TK-P2-09/TK-P2-15: host-only setup for (a) the match-ready ->
## Countdown trigger (formerly the DIRECT first-Tiger trigger -- see class
## doc "TK-P2-15 ADDITION" section for the retasking) and (b) the
## round-counting watch this file's own MatchEnd trigger needs (see class
## doc "MATCH-END TRIGGER"). Never runs any of this on a client -- clients
## only ever receive this file's broadcasts (assign_first_tiger,
## set_match_state, ...), they never decide or wait for anything here.
func _ready() -> void:
	if not multiplayer.is_server():
		return

	_tiger_rng = RandomNumberGenerator.new()
	_tiger_rng.randomize() # ONE call, host-only -- see _tiger_rng doc above.

	_countdown_manager.finished.connect(_on_countdown_finished)

	# TK-P2-15 match-end round counter: watch every currently-spawned AND every
	# future-spawned Player's role_changed the same way RoundManager.gd's own
	# _ready() does (see that file's class doc + this file's own "MATCH-END
	# TRIGGER" doc section for why this duplicates, rather than reuses,
	# RoundManager's watch -- two managers independently observing the same
	# pre-existing signal for two different purposes, the established
	# convention in this codebase).
	for child in _players_root.get_children():
		_watch_player_role_for_match_end(child)
	_players_root.child_entered_tree.connect(_on_player_spawned_watch_match_end)

	# host id + every peer already connected at the moment GameManager enters
	# the tree -- same NetworkManager.get_connected_peer_ids() source
	# networking/PlayerSpawner.gd's own barrier snapshot reads, taken at
	# effectively the same instant (no `await` runs between the two _ready()
	# calls), so both nodes agree on "who do we expect this round".
	_expected_first_tiger_roster_size = 1 + NetworkManager.get_connected_peer_ids().size()

	if _expected_first_tiger_roster_size > 0 and _players_root.get_child_count() >= _expected_first_tiger_roster_size:
		# Standalone/offline boot (or the old staggered-connect path): the
		# sibling PlayerSpawner already spawned everyone it's going to spawn
		# synchronously, earlier in this same _ready() pass (PlayerSpawner is
		# the earlier sibling in world/TestArena.tscn) -- nothing left to wait
		# for.
		_start_countdown()
	else:
		_players_root.child_entered_tree.connect(_on_player_entered_watch_first_tiger)
		_start_first_tiger_grace_timer()


func _start_first_tiger_grace_timer() -> void:
	var grace := Timer.new()
	grace.name = "FirstTigerSpawnGrace"
	grace.wait_time = FIRST_TIGER_SPAWN_WAIT_GRACE_SEC
	grace.one_shot = true
	add_child(grace)
	grace.timeout.connect(_on_first_tiger_grace_timeout)
	grace.start()


## Fires every time a new Player is spawned under _players_root (host's own
## local view -- see _try_assign_first_tiger() doc for why watching spawns,
## rather than firing in _ready() directly, is what keeps the eventual RPC
## broadcast from racing a client's own still-loading scene). Once every
## expected Player has arrived (or the grace window already elapsed and at
## least one Player exists), triggers Countdown -> (once it finishes)
## the actual first-Tiger pick + broadcast.
##
## RETASKED BY TK-P2-15 (name kept as-is -- "match-ready" IS still "first
## Tiger roster ready", just one step earlier than before; see class doc
## "TK-P2-15 ADDITION"): this used to call _try_assign_first_tiger() directly.
## It now calls _start_countdown() instead, which itself calls
## _try_assign_first_tiger() only once CountdownManager's `finished` signal
## fires (_on_countdown_finished() below) -- so this is now "match-ready ->
## Countdown", not "match-ready -> first Tiger" directly.
##
## DEFERRED ON PURPOSE (bug found + fixed during TK-P2-09's own probe
## testing, see tests/net/run_spawn_probe_together.sh output): Node's
## `child_entered_tree` fires as soon as THIS SAME child enters the tree --
## confirmed EMPIRICALLY to run before that child's own _ready() (and
## therefore its @onready ability_controller/movement_component) has been
## assigned yet. That timing hazard was specifically about calling
## set_role() synchronously on the very Player whose spawn just satisfied the
## roster count (see Player.set_role()'s own "caller before ready"
## null-guard doc) -- _start_countdown() itself never calls set_role() (it
## only starts CountdownManager's Timer), so this call_deferred() is no
## longer strictly REQUIRED for correctness, but is kept anyway (harmless,
## one extra frame of latency before Countdown starts) rather than removed,
## since the actual _try_assign_first_tiger() call this eventually leads to
## (via _on_countdown_finished(), several seconds later) still benefits from
## every spawned Player's own _ready() being long since complete by then.
func _on_player_entered_watch_first_tiger(_node: Node) -> void:
	if _countdown_started:
		return
	var have_everyone: bool = _players_root.get_child_count() >= _expected_first_tiger_roster_size
	if have_everyone or (_first_tiger_grace_elapsed and _players_root.get_child_count() > 0):
		_start_countdown.call_deferred()


## Rescue timer (mirrors networking/PlayerSpawner.gd's ARENA_READY_GRACE_SEC):
## if some expected peer's Player never actually spawns (e.g. it crashed
## mid-load, or PlayerSpawner's OWN grace timer force-disconnected it first),
## this must not wait forever -- start the Countdown (and, once it finishes,
## assign the first Tiger) among whoever HAS spawned by now instead of
## deadlocking the match before it even starts.
func _on_first_tiger_grace_timeout() -> void:
	if _countdown_started:
		return
	_first_tiger_grace_elapsed = true
	if _players_root.get_child_count() > 0:
		_start_countdown()
	else:
		GameLog.error("[TIGER] match-ready grace elapsed with zero Players spawned -- will start Countdown as soon as the first Player appears")


## TK-P2-15: host-only trigger for the WAITING_ROOM -> COUNTDOWN edge (see
## class doc "FLOW"). Broadcasts the state transition, then starts
## CountdownManager's timer -- once it finishes, _on_countdown_finished()
## below continues the flow into PLAYING + the first-Tiger pick.
func _start_countdown() -> void:
	if _countdown_started:
		return
	_countdown_started = true

	if _players_root.child_entered_tree.is_connected(_on_player_entered_watch_first_tiger):
		_players_root.child_entered_tree.disconnect(_on_player_entered_watch_first_tiger)

	GameLog.info("[MATCH] match-ready (%d players present) -- entering Countdown" % _players_root.get_child_count())
	set_match_state.rpc(MatchStateRules.State.COUNTDOWN)
	_countdown_manager.start_countdown()


## TK-P2-15: host-only handler for CountdownManager's `finished` signal (a
## LOCAL signal, never broadcast over RPC itself -- see
## managers/CountdownManager.gd's own class doc for why only the host needs
## to react here). Per the card's own note ("เข้า Playing -> เรียก
## assign_first_tiger"): broadcasts COUNTDOWN -> PLAYING first, then performs
## the exact same first-Tiger pick TK-P2-09 already built (unchanged
## _try_assign_first_tiger()/_pick_first_tiger_with_reroll() logic -- only
## the CALL SITE and its timing moved, per class doc "TK-P2-15 ADDITION").
func _on_countdown_finished() -> void:
	set_match_state.rpc(MatchStateRules.State.PLAYING)
	_try_assign_first_tiger()


## HOST-ONLY: the peer ids of every Player CURRENTLY spawned under
## _players_root, derived from the Players/<id> naming contract every
## spawned Player already uses (TK-BUG-P1-01 -- see PlayerSpawner.gd's own
## class doc). This is the candidate pool TigerSelector.pick_first_tiger()
## chooses from -- built from ACTUAL spawned Players (not raw
## NetworkManager peer ids) so a pick can never reference a peer whose
## Player does not exist yet/anymore.
func _current_player_ids() -> Array:
	var ids: Array = []
	for child in _players_root.get_children():
		# .to_int() (not the global int() cast) to match the rest of the
		# codebase's Players/<id> name-parsing convention -- see
		# networking/SpawnPointUtil.gd / TagDetectorComponent.gd's own
		# `.name.to_int()` usage.
		ids.append(child.name.to_int())
	ids.sort()
	return ids


## HOST-ONLY: picks the first Tiger, re-rolling against the CURRENT roster if
## the chosen id's Player has disconnected (card edge case: "if the
## randomly-selected peer disconnects at exactly the wrong moment, re-roll").
## _try_assign_first_tiger() may itself run one frame LATER than the spawn
## that triggered it (see _on_player_entered_watch_first_tiger()'s
## call_deferred() doc), but once it starts, this whole call chain down to
## here is synchronous -- no `await` runs between building the candidate list
## and broadcasting -- so in practice a disconnect cannot land mid-call; this
## loop makes the guarantee explicit rather than relying on "it's synchronous
## so it can't happen" (e.g. a disconnect signal already queued ahead of this
## call on the same frame). Each failed iteration re-snapshots the roster and
## re-picks, so it always terminates: either a still-present id is found, or
## the roster empties entirely (the card's "only 1 player left" edge case is
## handled by TigerSelector.pick_first_tiger() itself returning that one
## remaining id; only a TOTAL wipeout falls through to NO_ID here).
func _pick_first_tiger_with_reroll() -> int:
	var ids: Array = _current_player_ids()
	var attempts: int = 0
	while attempts <= ids.size():
		if ids.is_empty():
			return TigerSelector.NO_ID
		var pick: int = TigerSelector.pick_first_tiger(ids, _tiger_rng)
		if _players_root.has_node(str(pick)):
			return pick
		ids = _current_player_ids() # re-snapshot -- the picked id vanished
		attempts += 1
	return TigerSelector.NO_ID


## HOST-ONLY: the actual TK-P2-09 decision point. Picks exactly one Tiger
## (see _pick_first_tiger_with_reroll()) and broadcasts it via
## assign_first_tiger.rpc() below -- same
## @rpc("authority","call_local","reliable") pattern as apply_role_switch,
## so the host's own copy also applies the result instead of being
## special-cased. Idempotent: does nothing once _first_tiger_assigned is set.
func _try_assign_first_tiger() -> void:
	if _first_tiger_assigned:
		return

	if _players_root.child_entered_tree.is_connected(_on_player_entered_watch_first_tiger):
		_players_root.child_entered_tree.disconnect(_on_player_entered_watch_first_tiger)

	var tiger_id: int = _pick_first_tiger_with_reroll()
	if tiger_id == TigerSelector.NO_ID:
		GameLog.error("[TIGER] assign_first_tiger: no spawned Players to choose from -- cannot assign a Tiger")
		return

	_first_tiger_assigned = true
	GameLog.info("[TIGER] assign_first_tiger: host picked tiger=%d among %s" % [tiger_id, _current_player_ids()])
	assign_first_tiger.rpc(tiger_id)


## Host -> everyone (TK-P2-09). Broadcasts the ONE first-Tiger decision the
## host made (see _try_assign_first_tiger()) so every peer applies the exact
## SAME role assignment -- the mandatory server-authority rule from the card
## note: clients must NEVER pick/derive a Tiger themselves, only ever apply
## whatever this broadcast says. call_local so the host's own copy runs this
## too, exactly like apply_role_switch.
##
## Per TigerSelector.gd's own documented usage contract ("4) call
## build_role_map() on every peer to apply roles"), every peer builds the
## same role map from its OWN current _players_root roster + the broadcast
## tiger_id, then applies it to EVERY Player currently present (not just the
## chosen tiger_id) -- so any peer whose Player still held a stale/default
## role (e.g. it spawned slightly after another peer, or a future re-entry
## case) is explicitly confirmed Outer too, not just left alone.
@rpc("authority", "call_local", "reliable")
func assign_first_tiger(tiger_id: int) -> void:
	var ids: Array = _current_player_ids()
	var roles: Dictionary = TigerSelector.build_role_map(ids, tiger_id)
	for child in _players_root.get_children():
		var pid: int = child.name.to_int()
		var is_tiger: bool = roles.get(pid, TigerSelector.ROLE_OUTER) == TigerSelector.ROLE_TIGER
		child.set_role(RoleRules.TIGER if is_tiger else RoleRules.OUTER)


# --- TK-P2-15: match-level state machine (WaitingRoom -> Countdown ->     --
# --- Playing -> MatchEnd -> back to WaitingRoom). See class doc "TK-P2-15 --
# --- ADDITION" for the full flow writeup.                                 --

## Host -> everyone. The ONE place match_state is ever mutated (see that
## var's own doc) -- validates the transition via
## MatchStateRules.is_valid_transition() (fail-closed: an invalid/out-of-order
## transition is logged and dropped rather than silently applied, same
## defensive posture apply_role_switch's own TagSequenceRules.is_valid_role_swap()
## check uses) before applying it and emitting match_state_changed for any
## future subscriber (HUD polish, etc.). call_local so the host's own copy
## applies this identically to every client, same pattern as every other
## broadcast RPC in this file.
@rpc("authority", "call_local", "reliable")
func set_match_state(new_state: MatchStateRules.State) -> void:
	if not MatchStateRules.is_valid_transition(match_state, new_state):
		GameLog.error("[MATCH] refusing invalid state transition: %s -> %s" % [
			MatchStateRules.state_name(match_state), MatchStateRules.state_name(new_state)])
		return
	match_state = new_state
	GameLog.info("[MATCH] state -> %s" % MatchStateRules.state_name(new_state))
	match_state_changed.emit(new_state)


## Wires the match-end round-counting watch (see class doc "MATCH-END
## TRIGGER") onto a Player -- mirrors RoundManager.gd's own
## _watch_player_role()/_on_player_spawned() shape exactly (two managers
## independently watching the SAME pre-existing role_changed signal for two
## different purposes, the established convention in this codebase -- see
## RoundManager.gd's own class doc for why a shared utility is deliberately
## NOT used here either).
func _watch_player_role_for_match_end(player: Node) -> void:
	player.role_changed.connect(_on_any_player_role_changed_for_match_end.bind(player))


func _on_player_spawned_watch_match_end(node: Node) -> void:
	_watch_player_role_for_match_end(node)


## The match-end round counter (see class doc "MATCH-END TRIGGER"). Counts
## every transition INTO Tiger while match_state == PLAYING, regardless of
## which of the three causes fired it (this file's own first-Tiger pick, this
## file's own Tag-Sequence role swap, or RoundManager's independent
## timeout-driven start_new_round()) -- exactly the same "any Player's role
## becomes Tiger" trigger condition RoundManager._on_any_player_role_changed()
## uses for its own (different) purpose. Deliberately ignores every
## role_changed emission OUTSIDE of PLAYING (e.g. none currently fire during
## WAITING_ROOM/COUNTDOWN/MATCH_END in this card's scope, but the guard keeps
## this correct if a future card ever changes that) so a stray/edge-case role
## flip can never accidentally end a match early.
func _on_any_player_role_changed_for_match_end(new_role: StringName, player: Node) -> void:
	if match_state != MatchStateRules.State.PLAYING:
		return
	if new_role != RoleRules.TIGER:
		return
	_round_count += 1
	GameLog.info("[MATCH] round %d/%d started (tiger=%s)" % [_round_count, rounds_per_match, player.name])
	if _round_count >= rounds_per_match:
		_end_match()


## HOST-ONLY: the MatchEnd trigger fired (see class doc "MATCH-END TRIGGER").
## Broadcasts PLAYING -> MATCH_END immediately, then -- after
## match_end_grace_sec -- broadcasts the scene switch back to the Waiting
## Room (see return_to_waiting_room() below). Not awaited by any caller (this
## runs from a signal handler, same "fire-and-forget coroutine" shape
## _run_sequence()'s own await chain already uses in this file).
func _end_match() -> void:
	GameLog.info("[MATCH] match-end trigger reached (%d/%d rounds) -- ending match" % [_round_count, rounds_per_match])
	set_match_state.rpc(MatchStateRules.State.MATCH_END)
	await get_tree().create_timer(match_end_grace_sec).timeout
	return_to_waiting_room.rpc()


## Host -> everyone (call_local, mirrors ui/WaitingRoom.gd's own
## _rpc_start_match() exactly -- same idempotency-guard/deferred-scene-switch/
## push_warning-on-error shape, just running the switch in the OPPOSITE
## direction). Frees this entire world/TestArena.tscn scene -- GameManager,
## RoundManager, CountdownManager, every Player, all of it -- the moment the
## new scene is instanced, closing the WAITING_ROOM -> COUNTDOWN -> PLAYING ->
## MATCH_END -> WAITING_ROOM loop. A fresh WaitingRoom + (if a match starts
## again) a fresh GameManager are created next time, with zero risk of
## match-scoped state (this instance's _round_count, _tiger_rng,
## _is_tag_sequence_active, ...) leaking into a future match -- see class doc
## "AUTOLOAD-VS-SCENE-LOCAL DECISION" point 3.
@rpc("authority", "call_local", "reliable")
func return_to_waiting_room() -> void:
	if _match_ended_locally:
		return
	_match_ended_locally = true

	GameLog.info("[MATCH] match over -- returning to %s" % WAITING_ROOM_SCENE)
	var err: Error = get_tree().change_scene_to_file(WAITING_ROOM_SCENE)
	if err != OK:
		push_warning("[MATCH] failed to switch to %s (error %d)" % [WAITING_ROOM_SCENE, err])


## Read-only accessor for TagAbility.host_validate() (design doc section 3
## testability note: host_validate is a thin shell -- this is the one piece
## of live GameManager state it needs to consult that TagSequenceRules
## cannot know on its own, since the lock is genuinely host-runtime state,
## not a pure function of any inputs).
func is_sequence_active() -> bool:
	return _is_tag_sequence_active


## Entry point TagAbility.host_apply() calls once a Tag activation has been
## host_validate()'d as ok (design doc section 4 walkthrough -- this card's
## step 1, "the Tiger successfully grabs", already happened by the time this
## runs; steps 2-7 below are its CONSEQUENCES, not separately
## player-triggered, per the card). HOST-ONLY.
func start_tag_sequence(tiger_id: int, target_id: int) -> void:
	assert(multiplayer.is_server(), "GameManager.start_tag_sequence must only ever run on the host (mirrors Ability_System_Design.md section 4a's host-only assert pattern)")

	if not TagSequenceRules.can_start_sequence(_is_tag_sequence_active):
		# Defense in depth -- TagAbility.host_validate() already rejects a new
		# Tag while this lock is set (the mandatory re-trigger guard), so this
		# branch should be unreachable in practice; fail loudly rather than
		# silently double-run a sequence if it ever is.
		GameLog.error("[TAG-SEQ] start_tag_sequence called while a sequence is already active -- ignoring (tiger=%d target=%d)" % [tiger_id, target_id])
		return

	_is_tag_sequence_active = true
	GameLog.info("[TAG-SEQ] step1 grab confirmed: tiger=%d target=%d -- sequence locked" % [tiger_id, target_id])

	# Not awaited here on purpose: start_tag_sequence() is a synchronous
	# HOST_AUTHORITATIVE ability's host_apply() callee (AbilityController
	# calls host_apply() then immediately broadcasts rpc_confirm -- it must
	# not block on a multi-second Tag Sequence). _run_sequence() below runs
	# to its first `await` synchronously (locking + logging above already
	# happened), then continues as a coroutine.
	_run_sequence(tiger_id, target_id)


## HOST-ONLY: steps 2-7, in order. A single coroutine (rather than one Timer
## node per step) keeps the 7-step ORDER textually obvious and impossible to
## interleave with a second sequence -- the lock above already prevents a
## second start_tag_sequence() call while this runs; the `await`s below are
## what makes "in order, one at a time" true operationally, not just
## documented.
func _run_sequence(tiger_id: int, target_id: int) -> void:
	# Step 2: throw-to-ground. TK-P4-0x HOOK: replace this timer stub with the
	# real throw animation/physics once Phase 4 art lands -- no
	# stagger/knockback-style velocity change happens here today, same "log +
	# hook comment, no real effect yet" shape as KickAbility.host_apply()'s
	# own TK-P2-17 hook.
	GameLog.info("[TAG-SEQ] step2 throw-to-ground (stub, %.1fs)" % throw_stub_sec)
	await get_tree().create_timer(throw_stub_sec).timeout

	# Step 3: transform-effect. TK-P4-0x HOOK: replace this timer stub with
	# real transform VFX/SFX once Phase 4 polish lands.
	GameLog.info("[TAG-SEQ] step3 transform-effect (stub, %.1fs)" % transform_stub_sec)
	await get_tree().create_timer(transform_stub_sec).timeout

	# Steps 4+5: tagged player becomes the new Tiger, old Tiger becomes Outer
	# -- both resolved by the SAME broadcast (design doc section 5 step 1:
	# apply_role_switch), since every peer needs to observe both role flips
	# atomically together (a peer that only ever saw the new-Tiger half, or
	# only the old-Tiger-back-to-Outer half, would render a frame with either
	# zero or two Tigers). Step 6 (placeholder exit) rides the SAME broadcast
	# -- see apply_role_switch()'s own doc for why.
	if not TagSequenceRules.is_valid_role_swap(tiger_id, target_id):
		GameLog.error("[TAG-SEQ] refusing role swap: invalid pair (old=%d new=%d)" % [tiger_id, target_id])
		_is_tag_sequence_active = false
		return

	var exit_position: Vector3 = _compute_old_tiger_exit_position(tiger_id)
	GameLog.info("[TAG-SEQ] step4+5 role swap: old tiger=%d -> outer, new tiger=%d -> tiger; step6 exit=%s (placeholder, TK-P2-06 pending)" % [tiger_id, target_id, exit_position])
	apply_role_switch.rpc(tiger_id, target_id, exit_position)

	# Step 7: clear the lock -- "return to Playing" is scoped to exactly this
	# for this card (TK-P2-15 owns the real match state machine).
	_is_tag_sequence_active = false
	GameLog.info("[TAG-SEQ] step7 sequence complete -- lock cleared")


## HOST-ONLY: reads the old tiger's CURRENT position off the host's own local
## copy of Players/<tiger_id> (same "host's own reading of sibling Player
## state is authoritative enough for this purpose" caveat
## KickAbility.host_validate()/TagDetectorComponent's own docs already accept
## -- host sees a client slightly behind that client's own screen) and hands
## it to the pure TagSequenceRules.compute_exit_position() helper. Returns
## Vector3.ZERO (arena center) if the old tiger's Player node cannot be found
## -- should not happen (TagAbility.host_validate() already confirmed a
## tagger/target pair moments ago), but this must never crash mid-sequence.
func _compute_old_tiger_exit_position(tiger_id: int) -> Vector3:
	var old_tiger: Node3D = _players_root.get_node_or_null(str(tiger_id)) as Node3D
	if old_tiger == null:
		GameLog.error("[TAG-SEQ] _compute_old_tiger_exit_position: Player %d not found -- defaulting to arena center" % tiger_id)
		return Vector3.ZERO
	return TagSequenceRules.compute_exit_position(old_tiger.global_position, exit_radius_m)


## Host -> everyone (design doc section 5 step 1, call_local so the host's
## own copy also runs this instead of being special-cased -- same pattern as
## AbilityController.rpc_confirm). Every peer resolves both Players from the
## Players/<id> naming contract (TK-BUG-P1-01) and calls PlayerRoot.set_role()
## (idempotent, design doc section 5 step 3) -- exactly the design doc's
## own section 5 walkthrough: "every peer finds Player from
## Players/str(peer_id) -> player.set_role(...)".
##
## Step 6 (placeholder exit, non-final -- see class doc) rides this SAME
## broadcast rather than a separate RPC: every peer needs to move the SAME
## old-tiger Player at the SAME logical moment as its role flips (rendering
## a stray frame with the old tiger still standing where it got tagged, but
## already an Outer, is a smaller cosmetic gap than a second round-trip would
## avoid). Only the OWNING peer's own write to `position` actually matters --
## MultiplayerSynchronizer's position channel replicates FROM the owning peer
## TO everyone else (design doc section 4a), so setting `position` on a
## Player this peer does NOT own would just be silently overwritten by that
## Player's own next replicated update; the `is_multiplayer_authority()`
## guard below make this explicit rather than relying on that silent
## overwrite.
@rpc("authority", "call_local", "reliable")
func apply_role_switch(old_tiger_id: int, new_tiger_id: int, old_tiger_exit_position: Vector3) -> void:
	var old_tiger: Node = _players_root.get_node_or_null(str(old_tiger_id))
	if old_tiger:
		old_tiger.set_role(&"outer")
		if old_tiger.is_multiplayer_authority():
			# PLACEHOLDER (see class doc step 6 note): a rough
			# teleport-outside-a-fixed-radius stand-in, not a real
			# Safe-Circle-boundary exit -- TK-P2-06 replaces this.
			old_tiger.position = old_tiger_exit_position
	else:
		GameLog.error("[TAG-SEQ] apply_role_switch: old tiger Player %d not found (disconnected mid-sequence?)" % old_tiger_id)

	var new_tiger: Node = _players_root.get_node_or_null(str(new_tiger_id))
	if new_tiger:
		new_tiger.set_role(&"tiger")
	else:
		GameLog.error("[TAG-SEQ] apply_role_switch: new tiger Player %d not found (disconnected mid-sequence?)" % new_tiger_id)


## HOST-ONLY (TK-P2-06, Safe Circle). Design ruling point 3 ("host-
## authoritative -- the HOST clamps/rejects the Tiger's position; a client
## cannot walk a Tiger through the boundary by local movement alone"):
## characters/components/MovementComponent.gd already confines an HONEST
## Tiger client's own LOCAL prediction every physics tick (see that file's
## own doc). The host (and ONLY the host -- multiplayer.is_server() gate,
## mirrors every other host-only method in this file) independently
## re-checks whether each CURRENTLY-Tiger Player's replicated position (the
## host's own local view of it -- same "host sees a client slightly behind
## that client's own screen" caveat _compute_old_tiger_exit_position() above
## already documents) is still inside the circle every physics tick (with
## SAFE_CIRCLE_CORRECTION_TOLERANCE_M slack -- see that const's own doc for
## why an exact check would misfire against an honest, already-compliant
## Tiger resting against the wall), and pushes a correction back to that
## Player's OWNING peer only if not, via correct_tiger_position() below.
##
## HONEST ABOUT WHAT THIS DOES AND DOES NOT DO (reworded per code-review +
## network-engineer review -- the previous wording here overclaimed this as
## authoritatively "stopping" a cheating client; it does not): position in
## this codebase is owner-authoritative, ONE-WAY sync (Game_Balance.md §1:
## "ตำแหน่ง = owner-authoritative... sync ทางเดียว") -- a genuinely malicious
## client that has actually patched out its own local clamp will simply
## overwrite this correction with its own (still out-of-bounds) position on
## its very next physics tick, forever, since MultiplayerSynchronizer only
## ever replicates FROM the owner. This is a BEST-EFFORT defense-in-depth
## BACKSTOP, not a hard containment guarantee -- it helps a COOPERATING
## client recover from a transient bug/desync (a real, useful case: a stray
## frame of lag, a physics hiccup, a future regression that breaks the local
## clamp), and it is the honest, no-op-in-ordinary-play backstop design
## ruling point 3 asked for at this card's scope, but it is NOT proof against
## a deliberately modified client. Whether Phase 2 needs TRUE
## host-authoritative position containment (the host, not the owner, being
## the source of truth for a Tiger's position) is an open architecture
## question, deliberately NOT decided here -- filed as `TK-P2-28` for
## architect to rule on.
func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return

	var host_id: int = multiplayer.get_unique_id()
	for child in _players_root.get_children():
		if child.role != RoleRules.TIGER:
			continue
		var current_position: Vector3 = child.position
		if SafeCircleRules.is_inside(current_position, safe_circle_radius + SAFE_CIRCLE_CORRECTION_TOLERANCE_M):
			continue
		var corrected: Vector3 = SafeCircleRules.clamp_to_circle(current_position, safe_circle_radius)
		var owner_peer_id: int = child.name.to_int()
		if owner_peer_id == host_id:
			# The host itself owns this Tiger (host is playing, not just
			# hosting) -- Godot disallows a self-targeted rpc_id() call (see
			# Ability_System_Design.md §4a's own "try_activate ห้ามยิง
			# rpc_id(1) หาตัวเอง" note for the exact same constraint on Kick),
			# so apply the correction directly through the same shared method
			# the RPC handler below calls, instead of routing through the
			# network for no reason.
			_apply_tiger_position_correction(owner_peer_id, corrected)
		else:
			# TARGETED, not broadcast (code-review + network-engineer fix):
			# only the owning peer ever acts on this correction (see
			# correct_tiger_position()'s own doc) -- every OTHER peer already
			# learns the corrected position the ordinary way, via that
			# owner's own next replicated position update, so broadcasting
			# this RPC to everyone would be pure waste (and would compound
			# any future tolerance miss into needless traffic on every peer,
			# not just the one that matters).
			correct_tiger_position.rpc_id(owner_peer_id, owner_peer_id, corrected)


## Host -> the OWNING peer ONLY (rpc_id, not a broadcast -- see the targeted
## call site above). Resolves the named Player and only ACTS if it is the
## OWNING peer of that Player (`is_multiplayer_authority()` guard, defense in
## depth even though the caller already targeted the right peer) -- same
## reasoning apply_role_switch's own doc gives for its step-6 placeholder
## teleport: position is owner-authoritative, so writing to a Player this
## peer does NOT own would just be silently overwritten by that Player's own
## next replicated update; only the owner's own write can ever actually
## matter. No call_local (unlike apply_role_switch/assign_first_tiger): the
## host-owns-the-Tiger case is handled by the caller invoking
## _apply_tiger_position_correction() directly instead (self-targeted rpc_id
## is disallowed by Godot -- see the call site's own doc), so this RPC only
## ever needs to reach a REMOTE peer.
@rpc("authority", "reliable")
func correct_tiger_position(peer_id: int, corrected_position: Vector3) -> void:
	_apply_tiger_position_correction(peer_id, corrected_position)


## Shared local-apply logic for correct_tiger_position -- extracted so both
## the RPC handler above (remote peer's own copy runs this on receipt) and
## the host's own direct call (when the host itself owns the Tiger being
## corrected, see _physics_process()'s own doc) go through the exact same
## code, rather than duplicating the lookup+guard+write.
func _apply_tiger_position_correction(peer_id: int, corrected_position: Vector3) -> void:
	var player: Node = _players_root.get_node_or_null(str(peer_id))
	if player == null:
		return
	if player.is_multiplayer_authority():
		player.position = corrected_position
