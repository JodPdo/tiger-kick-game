class_name Ability
extends Node
## Ability -- base class for every ability in the Ability System (TK-P2-16
## Step 3 of 3, gameplay-engineer). See
## Tiger_Kick_Project_Docs/02_Technical/Ability_System_Design.md §3, the
## APPROVED source of truth this file implements verbatim (architect +
## human, 2026-07-05, Change Log [0.33]).
##
## SCAFFOLD ONLY -- this card adds no concrete ability logic (Kick is
## TK-P2-01 / design doc §7 Step 4, the very next card). Every virtual
## method below is a safe, conservative default so a bare `Ability` node
## can exist without crashing and so concrete subclasses only need to
## override what they actually use.
##
## Ability subclasses MUST NOT declare their own `@rpc` methods -- the
## entire network surface for the ability system lives on
## characters/abilities/AbilityController.gd (design doc §3/§8). A subclass
## only ever implements the virtual methods below; how a result travels
## owner -> host -> everyone is AbilityController's job alone.
##
## `ctx`/`result`/`reason` below are intentionally untyped (Dictionary/
## Variant) -- their shape is decided by each concrete ability, which this
## base class knows nothing about (kept as loose contracts, same spirit as
## TigerSelector/SpawnPointUtil's plain-value pure helpers elsewhere in the
## codebase).

## HOST_AUTHORITATIVE: the ability decides something the game itself cares
## about (a kick landing, a tag) -- must be host-validated, because a client
## deciding this for itself would let cheating win the game (design doc §3
## resolution criterion: "โกงแล้วชนะเกมได้ = HOST").
## LOCAL_ONLY: purely cosmetic/pose (crouch, lean, peek, emote) -- no RPC
## round-trip; the owner just writes replicated pose state directly
## (design doc §4 channel A) and cheating it only ever looks wrong, never
## wins anything ("โกงแล้วแค่ภาพ/เสียงเพี้ยน = LOCAL_ONLY").
enum Resolution { HOST_AUTHORITATIVE, LOCAL_ONLY }

## Stable id this ability is looked up/activated by (e.g. &"kick") --
## AbilityController keys its registry and both `rpc_request_activate`/
## `rpc_confirm`/`rpc_reject` payloads by this. Design-owned per concrete
## ability; left blank in the base class.
@export var ability_id: StringName = &""

## InputMap action this ability listens for (e.g. &"kick"). AbilityController
## reads this to route player input -> try_activate(). Left blank here.
@export var input_action: StringName = &""

## Minimum seconds between activations. 0.0 = no cooldown. Design-owned per
## ability; a later card (TK-P3-01) may upgrade this to a shared `.tres`
## resource without changing this contract.
@export var cooldown_sec: float = 0.0

## See the Resolution doc-comment above. HOST_AUTHORITATIVE is the safe
## default: a concrete ability that forgets to declare `resolution` fails
## SAFE by still routing through host validation, rather than accidentally
## granting itself client-authoritative (cheatable) behavior.
var resolution: Resolution = Resolution.HOST_AUTHORITATIVE


## Owner-side precheck (cooldown/grounded/match-state/etc, per subclass).
## Base default: nothing to block yet, so scaffold behavior is "allowed" --
## a concrete ability overrides this to gate on its own real precondition.
func can_activate(_ctx) -> bool:
	return true


## Owner-side immediate/cosmetic feedback (e.g. windup animation, camera
## shake) -- fires the instant the local player presses input, before any
## host round-trip. Must NEVER mutate authoritative game state (design doc
## §4: "on_activate_local(windup)" is prediction/feel only). No-op default.
func on_activate_local(_ctx) -> void:
	pass


## HOST-ONLY: authoritative validation of a requested activation (range,
## cooldown ledger, match state, etc, per subclass). Must return a
## Dictionary shaped {ok: bool, reason: String, result: Variant} (design doc
## §3). Base default REJECTS everything -- fail-closed: a bare/unconfigured
## Ability has no business being approved by the host.
func host_validate(_ctx) -> Dictionary:
	return {"ok": false, "reason": "not_implemented", "result": null}


## HOST-ONLY: apply the authoritative result of a validated activation to
## real game state (or notify GameManager). No-op default -- a bare Ability
## has no state of its own to mutate.
func host_apply(_result) -> void:
	pass


## Runs on EVERY peer once the host has broadcast a confirmed result (see
## AbilityController.rpc_confirm) -- the one place "the ability actually
## happened" for remote observers (animation/VFX/SFX react here, never in
## on_activate_local, which is owner-only prediction). No-op default.
func on_confirmed(_result) -> void:
	pass


## Owner-only: the host rejected this activation (see
## AbilityController.rpc_reject) -- undo/cancel whatever on_activate_local()
## started (e.g. cancel a windup animation). No-op default.
func on_rejected(_reason) -> void:
	pass
