class_name RoleVisualRules
## Pure, node-independent decision logic for TK-P3-13's TEMPORARY role-visual
## cue (characters/components/RoleVisualComponent.gd, gameplay-engineer) --
## same "pure static helper, thin caller" split every other decision-logic
## file in this codebase follows (see characters/RoleRules.gd,
## characters/components/CameraModeRules.gd, characters/components/
## JumpRules.gd).
##
## HARD BOUNDARY (see RoleVisualComponent.gd's own class doc for the full
## card context/rationale): this is throwaway, temporary playtest scaffolding
## filed by producer/design (TK-P3-13) so the first real-people playtest
## (TK-P3-03) has SOME visual distinction between Tiger and Outer, since real
## character art is Phase 4 scope and Character_Art_Bible.md section 5
## (Tiger Indicator) is itself still fully unlocked/undecided. Do NOT expand
## this into a permanent "visual indicator system", do NOT read
## Character_Art_Bible.md section 5 into this, and do NOT treat these values
## as anything but disposable -- Phase 4 real art wholesale replaces this.
##
## VALUES: Tiger = orange, scale 2.0 -- reuses the Art Bible's already-LOCKED
## real-world height ratio (Tiger 2.0m vs Player 1.2-1.4m) applied to the
## still-placeholder capsule mesh. Outer = white (matches the scene's
## pre-existing default look, i.e. this card changes NOTHING visually for
## Outer), scale 1.0 (no change).
##
## SCOPE: exactly the two roles RoleRules.gd recognizes (Outer, Tiger). Any
## other/unrecognized value fails safe to the Outer look -- same "unrecognized
## -> Outer profile" fail-safe convention MovementComponent.set_role()/
## CameraModeRules.is_first_person() already use elsewhere in this codebase.

const TIGER_ROLE: StringName = &"tiger"

const TIGER_COLOR: Color = Color(1.0, 0.549, 0.0) # orange
const OUTER_COLOR: Color = Color(1.0, 1.0, 1.0) # white -- the scene's pre-existing default look

const TIGER_SCALE: float = 2.0
const OUTER_SCALE: float = 1.0


## The capsule albedo color for `role`. Only &"tiger" gets orange; every other
## value (including a RoleRules-invalid one, which should never reach here in
## practice since Player.set_role() rejects those upstream before
## `role_changed` ever fires) fails safe to the Outer/white look.
static func color_for_role(role: StringName) -> Color:
	return TIGER_COLOR if role == TIGER_ROLE else OUTER_COLOR


## The uniform capsule scale factor for `role`. Same fail-safe default as
## color_for_role() above.
static func scale_for_role(role: StringName) -> float:
	return TIGER_SCALE if role == TIGER_ROLE else OUTER_SCALE
