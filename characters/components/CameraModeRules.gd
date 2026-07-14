class_name CameraModeRules
## Pure, node-independent decision logic for TK-P2-05's FP/TP camera swap
## (characters/components/CameraComponent.gd, gameplay-engineer) -- same
## "pure static helper, thin caller" split every other decision-logic file in
## this codebase follows (see characters/RoleRules.gd, managers/
## TagSequenceRules.gd, characters/abilities/KickRules.gd,
## characters/components/JumpRules.gd).
##
## Ability_System_Design.md §5 step 3: "CameraComponent set FP/TP (จริงเฉพาะ
## เครื่องเจ้าของ)" -- Tiger = first-person, everyone else (Outer) =
## third-person. That "only real on the owner's machine" qualifier is NOT
## decided here (this file is a pure role -> mode decision with no concept of
## authority at all) -- it lives on the CALLER (CameraComponent gates the
## whole apply step on `_body.is_multiplayer_authority()`, the same pattern
## MovementComponent/CameraComponent's own mouse-look already use elsewhere in
## this codebase), because only the owning peer's own Camera3D is ever
## `current` (PlayerSpawner._activate_local_camera_if_own) -- a non-owning
## peer's copy of ANY other Player's rig is never the active camera on that
## peer's screen, so mutating it would be a silent no-op at best and (for the
## mesh-visibility half of the swap, see CameraComponent.gd) actively WRONG if
## ever left unguarded: it would hide that Player's own model from every
## OTHER peer's view too, not just switch its owner's own first-person view.
##
## SCOPE: exactly the two roles RoleRules.gd recognizes (Outer, Tiger). Any
## other/unrecognized value fails safe to third-person -- mirrors
## MovementComponent.set_role()'s own "unrecognized -> Outer profile"
## fail-safe default (an unrecognized role should never accidentally grant
## the more disorienting first-person mode).

const TIGER_ROLE: StringName = &"tiger"


## True iff `role` should render first-person. Only &"tiger" does; every
## other value (including a RoleRules-invalid one, which should never reach
## here in practice since Player.set_role() rejects those upstream before
## `role_changed` ever fires) renders third-person.
static func is_first_person(role: StringName) -> bool:
	return role == TIGER_ROLE
