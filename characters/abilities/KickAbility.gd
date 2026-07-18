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
## SCOPE NOTE (historical -- role filter now landed, kept for context): before
## TK-P2-04/09 (Role state machine / first-Tiger assignment) existed, Kick
## landed on the NEAREST OTHER PLAYER, full stop -- there was no "is this the
## Tiger" check anywhere in this file. That was enough to prove the ability
## pipeline end-to-end (the point of TK-P2-01) but was never the final rule.
## TK-P2-32 (gameplay-engineer) closed the gap: host_validate() below now
## filters candidates down to role == RoleRules.TIGER before calling
## KickRules.nearest_target() -- a one-line change at that call site (the
## pure helper itself stays role-agnostic, see KickRules.gd's own doc). See
## tests/test_kick_rules.gd's mixed-role host_validate() coverage for the
## regression this closes (an Outer candidate strictly closer than the Tiger
## must never be picked).
##
## TK-P2-17 (Kick Stagger, gameplay-engineer): landed. host_apply() below
## still only records + logs the hit -- there is no server-side stagger
## bookkeeping to add (see that method's own doc for why). The actual
## stagger EFFECT lives in on_confirmed() below instead: every peer already
## receives the confirmed {kicker_id, target_id} via AbilityController's
## existing rpc_confirm broadcast (design doc §3), so the TARGETED player's
## own client recognizes itself there and applies a decaying knockback to
## itself locally via a new characters/components/MovementComponent.gd seam
## (start_stagger()/resolve_stagger_knockback()) -- no new RPC needed. See
## on_confirmed()'s own doc below for the full reasoning, including why this
## is additive (not an override) to satisfy the card's hard "no full stun"
## requirement.
##
## SCOPE NOTE (historical -- found during TK-P2-17, fixed by TK-P2-32, kept
## for context): at the time TK-P2-17 landed, host_validate() below still
## targeted the NEAREST OTHER PLAYER regardless of role (see the class doc
## SCOPE NOTE above) -- the TK-P2-04/09 role filter that comment anticipated
## had never actually been applied here, even though both those cards were
## already closed. Kick Stagger is specifically a TIGER effect per
## Game_Balance.md §4 ("เสือเซ" -- "the Tiger staggers"), so on_confirmed()
## below ADDITIONALLY gated on a Tiger-role check before applying a stagger.
## TK-P2-32 (gameplay-engineer) has since closed the host_validate() gap
## directly (see the class doc SCOPE NOTE above).
##
## SCOPE NOTE (TK-BUG-P2-01, gameplay-engineer, bug fix -- SUPERSEDES the
## on_confirmed() gate description this comment originally carried): the
## Tiger-role gate described above was, until this fix, checked against
## `_body.role` -- but `_body` in on_confirmed() is always the KICKER's own
## Player node (Kick lives on the kicker's own AbilityController, see the
## class doc top comment), never the target's, so `_body.role ==
## RoleRules.TIGER` was permanently false (the kicker is by definition never
## the Tiger it just kicked) and the whole stagger effect was structurally
## unreachable at any N -- filed from TK-P2-17's own human 2-instance test
## (12 kicks, zero stagger). on_confirmed() below now explicitly RESOLVES the
## confirmed target's own Player node off the shared "Players" root first,
## and evaluates every gate (ownership + role) against THAT resolved node --
## see on_confirmed()'s own doc for the full fix.

## Kick range, meters (Game_Balance.md: "Kick range | 1.5 m | proposed, tune
## P3; host validate distance kicker<->tiger"). @export (not hard-coded) so
## designer/producer can tune it in the Inspector once a real Kick ability
## scene/values resource exists (TK-P3-01 upgrades tunables to .tres without
## changing this contract, per design doc §2).
@export var kick_range_m: float = 1.5

## Kick Stagger duration, seconds (TK-P2-17, gameplay-engineer). Game_
## Balance.md §4: "Kick Stagger | เสือเซ ~0.3s + ดันถอยเล็กน้อย (ห้าม stun
## เต็ม)" -- this is the one semi-locked number for this mechanic (~0.3s), so
## kept AT that value rather than treated as a free placeholder the way
## stagger_knockback_speed_mps below is. Still @export (not hard-coded) per
## CLAUDE.md's "expose design-owned tunables" rule, same as every other
## balance value in this file, so producer/designer can retune the "~"
## without touching code. Passed straight through to
## characters/components/MovementComponent.gd's start_stagger() in
## on_confirmed() below.
@export var stagger_duration_sec: float = 0.3

## Kick Stagger knockback speed, m/s, at the INSTANT of impact -- decays
## LINEARLY to 0 over stagger_duration_sec (see
## characters/components/StaggerRules.gd's decayed_speed() and
## characters/components/MovementComponent.gd's start_stagger()/
## resolve_stagger_knockback() for the actual decay math and the "why
## additive, why linear" reasoning behind this card's "stagger, not stun"
## requirement). NOT specified anywhere in the docs (Game_Balance.md §4 only
## locks "ดันถอยเล็กน้อย" -- "push back slightly" -- with no m/s figure), so
## this is a genuine placeholder pending designer lock, same "TBD, tune P3"
## discipline every other un-locked tunable in this codebase already follows
## (see kick_range_m/cooldown_sec's own docs above, and
## characters/abilities/PounceAbility.pounce_duration_sec's own doc for the
## closest precedent of an un-locked companion value sitting next to a
## locked one). Picked equal to MovementComponent.tiger_walk_speed (4.0 m/s)
## -- "slightly" pushed, not flung: decaying LINEARLY from this speed over
## 0.3s, the total knockback displacement averages out to roughly 0.6m
## (½ × 4.0 m/s × 0.3s), a noticeable shove without covering serious ground,
## well short of e.g. a single Pounce burst's ~2.8m
## (PounceAbility.pounce_speed_mps × pounce_duration_sec).
@export var stagger_knockback_speed_mps: float = 4.0

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

## TK-BUG-P2-01 (gameplay-engineer, bug fix): NO cached `_movement` @onready
## sibling here (unlike characters/abilities/PounceAbility.gd's own
## `_movement`, which is correct for Pounce because a TigerAbility's `_body`
## really is the acting Tiger). Kick is a HumanAbility living on the KICKER's
## own AbilityController/Player subtree -- `_body` below is ALWAYS the kicker,
## never the staggered target -- so on_confirmed() below must resolve the
## TARGET's own MovementComponent fresh, off the resolved target Player node,
## every time it runs (see on_confirmed()'s own doc for the full root-cause
## explanation). A `_body`-anchored `_movement` cache here was exactly the bug
## (TK-BUG-P2-01): it always pointed at the kicker's own MovementComponent,
## never the target's.


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
			# TK-P2-32 fix: Kick may only ever land on the Tiger, per
			# Game_Balance.md's own Kick description and the SCOPE NOTE this
			# call site has carried since TK-P2-01. Filtered HERE (the call
			# site), not inside KickRules.nearest_target() -- that pure
			# helper stays deliberately role-agnostic (see KickRules.gd's own
			# doc), it just never sees a non-Tiger candidate in the first
			# place.
			if child.role != RoleRules.TIGER:
				continue
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
	# TK-P2-17 (Kick Stagger, gameplay-engineer): confirmed this stays a
	# record-only log, same as before -- there is no server-side stagger
	# STATE worth keeping here (no legality/cooldown decision the stagger
	# itself makes; it is a pure movement consequence applied on the
	# target's own client in on_confirmed() below, see that method's own
	# doc). If a future card ever needs the HOST to know a stagger is in
	# effect (e.g. to gate TagAbility activation host-side while a Tiger is
	# visibly staggered -- considered and deliberately NOT added by this
	# card, see this file's class doc SCOPE NOTE), that bookkeeping would
	# start here.


## Runs on EVERY peer once the host has broadcast rpc_confirm (design doc §3:
## the one place "the ability actually happened" for remote observers) -- but
## it runs in the context of the KICKER's own KickAbility node (Kick is a
## HumanAbility living on the ACTING OUTER's own AbilityController/Player
## subtree, replicated identically to every peer, per this file's class doc).
## `_body` above is therefore ALWAYS the kicker's own Player node here, NEVER
## the target's.
##
## TK-BUG-P2-01 ROOT CAUSE (gameplay-engineer, bug fix -- filed from
## TK-P2-17's human 2-instance test): the pre-fix version of this method
## gated directly on `_body.role`/`_body.name`, i.e. it asked "is the KICKER
## a Tiger" and "is the KICKER's own name the target_id" -- both permanently
## false for the node this code actually runs on (the kicker is by
## definition never the Tiger it just kicked, and never equal to its own
## target_id). `MovementComponent.start_stagger()` was therefore structurally
## unreachable through this path, at any N -- 12 live kicks landed on the
## Tiger, zero stagger. See tests/test_kick_rules.gd's
## "on_confirmed() Kick Stagger targeting" section for the regression test
## this fix adds (fails red against the pre-fix identity-check, green against
## the resolve-the-target fix below).
##
## THE FIX: explicitly RESOLVE the confirmed TARGET's own Player node off the
## shared "Players" root (every Player node is spawned/replicated to every
## peer, design doc §2/§7) via `players_root.get_node_or_null(str(target_id))`
## -- the exact same "resolve a peer id to a live Player node" lookup
## convention managers/GameManager.gd's own apply_role_switch()/
## _apply_tiger_position_correction() already establish, reused here rather
## than inventing a new one. Then gate on `target_node.is_multiplayer_
## authority()` -- "do I (this local peer) own the targeted player" -- the
## same guard/reasoning _apply_tiger_position_correction() already uses for
## the identical "resolved node, act only if I own it" shape, in place of the
## old permanently-false identity check. Only the TARGET's own owning peer
## ever proceeds past this gate; every OTHER peer (the kicker's own included)
## still runs this method (rpc_confirm broadcasts to everyone) but does
## nothing beyond the log above -- it simply sees the staggered Tiger's
## position update the normal way afterward, via the pre-existing
## owner-authoritative position sync (Player.tscn's MultiplayerSynchronizer),
## same "the owning peer applies its own movement, everyone else just sees it
## replicate" model characters/abilities/PounceAbility.gd's on_activate_local()
## and MovementComponent.step_jump() both already establish.
##
## MUST NOT be authoritative -- §4a explicitly calls out that a forger can make
## on_confirmed() run locally on their OWN machine (e.g. by faking the
## ability layer above this method), but that can only ever affect THEIR OWN
## screen: the authoritative effect already happened in host_apply() above,
## which only the real host can ever reach. This method is therefore
## OWNER-SIDE COSMETIC/PREDICTED feedback only and must never mutate
## shared/authoritative game state -- same "cosmetic, a cheating client can
## only ever distort their own screen" caveat every other owner-side effect
## in this codebase documents (Pounce's burst, the Safe Circle owner clamp).
##
## Three gates before applying anything, all now evaluated against the
## RESOLVED `target_node` (never `_body`):
##   1. `target_node != null` -- the target's own node vanished between the
##      kick landing (host_validate() just confirmed it existed) and this
##      confirm arriving, e.g. a disconnect. Edge case, not the common path;
##      nothing to stagger, so this method returns early rather than
##      crashing on a null get_node().
##   2. `target_node.is_multiplayer_authority()` -- "am I the client that
##      owns the targeted player" (see THE FIX above).
##   3. `target_node.role == RoleRules.TIGER` -- Kick Stagger is specifically
##      a Tiger effect (Game_Balance.md §4: "เสือเซ" -- "the Tiger
##      staggers"), not a generic "whoever got kicked" effect. TK-P2-32's
##      host_validate() role filter already guarantees target_id names a
##      Tiger by construction, so this is defense-in-depth, kept for the same
##      "a defensive check costing nothing is still worth having" reason the
##      pre-fix version kept its own (differently-anchored, then-dead)
##      version of this same check.
##
## Knockback direction is computed HERE, client-side, off the RESOLVED
## target_node's own position (not `_body`'s, which is the kicker) -- by
## looking up the kicker's live position the same sideways "Players"
## sibling-scan way host_validate() above does host-side, a COSMETIC/local
## lookup for movement purposes only, not a decision (the kick itself is
## already authoritatively decided by the time this runs). A cheating
## target's client is free to ignore/distort this locally, same "cosmetic,
## not authoritative" caveat as everywhere else in this file (see this
## method's own doc above) -- not over-engineered against here, per the
## TK-P2-28 architect ruling (Change Log [0.45]) this codebase already
## accepts that limitation class for Phase 2. If the kicker's node can't be
## found (e.g. it disconnected between the kick landing and this confirm
## arriving -- an edge case, not the common path), falls back to
## Vector3.ZERO direction via StaggerRules.direction_away_from()'s own
## degenerate-input guard: the stagger's TIME WINDOW still starts (so
## is_staggered() still reports true for animation purposes), it just
## carries no directional push that tick.
func on_confirmed(result) -> void:
	GameLog.info("[KICK] confirmed: kicker=%s target=%s" % [result.get("kicker_id"), result.get("target_id")])

	var players_root: Node = _body.get_parent()
	var target_node: CharacterBody3D = players_root.get_node_or_null(str(result.get("target_id"))) as CharacterBody3D
	if target_node == null:
		return # target disconnected between the kick landing and this confirm -- nothing to stagger, see doc above
	if not target_node.is_multiplayer_authority():
		return # this local peer does not own the targeted player -- nothing to do here
	if target_node.role != RoleRules.TIGER:
		return # Kick Stagger is a Tiger-specific effect -- see this method's own doc above

	var kicker_position: Vector3 = target_node.global_position # degenerate fallback if the kicker can't be found, see doc above
	var kicker_node: Node = players_root.get_node_or_null(str(result.get("kicker_id")))
	if kicker_node is Node3D:
		kicker_position = (kicker_node as Node3D).global_position

	var target_movement: Node = target_node.get_node("MovementComponent")
	var direction: Vector3 = StaggerRules.direction_away_from(kicker_position, target_node.global_position)
	target_movement.start_stagger(direction, stagger_knockback_speed_mps, stagger_duration_sec)
	GameLog.debug("[KICK] stagger applied locally (I am target=%s)" % target_node.name)


## Owner-only (design doc §3: "owner cancels windup"). The host rejected this
## activation (out of range / on cooldown host-side / unknown ability) --
## cancel whatever on_activate_local() started. Also rolls back the OWNER's
## predicted cooldown clock: the kick never actually happened, so penalizing
## the owner with a cooldown for it would be an unearned punishment (game
## feel, gameplay-engineer's call -- not a rule/balance change).
func on_rejected(reason: String) -> void:
	_owner_last_fire_ms = -1
	GameLog.debug("[KICK] rejected: %s -- windup cancelled" % reason)

