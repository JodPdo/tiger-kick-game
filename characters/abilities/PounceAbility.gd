class_name PounceAbility
extends TigerAbility
## PounceAbility (TK-P2-18, gameplay-engineer) -- the Tiger's short burst
## dash. Tiger_Kick_Project_Docs/01_Design/Game_Balance.md section 3 locked
## design intent: "Tiger = ambush hunter (hunt, not chase). Tiger is
## slower-or-equal to Humans; it catches via Pounce + reading the moment
## someone comes in to kick, NOT by chasing." Pounce is the Tiger's ONLY way
## to close distance (Sprint gives the Tiger zero speed advantage over a
## walking Human by design, see MovementComponent.gd's own
## tiger_walk_speed/tiger_sprint_speed doc). Game_Balance.md section 4:
## "Pounce burst | ~8 m/s short range | card TK-P2-18 (TigerAbility, HOST
## validate)".
##
## SCOPE BOUNDARY (read before "fixing" this to auto-tag on landing): despite
## the backlog card's Thai title translating to "the main catch mechanic",
## Pounce itself does NOT catch/tag anyone -- it only moves the Tiger.
## characters/abilities/TagAbility.gd (TK-P2-03, closed/locked, NOT touched by
## this card) remains the separate ability that performs the actual grab once
## a Tiger is in Tag range. Pounce's contract ends at "the Tiger got a short
## burst of speed" -- it is the tool that gets the Tiger INTO tag range, not
## the ability that catches. (If a future card wants Pounce to directly chain
## into a Tag Sequence, that is a design-scope change -- movement-only vs.
## movement+auto-catch -- needing designer/architect sign-off, not an
## implementer's call; not decided here.)
##
## ARCHITECTURE (the one genuinely new problem this card introduces): every
## other HOST_AUTHORITATIVE ability so far (Kick, Tag) DECIDES something
## host-side but does not itself move anyone -- Pounce's entire effect IS
## movement, and Player position in this codebase stays OWNER-AUTHORITATIVE
## one-way sync (architect ruling TK-P2-28, Change Log [0.45] / Game_
## Balance.md section 6 "Known Limitations"). So the burst VELOCITY is
## applied OWNER-SIDE, immediately, in on_activate_local() below -- via a new
## seam on MovementComponent (start_pounce_burst()/cancel_pounce_burst(), see
## that file's own doc) -- going further than Kick/Tag's "windup only"
## prediction: here the movement ITSELF is the prediction, because there is
## no windup-then-wait, the burst has to feel instant. host_validate() below
## therefore only gates LEGALITY (cooldown, sequence_active) -- there is no
## target/range decision here the way Kick/Tag have one -- and
## host_apply()/on_confirmed() are log-only (nothing authoritative left to
## apply; the movement already happened owner-side, and every peer simply
## SEES it via the normal owner-authoritative position-sync path, the same
## way ordinary walk/sprint/jump movement already replicates with no
## ability-layer involvement at all). on_rejected() below is the one place
## genuinely different from Kick/Tag's own template -- see that method's doc.

## TK-P3-01 (tools-devops): the actual, externally-editable source of truth
## for every value below is now this Resource, not the class-level literals
## sitting next to each @export var -- see
## characters/abilities/tuning/PounceTuning.gd's own class doc (and, for the
## full "why a Resource" investigation,
## characters/abilities/tuning/KickTuning.gd's own class doc). Defaults to
## the project's own placeholder asset; `_init()` below copies its fields
## onto `pounce_speed_mps`/`pounce_duration_sec`/`cooldown_sec` once, at
## construction.
@export var tuning: PounceTuning = preload("res://characters/abilities/tuning/pounce_tuning.tres")

## Burst speed, m/s. Game_Balance.md section 4 locked-ish value (~8.0 m/s
## short burst) -- @export (not hard-coded) per CLAUDE.md's "expose
## design-owned tunables" rule, same as every other balance value in this
## codebase, even though this one is closer to locked than most. Kept as a
## plain @export (rather than removed) so this ability's external contract
## is unchanged; the VALUE actually driving gameplay comes from `tuning`
## above as of TK-P3-01 (see `_init()` below) -- edit
## tuning/pounce_tuning.tres, not this literal, to retune.
@export var pounce_speed_mps: float = 8.0

## Burst duration, seconds -- NOT specified anywhere in the docs (Game_
## Balance.md section 4 only locks the m/s figure, not how long the burst
## lasts); placeholder pending designer lock, same "TBD, tune P3" discipline
## every other un-locked tunable in this codebase already follows (see
## KickAbility.kick_range_m/cooldown_sec's own doc). Picked so ONE burst
## covers roughly 2.5-3m (8.0 m/s times 0.35s equals about 2.8m) -- enough
## to close the final approach from just outside TagAbility's own
## tag_range_m (2.0m) plus margin, without covering the ENTIRE Safe Circle
## radius (5.0m, MovementComponent.safe_circle_radius) in a single press,
## keeping Pounce a distance-closer, not a teleport across the whole circle.
## TK-P3-01: same "kept for contract, actual value comes from `tuning`
## above" posture as pounce_speed_mps's own doc.
@export var pounce_duration_sec: float = 0.35

## Cooldown, seconds. Game_Balance.md section 4: "Cooldowns (Kick/Pounce) --
## TBD -- tune P3" -- same un-locked status as KickAbility/TagAbility's own
## cooldown_sec (set in _init() below, per the "GDScript rejects
## re-declaring an inherited @export var" note KickAbility.gd's own _init()
## explains), but deliberately picked LONGER than Kick/Tag's 0.6s
## placeholder: Pounce is the Tiger's only speed-advantage tool (Sprint
## grants none, by design, Game_Balance.md section 3) -- a short cooldown
## would let repeated Pounces effectively let the Tiger CHASE by spamming
## bursts, directly undermining the locked "hunt, not chase" intent this
## whole card exists to let the team feel-test. @export so producer/designer
## can retune without touching code once real playtest data exists. TK-P3-01:
## same "kept for contract, actual value comes from `tuning` above" posture
## as pounce_speed_mps's own doc.

## Cached parent Player body -- same @onready pattern as
## KickAbility/TagAbility's own _body (get_parent() is this ability's
## AbilityController, one level further up is the owning CharacterBody3D).
@onready var _body: CharacterBody3D = get_parent().get_parent() as CharacterBody3D

## The Tiger's own MovementComponent sibling (Player.tscn tree: Player ->
## MovementComponent - CameraComponent - AbilityController -> [abilities],
## see MovementComponent.gd's start_pounce_burst()/cancel_pounce_burst()/own
## class doc). Reached the same sideways sibling-node-path way TagAbility
## reaches its own TagDetector sibling -- see that file's own doc for why
## this raw reach-around is an established pattern in this codebase, not a
## stopgap. Typed Node (not a concrete class) because MovementComponent.gd
## declares no class_name -- same "call a script-only method through a
## builtin-typed reference" shape TagAbility already uses for
## _tag_detector.get_candidates_in_range().
@onready var _movement: Node = _body.get_node("MovementComponent")

## CameraRig sibling -- read-only, for its current yaw (see
## on_activate_local() below), same sideways reach MovementComponent/
## CameraComponent already both use for the exact same node (see
## MovementComponent.gd's own class doc for why two-plus siblings reading the
## same rotation.y is a known, harmless, deliberate coupling in this
## codebase, not a bug).
@onready var _camera_rig: Node3D = _body.get_node("CameraRig") as Node3D

## MovementComponent has no class_name (preloaded by path everywhere else in
## this codebase too, e.g. tests/test_player_movement.gd/test_jump_rules.gd)
## -- preloaded here only to reuse its pure camera_relative_dir() static (see
## on_activate_local() below), not to instantiate a second copy.
const MovementComponentScript := preload("res://characters/components/MovementComponent.gd")

## Owner-side (predicted) cooldown ledger -- see can_activate()/
## on_activate_local() below, same "SEPARATE from _host_last_fire_ms"
## reasoning KickAbility.gd/TagAbility.gd's own docs explain in full (every
## peer builds its OWN ability children, design doc section 7 Step 3;
## can_activate() is a PREDICTION, host_validate() is the one authoritative
## ledger). -1 = "never fired yet".
var _owner_last_fire_ms: int = -1

## HOST-authoritative cooldown ledger -- see host_validate() below. Only ever
## read/written on the host's own copy of this node, same guarantee Kick/Tag's
## own _host_last_fire_ms already documents (host_validate() is only ever
## reached via AbilityController._host_process_request(), itself only ever
## called from a context multiplayer.is_server() already guards). -1 = "never
## fired yet".
var _host_last_fire_ms: int = -1


func _init() -> void:
	# Overriding these here (rather than re-declaring the inherited @export
	# vars, which GDScript 4 rejects at parse time) sets this concrete
	# ability's design-owned identity/wiring values without touching
	# Ability's base declarations -- same pattern KickAbility.gd/
	# TagAbility.gd's own _init() already use.
	ability_id = &"pounce"
	input_action = &"pounce" # project.godot InputMap action `pounce` -- NEW
	# for this card, bound to the right mouse button (button_index 2): the
	# Tiger's two abilities then live one per mouse button (left = Tag grab,
	# already `tag`; right = Pounce dash) -- matches the existing "one
	# physical control per ability" pattern kick/tag already established. No
	# input conflict with Outer's `kick` (also left mouse button): Tiger and
	# Outer catalogs are mutually exclusive per role (AbilityController.
	# _unhandled_input's per-role _abilities iteration), so only one of
	# kick/tag/pounce is ever registered for a given Player at a time.
	# TK-P3-01: pounce_speed_mps/pounce_duration_sec/cooldown_sec are now
	# sourced from `tuning` (see that @export var's own doc above) rather
	# than a literal here -- edit tuning/pounce_tuning.tres to retune, not
	# this file. Same "defends against a hypothetical null tuning" guard
	# KickAbility.gd's own _init() uses.
	if tuning != null:
		pounce_speed_mps = tuning.pounce_speed_mps
		pounce_duration_sec = tuning.pounce_duration_sec
		cooldown_sec = tuning.cooldown_sec
	# resolution stays Ability's default (HOST_AUTHORITATIVE) -- Pounce
	# decides the game the same "Kick, Jump-Kick, Tag, Pounce -- HOST" way
	# Kick/Tag's own _init() docs cite (design doc section 3 resolution
	# table), so we deliberately do NOT override it here.


## Owner-side precheck (design doc section 4 walkthrough step 1, mirrored
## from KickAbility.can_activate()/TagAbility.can_activate() verbatim):
## predicted cooldown only -- a PREDICTION for immediate local feedback,
## never the authoritative decision (host_validate() below always is). Runs
## only for the owning peer (AbilityController.try_activate() already gates
## the whole call chain on _body.is_multiplayer_authority(), design doc
## section 4a).
func can_activate(_ctx: Dictionary) -> bool:
	return PounceRules.can_fire(_owner_last_fire_ms, cooldown_sec, Time.get_ticks_msec())


## Owner-side IMMEDIATE EXECUTION -- not just cosmetic feedback the way
## KickAbility/TagAbility's own on_activate_local() are (see class doc above
## for why Pounce goes further): starts the burst on THIS peer's own
## MovementComponent right away, so the dash feels instant rather than
## waiting on a host round-trip. on_rejected() below undoes this if the host
## disagrees (cooldown/sequence_active raced the owner's own prediction).
##
## Direction: the Tiger's current WASD input direction if any movement key
## is held (rotated camera-relative, the SAME rotation MovementComponent.
## _physics_process() already applies to ordinary movement, reused here via
## MovementComponentScript.camera_relative_dir() rather than re-deriving the
## rotation math a second time) -- falling back to pure camera-forward
## (Input.get_vector's own "forward" convention, (0,-1) on the y axis) when
## no movement key is held, so pressing Pounce with no WASD input still does
## something sensible (dash straight ahead) instead of a degenerate
## zero-length burst. This is a feel detail Phase 3 may retune, not a locked
## spec -- documenting the choice here per the card's own instruction.
func on_activate_local(_ctx: Dictionary) -> void:
	_owner_last_fire_ms = Time.get_ticks_msec()
	var input_dir: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	)
	if input_dir == Vector2.ZERO:
		input_dir = Vector2(0.0, -1.0) # no key held -- default to camera-forward
	var direction: Vector3 = MovementComponentScript.camera_relative_dir(
		input_dir, _camera_rig.rotation.y
	)
	_movement.start_pounce_burst(direction, pounce_speed_mps, pounce_duration_sec)
	GameLog.debug("[POUNCE] burst fired (owner=%s) -- awaiting host confirm" % _body.name)


## HOST-ONLY (design doc section 4a: host check = multiplayer.is_server(),
## NEVER AbilityController's own is_multiplayer_authority()). Only ever
## reached via AbilityController._host_process_request(), same invariant
## Kick/Tag's own host_validate() asserts already document.
##
## LEGALITY ONLY -- unlike Kick/Tag, there is no target/range decision here
## at all (Pounce doesn't select anyone, see class doc above): (1)
## re-trigger guard mirrors TagAbility.host_validate()'s own
## "sequence_active" rejection -- pouncing while the Tiger is locked in the
## grab/throw/transform Tag Sequence animation doesn't make sense (small
## defensive addition, not a design-rule change; see _game_manager()'s own
## doc for why this fails OPEN rather than closed when GameManager is
## missing, unlike TagAbility); (2) this ability's own cooldown ledger, same
## shape Kick/Tag already use.
func host_validate(ctx: Dictionary) -> Dictionary:
	assert(multiplayer.is_server(), "PounceAbility.host_validate must only ever run on the host (design doc section 4a)")

	var gm: Node = _game_manager()
	if gm != null and gm.is_sequence_active():
		return {"ok": false, "reason": "sequence_active", "result": null}

	if not PounceRules.can_fire(_host_last_fire_ms, cooldown_sec, Time.get_ticks_msec()):
		return {"ok": false, "reason": "cooldown", "result": null}

	_host_last_fire_ms = Time.get_ticks_msec()
	return {"ok": true, "reason": "", "result": {"tiger_id": ctx.get("sender_id")}}


## HOST-ONLY: log only -- see class doc above for why there is nothing left
## to authoritatively apply here (the burst already happened owner-side, in
## on_activate_local() above; GameManager does not need to know a Pounce
## happened for anything today). Same "record + log, nothing else" shape
## KickAbility.host_apply() uses for its own still-hookless card.
func host_apply(result) -> void:
	GameLog.info("[POUNCE] tiger %s burst" % result.get("tiger_id"))


## Runs on EVERY peer once the host has broadcast rpc_confirm -- cosmetic log
## only, same "must never mutate authoritative game state" rule Kick/Tag's
## own on_confirmed() already document. Remote peers do not need to do
## ANYTHING here to SEE the Tiger move -- that already happens for free via
## the normal owner-authoritative position sync (Player.tscn's
## MultiplayerSynchronizer), the exact same way ordinary walk/sprint/jump
## movement already replicates with no ability-layer involvement at all.
func on_confirmed(result) -> void:
	GameLog.info("[POUNCE] confirmed: tiger=%s" % result.get("tiger_id"))


## Owner-only (design doc section 3: "owner cancels windup"). The host
## rejected this activation (cooldown / sequence_active, host-side) -- THE
## ONE STEP GENUINELY DIFFERENT from Kick/Tag's own on_rejected() template
## (see class doc above): unlike a windup animation (nothing physically
## happened yet), Pounce already started REAL movement in on_activate_local()
## above -- cancel_pounce_burst() stops it in flight (MovementComponent.
## resolve_horizontal_velocity() falls back to normal WASD the very next
## physics tick). Also rolls back the owner-predicted cooldown clock, same
## "the ability never actually happened, so penalizing the owner with a
## cooldown for it would be an unearned punishment" reasoning Kick/Tag's own
## on_rejected() already documents.
##
## Null-guards _movement: on a bare PounceAbility.new() never added to a
## tree (e.g. tests/test_pounce_rules.gd's owner-cooldown-rollback coverage,
## mirroring tests/test_kick_rules.gd's own bare-instance tests), @onready
## vars are never resolved -- this guard keeps on_rejected()'s cooldown
## rollback GUT-testable with no scene tree, the same way KickAbility.
## on_rejected() already is. In real (non-test) play a rejection can only
## ever follow a live, in-tree on_activate_local() call, so _movement is
## guaranteed non-null there.
func on_rejected(reason: String) -> void:
	_owner_last_fire_ms = -1
	if _movement != null:
		_movement.cancel_pounce_burst()
	GameLog.debug("[POUNCE] rejected: %s -- burst cancelled" % reason)


## HOST-ONLY lookup: same "GameManager as a sibling of Players/PlayerSpawner
## under world/TestArena.tscn's root" reach TagAbility._game_manager()
## already documents/implements verbatim (duplicated here rather than
## shared -- there is no common ability-utility file this codebase currently
## reuses across abilities for tree lookups; a THIRD copy of this exact
## method would be the point to actually consider extracting one -- flagged
## here, not decided unilaterally).
##
## get_node_or_null (not get_node), and DELIBERATELY fails OPEN when missing
## -- unlike TagAbility, Pounce does not NEED GameManager to exist in order
## to function at all (its core effect is pure movement, not a match-flow
## handoff): a scene with no GameManager simply skips the sequence_active
## guard above (see host_validate()) rather than rejecting every Pounce
## outright the way TagAbility's own missing-GameManager path deliberately
## does (TagAbility genuinely cannot proceed without one, since it must call
## start_tag_sequence()).
func _game_manager() -> Node:
	var players_root: Node = _body.get_parent()
	var arena: Node = players_root.get_parent()
	return arena.get_node_or_null("GameManager")
