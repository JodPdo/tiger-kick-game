class_name SafeCircleRules
## Pure, node-independent decision logic for the Safe Circle boundary
## (TK-P2-06, gameplay-engineer) -- same "pure static helper, thin caller"
## split every other decision-logic file in this codebase follows (see
## characters/RoleRules.gd, characters/components/JumpRules.gd,
## characters/components/CameraModeRules.gd, managers/TagSequenceRules.gd).
##
## DESIGN RULING (human/producer, 2026-07-15, Change Log [0.42], recorded
## verbatim on this card's own `design_ruling` field in _backlog.json):
## (1) Tiger is CONFINED inside the circle -- an invisible wall at radius
## 5.0m (locked, Tiger_Kick_Project_Docs/01_Design/Game_Balance.md §4 "Safe
## Circle radius") blocks the Tiger from exiting; (2) Outer/human players
## move freely in AND out (must be able to walk in to Kick and flee back
## out -- this file/its callers must NEVER gate an Outer); (3)
## host-authoritative -- see characters/components/MovementComponent.gd's
## own doc (owner-side local prediction, role-gated) and managers/
## GameManager.gd's own doc (host-side correction) for how the two
## authority-side callers each use this file.
##
## WHY A RADIAL CLAMP, NOT A COLLISION SHAPE (engineering judgment call made
## explicitly here per the card's own "if ambiguous, escalate" note -- this
## specific question was judged NOT ambiguous enough to escalate, recorded
## here instead): a solid CollisionShape3D/CSG "wall" ring big enough to
## block exit from outside would necessarily also occupy the inside (a disc
## collider fills its whole interior; approximating a hollow ring with many
## segment colliders is exactly the kind of fragile, hard-to-author geometry
## this codebase's Rules-helper convention exists to avoid -- see
## RoleRules.gd/JumpRules.gd's own class docs for the same "pure math over
## scene geometry" precedent already established here). A radial clamp is
## exact for any radius, trivially unit-testable with no scene tree, and
## works identically regardless of the player's own collision shape -- so
## this file does the boundary math directly on the position instead of
## adding scene geometry. world/TestArena.tscn's SafeCircleMarker (CSGTorus3D)
## stays a VISUAL-ONLY ring (no `use_collision`, unlike Floor's CSGBox3D) --
## this file is the actual boundary logic.
##
## CENTER: the arena's Safe Circle is authored at the world origin
## (world/TestArena.tscn's SafeCircleMarker sits at Vector3(0, 0.01, 0)) --
## every function below defaults `center` to Vector3.ZERO to match, but
## takes it as a parameter (not hardcoded) so this stays reusable if a
## future arena ever centers its circle elsewhere.
##
## Only the HORIZONTAL (X/Z) distance from `center` is ever compared against
## `radius` -- Y (height) never enters the boundary check, matching the
## "invisible wall" (not "dome"/"pit") framing of the design ruling: a Tiger
## jumping does not escape any sooner, the wall behaves as if it extends to
## infinite height in both directions.


## Horizontal (X/Z-plane) distance from `position` to `center`, ignoring Y.
static func horizontal_distance(position: Vector3, center: Vector3 = Vector3.ZERO) -> float:
	return Vector2(position.x - center.x, position.z - center.z).length()


## True iff `position` is inside or exactly ON the boundary (<=, not <) -- a
## position exactly at the wall still counts as "inside", matching
## clamp_to_circle() below being a no-op at exactly `radius`, so the two
## never disagree right at the boundary itself.
static func is_inside(position: Vector3, radius: float, center: Vector3 = Vector3.ZERO) -> bool:
	return horizontal_distance(position, center) <= radius


## Returns `position` unchanged if already inside (or exactly on) the
## circle; otherwise projects it radially back onto the boundary (same
## direction from `center`, distance == `radius`), preserving Y untouched.
## This is the "hard clamp with sliding" wall behavior (engineering judgment
## call, see class doc above): walking straight at the wall stops dead at
## the boundary; walking at an angle keeps the tangential component and
## slides along the wall -- the same felt result as CharacterBody3D
## colliding with real static geometry, without needing any.
##
## Degenerate guard: if `radius` <= 0.0 (a misconfigured tunable) or
## `position` sits (numerically) exactly on `center` while outside a
## (invalid) non-positive radius, there is no well-defined direction to
## project along -- returns `center` itself (Y preserved) rather than
## dividing by zero.
static func clamp_to_circle(position: Vector3, radius: float, center: Vector3 = Vector3.ZERO) -> Vector3:
	var offset: Vector2 = Vector2(position.x - center.x, position.z - center.z)
	var distance: float = offset.length()

	if distance <= radius:
		return position

	if distance <= 0.0001 or radius <= 0.0:
		return Vector3(center.x, position.y, center.z)

	var clamped_offset: Vector2 = offset * (radius / distance)
	return Vector3(center.x + clamped_offset.x, position.y, center.z + clamped_offset.y)
