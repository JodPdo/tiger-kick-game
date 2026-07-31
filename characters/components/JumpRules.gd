class_name JumpRules
## Pure, node-independent decision logic for Jump (TK-P2-10, gameplay-engineer).
##
## ARCHITECTURE NOTE (resolved, not re-litigate per card): the Ability System
## design doc explicitly rules Jump is NOT an ability -- see
## Tiger_Kick_Project_Docs/02_Technical/Ability_System_Design.md §3 ("Sprint,
## Jump -- ไม่ใช่ ability -- MovementComponent (movement primitive)") and §2's
## MovementComponent responsibility row ("...Jump (TK-P2-10)..."), confirmed
## again in Tiger_Kick_Project_Docs/04_Management/03_Change_Log.md [0.34]
## ("Jump=primitive"; originally decided in [0.33]). CURRENT_PHASE.md's
## looser "Jump re-slot as abilities" line predates that detail and is now
## stale phrasing describing the same Phase-2 sprint, not a competing
## decision -- the design doc is the dated, specific, already-approved
## source of truth (per CLAUDE.md/DOCUMENT_ROUTING precedence) and is what
## this card follows: Jump lives on
## characters/components/MovementComponent.gd, NOT as a new
## characters/abilities/*Ability.gd. Jump is host-controlled only in the
## sense that it is authority-side (owner) physics + MultiplayerSynchronizer
## sync, same as Sprint/gravity already are -- it does NOT go through
## AbilityController's 3-RPC HOST_AUTHORITATIVE confirm surface (design doc
## §4), because it decides nothing about who wins/loses (the §3 resolution
## criterion: "โกงแล้วชนะเกมได้ = HOST; โกงแล้วแค่ภาพ/เสียงเพี้ยน = LOCAL_ONLY"
## -- a client mispredicting/faking its own jump only ever desyncs its own
## position, which the owner-authoritative MultiplayerSynchronizer channel
## already tolerates the same way it tolerates any other owner-authored
## movement).
##
## WHY THIS EXISTS (testability, same pattern as KickRules.gd/TigerSelector.gd
## per design doc §3): the actual "am I allowed to jump right now" / "what
## vertical velocity does a jump impulse produce" decisions have no scene-tree
## or Input dependency, so they live here as plain static functions GUT can
## call directly -- no CharacterBody3D, no live physics tick.

## True when a jump input may actually launch the body this tick.
## `is_on_floor` is the CharacterBody3D's own floor contact this frame
## (MovementComponent's `_body.is_on_floor()`, read once per tick before
## move_and_slide() runs again -- see MovementComponent.gd's own doc for why
## that ordering matters). `is_jumping` is MovementComponent's own tracked
## flag (`_is_jumping`, see MovementComponent.gd), cleared once a REAL
## landing is detected (grounded AND no longer moving upward -- see
## MovementComponent.step_jump()'s own doc for why velocity direction
## matters there) and set the instant a jump fires -- kept as a SEPARATE
## signal from `is_on_floor` (rather than relying on `is_on_floor` alone) as
## defense in depth against Godot's own is_on_floor() lagging by a frame
## while still rising (a known CharacterBody3D quirk, e.g. on slopes/moving
## floors), which is exactly the "double-jump mid-air" bug this card's DoD
## calls out. Both must agree the body is grounded and not already mid-jump
## for a jump to be allowed -- this is the ONLY gate; there is no
## coyote-time/jump-buffer grace window in this card (out of scope, a Phase
## 3 feel tune if ever wanted).
static func can_jump(is_on_floor: bool, is_jumping: bool) -> bool:
	return is_on_floor and not is_jumping


## The vertical velocity (m/s, +Y = up) a jump impulse sets, given the
## design-owned `jump_speed` tunable (MovementComponent.@export). Trivial
## today (no charge-jump/height-variance mechanic exists), but kept as its
## own pure function -- same shape as KickRules.can_fire()/nearest_target()
## -- so MovementComponent never hard-codes the impulse formula inline and a
## future tune (e.g. variable jump height held-vs-tapped) has one place to
## change without touching step_jump()'s wiring.
static func jump_velocity(jump_speed: float) -> float:
	return jump_speed
