class_name TagAbility
extends TigerAbility
## TagAbility (TK-P2-03, gameplay-engineer) -- the Tiger's Tag ACTION (step 1
## of the 7-step Tag Sequence: "grab/lock the target"). Mirrors
## characters/abilities/KickAbility.gd's exact HOST_AUTHORITATIVE pipeline
## verbatim (owner precheck -> on_activate_local -> rpc_request_activate ->
## host_validate -> host_apply + rpc_confirm -> on_confirmed/on_rejected).
## See Tiger_Kick_Project_Docs/02_Technical/Ability_System_Design.md section 3
## (base Ability API), section 4 (the Kick walkthrough this file follows),
## section 4a (authority rules -- CRITICAL, see every method below), section
## 4b (TagDetector's RPC-free invariant -- this file is the "host-authority
## node" that invariant requires; TagDetector itself gets NO changes), and
## section 5 (Role-swap, which GameManager -- not this file -- actually
## performs once this ability's host_apply() kicks off the Tag Sequence).
##
## SCOPE (per the card, mirrors KickAbility's own scope note verbatim): this
## file is ONLY step 1 (grab confirmed). Steps 2-7 (throw-to-ground,
## transform-effect, role swap x2, exit-Safe-Circle placeholder, clear lock)
## are CONSEQUENCES of a successful activation here, not separately
## player-triggered -- they live on managers/GameManager.gd
## (start_tag_sequence(), called from host_apply() below), per the card's
## explicit design: "steps 2-7 are consequences of step 1's successful
## ability activation, not separately player-triggered".
##
## MANDATORY re-trigger guard (from TK-P2-02's human-test finding, recorded
## in this card's backlog notes): a boundary-jitter Area3D overlap re-fires
## tag_target_in_range/tag_target_left_range repeatedly within the same
## second when a player stands right at the ~2m range edge. A cooldown
## ledger alone is not enough to prevent a rapid-fire re-tag off that jitter
## -- host_validate() below ALSO rejects (reason "sequence_active") while
## GameManager reports a Tag Sequence is already running, which holds for
## the sequence's full multi-second duration, not just one cooldown window.
## See managers/TagSequenceRules.can_start_sequence()'s own doc.

## Tag range, meters. @export (not hard-coded), same placeholder-tuning
## discipline as KickAbility.kick_range_m -- see
## characters/components/TagDetectorComponent.gd's own doc comment on why
## 2.0 m is a placeholder pending designer input (no locked Game_Balance.md
## entry yet). Deliberately matches TagDetectorComponent.tag_range_m's own
## default so the Tiger's grab range agrees with the sensor that fed this
## card's candidate list in the first place; NOT the same @export instance
## (they can be retuned independently once a designer actually locks values).
@export var tag_range_m: float = 2.0

## Owner-side (predicted) cooldown ledger -- see can_activate()/
## on_activate_local() below, same "SEPARATE from _host_last_fire_ms"
## reasoning KickAbility.gd's own doc explains in full (every peer builds its
## OWN ability children, design doc section 7 Step 3; can_activate() is a
## PREDICTION, host_validate() is the one authoritative ledger). -1 = "never
## fired yet".
var _owner_last_fire_ms: int = -1

## HOST-authoritative cooldown ledger -- see host_validate() below. Only ever
## read/written on the host's own copy of this node (guaranteed the same way
## KickAbility's own _host_last_fire_ms is: host_validate() is only ever
## reached via AbilityController._host_process_request(), itself only ever
## called from a context multiplayer.is_server() already guards). -1 = "never
## fired yet".
var _host_last_fire_ms: int = -1

## Cached parent Player body -- get_parent() is this ability's
## AbilityController (design doc section 2 tree: Player -> AbilityController
## -> [ability nodes]), so the owning CharacterBody3D is one level further
## up. Same @onready-cache pattern as KickAbility/MovementComponent/
## CameraComponent's own _body. Declared BEFORE _tag_detector below so
## GDScript resolves it first (top-to-bottom @onready order) -- _tag_detector
## depends on it.
@onready var _body: CharacterBody3D = get_parent().get_parent() as CharacterBody3D

## The Tiger's own TagDetector sibling (design doc section 2 tree: Player ->
## TagDetector, a sibling of AbilityController -- see
## characters/components/TagDetectorComponent.gd, TK-P2-02, closed/locked).
## Equivalent to get_parent().get_parent().get_node("TagDetector") from this
## node (get_parent().get_parent() IS _body above) -- this ability reads it
## exactly the way that card's own HAND-OFF CONTRACT describes ("POLL:
## get_candidates_in_range()"), never touching TagDetectorComponent's
## detection/emission logic itself (locked, TK-P2-02 is closed).
@onready var _tag_detector: Area3D = _body.get_node("TagDetector") as Area3D

func _init() -> void:
	# Overriding these here (rather than re-declaring the inherited @export
	# vars -- GDScript 4 rejects that, "member already exists in parent
	# class", per KickAbility.gd's own note) sets this concrete ability's
	# design-owned identity/wiring values without touching Ability's base
	# declarations.
	ability_id = &"tag"
	input_action = &"tag" # project.godot InputMap action `tag` (same physical
	# left-mouse-button as `kick` -- Tiger/Outer catalogs are mutually
	# exclusive per role, so no input conflict; see
	# AbilityController._unhandled_input's per-role `_abilities` iteration).
	cooldown_sec = 0.6 # Placeholder, same value/rationale as KickAbility's own
	# cooldown_sec -- no locked Game_Balance.md entry for Tag cooldown yet,
	# tune Phase 3. @export so producer/designer can retune without touching
	# code.
	# resolution stays Ability's default (HOST_AUTHORITATIVE) -- Tag decides
	# the game (design doc section 3 table: "Kick, Jump-Kick, Tag, Pounce --
	# HOST"), so we deliberately do NOT override it here.


## Owner-side precheck (design doc section 4 walkthrough step 1, mirrored
## from KickAbility.can_activate() verbatim): predicted cooldown only -- a
## PREDICTION for immediate local feedback, never the authoritative decision
## (host_validate() below always is). Runs only for the owning peer
## (AbilityController.try_activate() already gates the whole call chain on
## _body.is_multiplayer_authority(), design doc section 4a).
func can_activate(_ctx: Dictionary) -> bool:
	return TagAbilityRules.can_fire(_owner_last_fire_ms, cooldown_sec, Time.get_ticks_msec())


## Owner-side immediate/cosmetic feedback (design doc section 3:
## on_activate_local runs immediately, cosmetic only). Placeholder log only
## -- real grab-windup animation is Phase 4 art/animation work (same
## TK-P4-xx-hook-shaped deferral KickAbility.on_activate_local() documents
## for its own windup). Starts the OWNER's predicted cooldown clock;
## on_rejected() below undoes this if the host disagrees.
func on_activate_local(_ctx: Dictionary) -> void:
	_owner_last_fire_ms = Time.get_ticks_msec()
	GameLog.debug("[TAG] grab windup (owner=%s) -- awaiting host confirm" % _body.name)


## HOST-ONLY (design doc section 4a: host check = multiplayer.is_server(),
## NEVER AbilityController's own is_multiplayer_authority()). Only ever
## reached via AbilityController._host_process_request(), same invariant
## KickAbility.host_validate()'s own assert documents.
##
## Order of checks (per the card): (1) re-trigger guard -- reject
## "sequence_active" while GameManager reports a Tag Sequence already running
## (mandatory, see class doc above); (2) this ability's OWN cooldown ledger;
## (3) target selection, delegated to TagRules.nearest_candidate() (TK-P2-02,
## unchanged) fed by this Tiger's own TagDetector.get_candidates_in_range()
## (TK-P2-02, unchanged) -- thin shell around pure statics, same
## "host_validate does the two things that NEED a live scene tree, hands the
## actual decision to a pure static" split KickAbility.host_validate()
## documents.
func host_validate(ctx: Dictionary) -> Dictionary:
	assert(multiplayer.is_server(), "TagAbility.host_validate must only ever run on the host (design doc section 4a)")

	var gm: Node = _game_manager()
	if gm == null:
		# Defensive/fail-closed: every production scene this ability can ever
		# run in (world/TestArena.tscn) ships a GameManager sibling of
		# Players/PlayerSpawner -- reaching this branch means the scene is
		# missing it, which is a setup bug, not a normal rejection. Fail
		# closed rather than let host_apply() crash on a null GameManager.
		GameLog.error("[TAG] host_validate: no GameManager found under the arena -- rejecting (scene setup bug?)")
		return {"ok": false, "reason": "no_game_manager", "result": null}

	if gm.is_sequence_active():
		return {"ok": false, "reason": "sequence_active", "result": null}

	if not TagAbilityRules.can_fire(_host_last_fire_ms, cooldown_sec, Time.get_ticks_msec()):
		return {"ok": false, "reason": "cooldown", "result": null}

	var candidates: Array = _tag_detector.get_candidates_in_range()
	var target: Dictionary = TagRules.nearest_candidate(_body.global_position, candidates, tag_range_m)
	if target.is_empty():
		return {"ok": false, "reason": "no_target_in_range", "result": null}

	_host_last_fire_ms = Time.get_ticks_msec()
	return {
		"ok": true,
		"reason": "",
		"result": {"tagger_id": ctx.get("sender_id"), "target_id": target.get("id")},
	}


## HOST-ONLY: apply the authoritative result. Per the card, step 1 (grab
## confirmed) hands off IMMEDIATELY to GameManager.start_tag_sequence(),
## which runs steps 2-7 as consequences of this call -- this ability itself
## never touches role/position/lock state directly (design doc section 8:
## "GameManager = owner of role + Tag Sequence 7 steps -- ability does not
## swallow match flow").
func host_apply(result) -> void:
	GameLog.info("[TAG] player %s tagged player %s -- handing off to Tag Sequence" % [result.get("tagger_id"), result.get("target_id")])
	var gm: Node = _game_manager()
	if gm == null:
		# host_validate() above already checked this and would have rejected
		# first -- unreachable in practice (same "defense in depth" shape as
		# KickAbility/AbilityController's own belt-and-suspenders guards), but
		# fail loudly rather than crash on a null call if it ever happens
		# (e.g. GameManager freed mid-request by some future scene-teardown
		# race).
		GameLog.error("[TAG] host_apply: GameManager vanished between host_validate and host_apply -- Tag Sequence NOT started")
		return
	gm.start_tag_sequence(result.get("tagger_id"), result.get("target_id"))


## Runs on EVERY peer once the host has broadcast rpc_confirm (design doc
## section 3: the one place "the ability actually happened" for remote
## observers). Placeholder feedback ONLY (log) -- must never mutate
## shared/authoritative game state (section 4a). The actual
## role-swap/exit/lock-clear steps everyone OBSERVES arrive separately via
## GameManager's own apply_role_switch RPC (design doc section 5), not
## through this method.
func on_confirmed(result) -> void:
	GameLog.info("[TAG] confirmed: tagger=%s target=%s" % [result.get("tagger_id"), result.get("target_id")])


## Owner-only (design doc section 3: "owner cancels windup"). The host
## rejected this activation (sequence already active / on cooldown host-side
## / out of range / no GameManager) -- cancel whatever on_activate_local()
## started and roll back the OWNER's predicted cooldown clock, same "the tag
## never actually happened, so penalizing the owner with a cooldown for it
## would be an unearned punishment" reasoning KickAbility.on_rejected()
## documents.
func on_rejected(reason: String) -> void:
	_owner_last_fire_ms = -1
	GameLog.debug("[TAG] rejected: %s -- grab windup cancelled" % reason)


## HOST-ONLY lookup: GameManager lives as a sibling of Players/PlayerSpawner
## under world/TestArena.tscn's root (mirrors networking/PlayerSpawner.gd's
## own scene-local, non-autoload placement) -- reached the same way
## KickAbility.host_validate() already walks up to the "Players" root
## (_body.get_parent()), one level further: _body.get_parent() is the
## "Players" node, .get_parent() of THAT is the arena root GameManager is a
## direct child of. get_node_or_null (not get_node) so a scene missing
## GameManager fails soft (null) into host_validate()/host_apply()'s own
## explicit fail-closed handling above, rather than an uncaught engine error.
func _game_manager() -> Node:
	var players_root: Node = _body.get_parent()
	var arena: Node = players_root.get_parent()
	return arena.get_node_or_null("GameManager")
