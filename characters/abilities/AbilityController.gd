extends Node
## AbilityController (TK-P2-16 Step 3 of 3, gameplay-engineer) -- per-Player
## registry + the ENTIRE network surface for the Ability System. See
## Tiger_Kick_Project_Docs/02_Technical/Ability_System_Design.md sections
## 2/3/4/5, the APPROVED source of truth this file implements (architect +
## human, 2026-07-05, Change Log [0.33]).
##
## Part of the Player component tree (design doc section 2):
##   Player -> MovementComponent - CameraComponent - AbilityController -> [abilities]
## THIS STEP (3 of 3 -- design doc section 7 says TK-P2-16 is complete at the
## end of Step 3) adds this controller structurally complete but
## functionally EMPTY: AbilityCatalog.abilities_for_role() currently returns
## an empty array for every role, so set_role() below frees/rebuilds zero
## ability children every time it runs -- wired, but inert until Step 4
## (TK-P2-01 Kick) registers the first real ability. The 3 RPCs exist with
## correct signatures/guards per section 4 but have nothing to dispatch to
## yet.
##
## Ownership (design doc section 8): AbilityController owns ALL ability
## network surface -- the 3 @rpc methods below are the ONLY ones anywhere
## in the ability system. Concrete Ability subclasses must never declare
## their own (design doc section 3) -- they only implement the virtual
## methods on Ability, and this controller is what calls them at the right
## time/place.
##
## Coupling to the parent Player (same documented pattern as
## MovementComponent/CameraComponent -- see their class docs): this
## component is a child of Player (a CharacterBody3D) in Player.tscn, and
## reaches up via get_parent() (cached, typed) for authority checks. The
## Player body remains the single source of truth for its own authority
## (Player._enter_tree(), TK-BUG-P1-01 -- untouched by this card).

@onready var _body: CharacterBody3D = get_parent() as CharacterBody3D


## AbilityController authority = server (fix for the TK-P2-16 Step 3 blocker,
## network-engineer 2026-07-05, design doc section 4 amended). WHY: Player's
## own _enter_tree() (characters/Player.gd, TK-BUG-P1-01) calls
## set_multiplayer_authority(int(name), recursive=true), which recursively
## assigns the OWNING PEER's id as authority to this whole subtree -- including
## this controller. That makes @rpc("authority") here mean "the owning client",
## which (1) drops the HOST's rpc_confirm/rpc_reject for a client-owned Player
## and (2) lets a client forge rpc_confirm to bypass host_validate -- an S1
## server-authority inversion.
##
## Fix: override THIS controller's authority back to the server (peer 1). This
## runs AFTER Player._enter_tree()'s recursive set (parent-before-child node
## enter order, empirically confirmed) and only re-targets this controller's
## own subtree -- the Player root / MultiplayerSynchronizer / MovementComponent
## / CameraComponent all KEEP owner authority (the TK-BUG-P1-01 invariant is
## untouched; Player.gd is not modified). Runtime ability children added later
## default to this node's authority (1), so the whole ability network surface
## is consistently host-authoritative. Net effect: @rpc("authority") on this
## node now means "host only" -- the engine drops a forged client rpc_confirm
## BEFORE user code runs (fail-closed).
func _enter_tree() -> void:
	set_multiplayer_authority(1)

## Currently-active ability child nodes, keyed by ability_id, rebuilt every
## time set_role() runs. Empty for now (AbilityCatalog returns an empty
## array for every role this step) -- kept as a Dictionary (rather than
## only relying on scene children) so try_activate()/the RPC handlers can
## look an ability up by id in O(1) once abilities exist.
var _abilities: Dictionary = {}


## Idempotent (design doc section 5 step 3: PlayerRoot.set_role() is
## idempotent). Frees every current ability child node and instantiates
## AbilityCatalog set for role from scratch -- safe to call repeatedly with
## the SAME role (e.g. a stray duplicate role-switch broadcast) since it
## always fully rebuilds rather than diffing, so a stale ability from a
## previous role can never linger.
##
## Called by Player.set_role() (PlayerRoot) -- see characters/Player.gd.
## Nobody calls Player.set_role() for real yet; GameManager is the intended
## caller once the real Role state machine (TK-P2-04) and role-swap RPC
## (design doc section 5 step 1: GameManager Tag Sequence transform ->
## apply_role_switch.rpc(old, new)) exist.
func set_role(role: StringName) -> void:
	for id in _abilities.keys():
		var node: Node = _abilities[id]
		if is_instance_valid(node):
			node.queue_free()
	_abilities.clear()

	for entry in AbilityCatalog.abilities_for_role(role):
		var ability: Ability = _instantiate_ability(entry)
		if ability == null:
			continue
		add_child(ability)
		_abilities[ability.ability_id] = ability


## AbilityCatalog entries may be a PackedScene (ability packaged as its own
## .tscn, e.g. one that needs child nodes like a KickHitbox Area3D -- design
## doc section 2 "adding an ability = 1 file") or a plain Script (a
## pure-logic ability with no scene needs) -- accept either so the catalog
## stays free to register abilities either way without this controller
## caring.
func _instantiate_ability(entry) -> Ability:
	if entry is PackedScene:
		return entry.instantiate() as Ability
	if entry is Script:
		return entry.new() as Ability
	GameLog.error(
		"[AbilityController] unrecognized AbilityCatalog entry type (expected PackedScene or Script): %s"
		% str(entry)
	)
	return null


## Owner-side entry point (design doc section 4, the Kick walkthrough):
## looks the ability up by id, runs its owner-side precheck + cosmetic
## feedback, then routes by its declared Resolution -- LOCAL_ONLY abilities
## apply immediately on the owner with no RPC round-trip at all (e.g.
## Crouch just writes replicated pose state, design doc section 4 channel
## A); HOST_AUTHORITATIVE abilities send an activation request to the host
## via rpc_request_activate and wait for rpc_confirm/rpc_reject.
##
## With no abilities registered yet (this step), _abilities is always
## empty, so every call is an inert early-return -- but the path below is
## exactly what Step 4 (Kick) will exercise for real, so it is written and
## reviewable now rather than invented later.
func try_activate(ability_id: StringName, payload: Dictionary = {}) -> void:
	if not _body.is_multiplayer_authority():
		return # only the owning peer may request its own Player ability to activate

	var ability: Ability = _abilities.get(ability_id)
	if ability == null:
		GameLog.debug(
			"[AbilityController] try_activate: no ability registered for id %s under the current role"
			% ability_id
		)
		return

	var ctx: Dictionary = {"ability_id": ability_id, "payload": payload}
	if not ability.can_activate(ctx):
		return

	ability.on_activate_local(ctx)

	if ability.resolution == Ability.Resolution.LOCAL_ONLY:
		# design doc section 4: LOCAL_ONLY (Crouch) never fires an RPC -- it
		# just sets replicated pose state (stance/lean) on the root, and the
		# synchronizer carries it. AbilityController never round-trips a
		# LOCAL_ONLY ability -- on_activate_local() above is the whole story.
		return

	# HOST_AUTHORITATIVE routing. A host-owned Player (or offline/solo, where
	# is_server() is true and get_unique_id() == 1) processes its own request
	# IN-PROCESS -- never rpc_id(1) to itself, which the engine errors on
	# ("Attempt to call ... on yourself"). The owner gate at the top of this
	# method already guarantees sender == authority, so the host-local path is
	# reached only for a Player this peer legitimately owns. A remote-owned
	# client sends the request to the host over the wire as before.
	if multiplayer.is_server():
		_host_process_request(multiplayer.get_unique_id(), ability_id, payload)
	else:
		rpc_request_activate.rpc_id(1, ability_id, payload)


## HOST-ONLY (design doc section 4, channel B). any_peer because every
## non-host owner needs to be able to call this on the host; reliable
## because a dropped activation request must never silently vanish -- the
## owner would otherwise wait forever for a confirm/reject that never
## comes.
##
## Sender/authority guard (per the card spec, design doc section 4): only
## the peer that owns THIS Player (this AbilityController parent) may
## request an activation for it -- otherwise one peer could forge
## activations on behalf of another peer own Player. Checked with
## get_multiplayer_authority() (not is_multiplayer_authority()), since this
## guard runs on the HOST, which is generally not the authority of a
## client-owned Player.
@rpc("any_peer", "reliable")
func rpc_request_activate(ability_id: StringName, payload: Dictionary) -> void:
	if not multiplayer.is_server():
		return # only the host validates/decides ability results (design doc section 4)

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != _body.get_multiplayer_authority():
		GameLog.error(
			"[AbilityController] rpc_request_activate: sender %d does not match authority %d for Player %s -- rejecting (possible forged activation)"
			% [sender_id, _body.get_multiplayer_authority(), _body.name]
		)
		return

	_host_process_request(sender_id, ability_id, payload)


## HOST-ONLY validate -> apply -> notify body, extracted from
## rpc_request_activate so the host can drive it IN-PROCESS for a Player it
## owns (try_activate host-local path) without doing rpc_id(1) to itself. Two
## callers: (a) rpc_request_activate, for a remote client-owned Player
## (sender_id = the requesting peer, resolved from get_remote_sender_id());
## (b) try_activate, for a host-owned / offline Player (sender_id =
## get_unique_id()). Both callers have already established that sender_id is
## the legitimate owner of this Player, so no authority check is repeated here.
func _host_process_request(sender_id: int, ability_id: StringName, payload: Dictionary) -> void:
	var ability: Ability = _abilities.get(ability_id)
	if ability == null:
		GameLog.error("[AbilityController] _host_process_request: unknown ability id %s" % ability_id)
		_reject_owner(sender_id, null, ability_id, "unknown_ability")
		return

	var ctx: Dictionary = {"ability_id": ability_id, "payload": payload, "sender_id": sender_id}
	var verdict: Dictionary = ability.host_validate(ctx)
	if verdict.get("ok", false):
		ability.host_apply(verdict.get("result"))
		# rpc_confirm carries call_local, so the host's own copy also runs
		# on_confirmed() -- covers both the client-owned case (host + all peers)
		# and the host-owned/offline case (host only). No change needed here.
		rpc_confirm.rpc(ability_id, verdict.get("result"))
	else:
		_reject_owner(sender_id, ability, ability_id, verdict.get("reason", "rejected"))


## Deliver a rejection to the requesting owner. rpc_reject is a host->owner
## targeted RPC, but Godot errors if you rpc_id() a message to your own peer
## id -- so when the requester IS the host itself (host-owned Player, or
## offline/solo where get_unique_id() == 1), we invoke the ability's
## on_rejected() locally instead. A remote owner still gets the RPC as before.
## `ability` may be null for the unknown-ability path; a host-local requester
## with no matching ability has nothing to undo (try_activate already looked
## the ability up and early-returned if it was missing, so this null-with-host
## case is only reachable via a role-swap race, where a no-op is correct).
func _reject_owner(sender_id: int, ability: Ability, ability_id: StringName, reason: String) -> void:
	if sender_id == multiplayer.get_unique_id():
		if ability != null:
			ability.on_rejected(reason)
	else:
		rpc_reject.rpc_id(sender_id, ability_id, reason)


## Host -> everyone, call_local included so the host own copy also runs
## on_confirmed() (design doc section 4: apply via host_apply then
## rpc_confirm(call_local) so every peer on_confirmed runs, host included).
## This is the ONLY place a result is applied for remote observers --
## animation/VFX/SFX react in on_confirmed(), never in on_activate_local()
## (owner-only prediction).
@rpc("authority", "call_local", "reliable")
func rpc_confirm(ability_id: StringName, result) -> void:
	var ability: Ability = _abilities.get(ability_id)
	if ability == null:
		return # ability no longer exists locally (e.g. a role-swap raced this confirm)
	ability.on_confirmed(result)


## Host -> the requesting owner only (no call_local -- the host itself
## never requested this, so it has nothing to undo). Lets the owner cancel
## whatever on_activate_local() started (e.g. a windup animation).
@rpc("authority", "reliable")
func rpc_reject(ability_id: StringName, reason: String) -> void:
	var ability: Ability = _abilities.get(ability_id)
	if ability == null:
		return
	ability.on_rejected(reason)

