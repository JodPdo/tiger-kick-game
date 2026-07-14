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
## same way TK-P2-02's sensor placement was): this node owns ONLY the Tag
## Sequence + its lock. It is explicitly NOT the full match state machine
## (WaitingRoom -> Countdown -> Playing -> MatchEnd, TK-P2-15, a separate
## still-todo card) -- step 7 ("return to Playing") here means "clear this
## lock", nothing more; no global match-state enum is introduced by this
## file. Assigning the first Tiger (TK-P2-09) and the Role state machine
## itself (TK-P2-04) are also separate, still-todo cards -- this file only
## reacts to a Tag Sequence that TagAbility already validated as legitimate;
## it does not decide who becomes Tiger on its own initiative.
##
## Step 2 (throw-to-ground) and step 3 (transform-effect) below are TIMER
## STUBS ONLY -- Phase 4 polish (TK-P4-0x) replaces both with real
## animation/VFX; the "TK-P4-xx HOOK" comments mark exactly where, same
## shape as KickAbility.host_apply()'s own TK-P2-17 stagger hook comment.
## Step 6 (move the old tiger outside the Safe Circle) is a PLACEHOLDER
## teleport -- Safe Circle itself does not exist yet (TK-P2-06, still todo)
## -- explicitly flagged non-final here, does not block on that card.
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

## Seconds the stub throw-to-ground step "plays" before the transform stub
## starts. Placeholder pending TK-P4-0x real animation -- @export so
## producer/designer can retune without touching code (CLAUDE.md: expose
## design-owned tunables, never hard-code).
@export var throw_stub_sec: float = 0.6

## Seconds the stub transform-effect step "plays" before the role swap
## resolves. Same placeholder/@export reasoning as throw_stub_sec above.
@export var transform_stub_sec: float = 0.6

## PLACEHOLDER exit radius (meters from the arena center, world origin) the
## old tiger is teleported to for step 6 -- Safe Circle (TK-P2-06) does not
## exist yet, so this is a rough "somewhere outside the ring" stand-in, NOT a
## real Safe-Circle-boundary exit. world/TestArena.tscn's own
## SafeCircleMarker ships outer_radius = 5.0 (see that scene) -- picked
## slightly larger here on the same "give some margin" placeholder reasoning
## KickAbility/TagDetectorComponent's own placeholder tunables use elsewhere
## in this codebase. Flag for designer once TK-P2-06 lands for real.
@export var exit_radius_m: float = 6.0

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
