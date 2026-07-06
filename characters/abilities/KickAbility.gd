class_name KickAbility
extends HumanAbility
## KickAbility (TK-P2-01, gameplay-engineer) -- the FIRST real ability on the
## Ability System scaffold (TK-P2-16). This is the pipeline proof: owner
## intent -> host validation -> confirm/reject over the network,
## host-authoritative end to end. See
## Tiger_Kick_Project_Docs/02_Technical/Ability_System_Design.md §3 (base
## Ability API this implements), §4 (the exact "Kick walkthrough" this file
## follows verbatim), §4a (authority rules -- CRITICAL, see the notes on
## every method below), and Game_Balance.md (Kick range 1.5 m, cooldown TBD
## -- both left as @export tunables here, never hard-coded, per CLAUDE.md
## "MUST NOT hard-code tunables the GDD marks design-owned").
##
## SCOPE NOTE (no Tiger role yet -- read before "fixing" this to check role):
## TK-P2-04/09 (Role state machine / first-Tiger assignment) have not landed.
## Kick therefore lands on the NEAREST OTHER PLAYER, full stop -- there is no
## "is this the Tiger" check anywhere in this file. This is enough to prove
## the ability pipeline end-to-end (the point of this card), but is NOT the
## final rule. Once Player.role is real, host_validate() below must filter
## candidates down to role == &"tiger" before calling
## KickRules.nearest_target() -- a one-line change at that call site (the
## pure helper itself stays role-agnostic, see KickRules.gd's own doc).
##
## FOLLOW-UP (explicitly out of scope here, per the card): TK-P2-17 (Kick
## Stagger) is what actually staggers/knocks back the target on a landed
## kick -- host_apply() below only records + logs the hit and leaves a clear
## hook/comment for that card; it does NOT touch the target's velocity/state.

## Kick range, meters (Game_Balance.md: "Kick range | 1.5 m | proposed, tune
## P3; host validate distance kicker<->tiger"). @export (not hard-coded) so
## designer/producer can tune it in the Inspector once a real Kick ability
## scene/values resource exists (TK-P3-01 upgrades tunables to .tres without
## changing this contract, per design doc §2).
@export var kick_range_m: float = 1.5

## Owner-side (predicted) cooldown ledger -- see can_activate()/
## on_activate_local() below. -1 = "never fired yet" (no cooldown active).
## Deliberately SEPARATE from _host_last_fire_ms: this instance of
## KickAbility only exists on ONE peer's local Player tree (AbilityController
## rebuilds its OWN local ability children per peer, design doc §7 Step 3
## comment: ability nodes created at runtime already default to authority 1
## on every peer -- every peer has its own copy). When the owner IS the host
## (a host-owned Player), can_activate() and host_validate() run on the SAME
## node instance but must still track cooldown independently, because
## can_activate() is a PREDICTION (owner may be wrong, e.g. after a
## rejection) and host_validate() is the one authoritative ledger --
## conflating them would let an owner-side misprediction desync the real
## cooldown.
var _owner_last_fire_ms: int = -1

## HOST-authoritative cooldown ledger -- see host_validate() below. Only ever
## read/written on the host's own copy of this node (guaranteed by
## AbilityController: host_validate() is only ever called from
## _host_process_request(), which itself only runs when multiplayer.is_server()
## is true, design doc §4a). -1 = "never fired yet".
var _host_last_fire_ms: int = -1

## Cached parent Player body -- get_parent() is this ability's AbilityController
## (TK-P2-16 §2 tree: Player -> AbilityController -> [ability nodes]), so the
## owning CharacterBody3D is one level further up. Same @onready-cache pattern
## as MovementComponent/CameraComponent's own `_body` (their class docs).
@onready var _body: CharacterBody3D = get_parent().get_parent() as CharacterBody3D


func _init() -> void:
	# Overriding these here (rather than re-declaring the inherited @export
	# vars, which GDScript 4 rejects at parse time -- "member already exists
	# in parent class", confirmed while building this card) sets this
	# concrete ability's design-owned identity/wiring values without
	# touching Ability's base declarations.
	ability_id = &"kick"
	input_action = &"kick"
	cooldown_sec = 0.6 # Game_Balance.md: "Cooldowns (Kick/Pounce) | TBD | tune P3" -- 0.6s placeholder, tune later; @export so producer/designer can retune without touching code.
	# resolution stays Ability's default (HOST_AUTHORITATIVE) -- Kick decides
	# the game (design doc §3 table: "Kick, Jump-Kick, Tag, Pounce -- HOST"),
	# so we deliberately do NOT override it here.


## Owner-side precheck (design doc §4 walkthrough step 1): predicted cooldown
## only -- this is a PREDICTION for immediate local feedback, never the
## authoritative decision (that is host_validate() below, always). Runs only
## for the owning peer (AbilityController.try_activate() already gates the
## whole call chain on `_body.is_multiplayer_authority()` before reaching
## here, design doc §4a "owner check = `_body.is_multiplayer_authority()`").
func can_activate(_ctx: Dictionary) -> bool:
	return KickRules.can_fire(_owner_last_fire_ms, cooldown_sec, Time.get_ticks_msec())


## Owner-side immediate/cosmetic feedback (design doc §3: "on_activate_local"
## runs immediately, cosmetic only). Placeholder log only, per the card --
## real windup animation is Phase 4 art/animation work, out of scope here.
## Starts the OWNER's predicted cooldown clock; on_rejected() below undoes
## this if the host disagrees (e.g. no target was actually in range).
func on_activate_local(_ctx: Dictionary) -> void:
	_owner_last_fire_ms = Time.get_ticks_msec()
	GameLog.debug("[KICK] windup (owner=%s) -- awaiting host confirm" % _body.name)


## HOST-ONLY (design doc §4a: host check = `multiplayer.is_server()`, NEVER
## AbilityController's own `is_multiplayer_authority()`). Only ever reached
## via AbilityController._host_process_request(), which is only ever called
## from a context multiplayer.is_server() already guards (rpc_request_activate's
## own guard, or try_activate's host-local branch) -- the assert below is
## defense-in-depth documentation of that invariant, not a new gate.
##
## Thin shell around the pure statics in KickRules.gd (design doc §3
## testability note) -- this method itself does the two things that NEED a
## live scene tree/host clock (re-checking cooldown against the HOST's own
## ledger, and reading sibling Players' real global_position), then hands the
## actual range/target-selection DECISION to KickRules.nearest_target(),
## which GUT exercises directly with no scene tree at all.
func host_validate(ctx: Dictionary) -> Dictionary:
	assert(multiplayer.is_server(), "KickAbility.host_validate must only ever run on the host (design doc section 4a)")

	if not KickRules.can_fire(_host_last_fire_ms, cooldown_sec, Time.get_ticks_msec()):
		return {"ok": false, "reason": "cooldown", "result": null}

	var players_root: Node = _body.get_parent()
	var candidates: Array = []
	for child in players_root.get_children():
		if child == _body:
			continue # never target self
		if child is CharacterBody3D:
			# SCOPE NOTE (see class doc above): every OTHER player is a
			# candidate for now -- no role/Tiger filter exists yet.
			# TK-P2-04/09 land the Role state machine; once `role` is real,
			# filter this to `child.role == &"tiger"` before calling
			# nearest_target() below.
			candidates.append({"id": child.name, "position": child.global_position})

	var target: Dictionary = KickRules.nearest_target(_body.global_position, candidates, kick_range_m)
	if target.is_empty():
		return {"ok": false, "reason": "no_target_in_range", "result": null}

	_host_last_fire_ms = Time.get_ticks_msec()
	return {
		"ok": true,
		"reason": "",
		"result": {"kicker_id": ctx.get("sender_id"), "target_id": target.get("id")},
	}


## HOST-ONLY: apply the authoritative result. Per the card, this step only
## RECORDS + LOGS the hit -- no knockback/stagger here (that is TK-P2-17
## Kick Stagger, a separate card). GameManager does not exist yet either
## (TK-P2-15, later), so there is nothing to notify beyond this log for now;
## a future GameManager hook (e.g. `GameManager.on_kick_landed(result)`)
## would be called from right here once it exists.
func host_apply(result) -> void:
	GameLog.info("[KICK] player %s kicked player %s" % [result.get("kicker_id"), result.get("target_id")])
	# TK-P2-17 HOOK: stagger/knockback the target goes here (or via a
	# GameManager notification) once that card lands -- deliberately absent
	# in this card.


## Runs on EVERY peer once the host has broadcast rpc_confirm (design doc §3:
## the one place "the ability actually happened" for remote observers). MUST
## NOT be authoritative -- §4a explicitly calls out that a forger can make
## on_confirmed() run locally on their OWN machine (e.g. by faking the
## ability layer above this method), but that can only ever affect THEIR OWN
## screen: the authoritative effect already happened in host_apply() above,
## which only the real host can ever reach. This method is therefore
## placeholder feedback ONLY (log) and must never mutate shared/authoritative
## game state.
func on_confirmed(result) -> void:
	GameLog.info("[KICK] confirmed: kicker=%s target=%s" % [result.get("kicker_id"), result.get("target_id")])


## Owner-only (design doc §3: "owner cancels windup"). The host rejected this
## activation (out of range / on cooldown host-side / unknown ability) --
## cancel whatever on_activate_local() started. Also rolls back the OWNER's
## predicted cooldown clock: the kick never actually happened, so penalizing
## the owner with a cooldown for it would be an unearned punishment (game
## feel, gameplay-engineer's call -- not a rule/balance change).
func on_rejected(reason: String) -> void:
	_owner_last_fire_ms = -1
	GameLog.debug("[KICK] rejected: %s -- windup cancelled" % reason)

