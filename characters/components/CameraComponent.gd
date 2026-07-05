extends Node
## CameraComponent (TK-P2-16 Step 2 of 3, gameplay-engineer) -- extracted,
## BEHAVIOR-PRESERVING, from characters/Player.gd's camera-rig / mouse-look /
## mouse-capture code.
##
## Part of the architect-approved Ability System scaffold (see
## Tiger_Kick_Project_Docs/02_Technical/Ability_System_Design.md and
## Tiger_Kick_Project_Docs/04_Management/03_Change_Log.md [0.33]): target
## Player tree is
##   Player -> MovementComponent · CameraComponent · AbilityController -> [abilities]
## THIS STEP (2 of 3) extracts ONLY the camera/mouse-look code, still
## THIRD-PERSON ONLY (no FP/first-person mode -- that is TK-P2-05, later
## work; do not add it here). AbilityController (Step 3) does not exist yet.
##
## STEP 2 DISCIPLINE (per card, per the design doc's Step 2 note): this is a
## pure code MOVE. No tunable value changed, no new feature, no behavior
## change. Everything below is copied verbatim from Player.gd (see that
## file's own header for the full TK-P1-03/TK-BUG-P1-02 history of WHY this
## code looks the way it does -- that history still applies unchanged, just
## relocated here).
##
## ============================================================================
## !! CRITICAL !! ESC gate+consume (TK-BUG-P1-02) -- READ BEFORE TOUCHING !!
## ============================================================================
## The ESC branch in _unhandled_input below is GATED on the mouse currently
## being CAPTURED, and CONSUMES the event (get_viewport().set_input_as_handled())
## when it releases capture. This is load-bearing for the TestArena.gd Leave
## path: _unhandled_input propagates from the DEEPEST node UP, so this
## CameraComponent (a child of Player, itself deep in the tree) runs BEFORE
## the scene-root TestArena on the SAME event -- exactly the same ordering
## Player.gd relied on before this code moved here (CameraComponent nests
## one level deeper than Player, which only makes it run EARLIER in the
## deepest-first traversal, never later) -- and Input.mouse_mode readback is
## immediate. Without the gate+consume, a single ESC tap would (1) release
## capture here, then (2) TestArena would see mouse == VISIBLE on that very
## same press and immediately _leave() -- one reflexive ESC ends the whole
## session (fatal on the host). With the gate+consume: while CAPTURED, ESC is
## eaten here (release only, TestArena never sees it); only once the mouse is
## ALREADY visible does ESC fall through un-consumed to TestArena to trigger
## Leave. Net UX: first ESC releases the mouse, a distinct second ESC leaves.
## DO NOT remove or reorder the gate/consume without re-running the windowed
## ESC probe (see tests/ -- offline manual verification only, mouse_mode is a
## headless no-op) and re-reading world/TestArena.gd's own class doc.
## ============================================================================
##
## Coupling to the parent Player (documented per the card; same pattern as
## MovementComponent):
##   - This component is added as a child of Player (a CharacterBody3D) in
##     Player.tscn. It does not own the CameraRig/SpringArm3D/Camera3D nodes
##     -- those stay in place under Player (siblings of this component), and
##     this script reaches up/sideways via `get_parent()` (cached, typed) to
##     drive their rotation. `is_multiplayer_authority()` is likewise checked
##     on the parent body, not on `self` -- only the owning peer's rig should
##     respond to its own mouse input (same authority caveat MovementComponent
##     documents for its own gate).
##   - MovementComponent still reaches CameraRig itself (get_parent().get_node
##     ("CameraRig").rotation.y) for camera-relative movement -- that sideways
##     reach-around is UNCHANGED by this step (see MovementComponent.gd's own
##     doc and this card's decision note: rerouting it through this component
##     was considered and deliberately deferred as lower-risk to leave as-is;
##     CameraRig's rotation.y is the same value either way, read directly from
##     the node both components already have a reference to).

@onready var _body: CharacterBody3D = get_parent() as CharacterBody3D
@onready var _camera_rig: Node3D = get_parent().get_node("CameraRig") as Node3D
@onready var _spring_arm: SpringArm3D = get_parent().get_node("CameraRig/SpringArm3D") as SpringArm3D

## -- Camera rig tunables (TK-P1-03) ------------------------------------------
## Moved verbatim from Player.gd. Values UNCHANGED.

## Fallback mouse sensitivity multiplier, used only if ConfigManager isn't
## available (e.g. a bare/offline test context). Normally overridden per-run
## by ConfigManager.get_value("controls", "mouse_sensitivity", ...) -- see
## Settings > Controls (TK-PX-05), DEFAULTS.controls.mouse_sensitivity = 1.0.
@export var mouse_sensitivity_fallback: float = 1.0

## Radians of rig rotation per pixel of mouse motion at sensitivity == 1.0.
## Not a GDD/TDD-specified balance value (a feel/UX constant, not gameplay
## rules), so a plain constant rather than a design-owned @export.
const MOUSE_LOOK_RADIANS_PER_PIXEL: float = 0.0025

## SpringArm3D pitch clamp (TK-P1-03 card spec): more room to look down
## (toward the ground/character) than up, matching common third-person
## camera feel and avoiding the camera flipping over the top.
const PITCH_MIN: float = -deg_to_rad(60.0) # look down
const PITCH_MAX: float = deg_to_rad(30.0)  # look up


## Mouse capture UX (documented, kept simple per the card, unchanged by this
## move): captured on _ready() for the authority player; Esc releases it
## (e.g. to reach OS/UI); a left-click while released recaptures it. No pause
## menu exists yet -- a future pause/menu card should decide how capture
## interacts with that UI (e.g. suspend capture while a menu is open) rather
## than this script owning that policy.
func _ready() -> void:
	if _body.is_multiplayer_authority():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Mouse-look (TK-P1-03): rotates CameraRig's yaw (Y) and SpringArm3D's
## pitch (X, clamped to PITCH_MIN..PITCH_MAX) from raw mouse motion. Gated on
## the parent body's is_multiplayer_authority() so only the local/owning
## peer's rig responds (same authority caveat MovementComponent documents).
##
## TK-BUG-P1-02 (review fix): see the CRITICAL banner at the top of this file
## for the full ESC gate+consume rationale -- kept load-bearing and unchanged
## by this move.
func _unhandled_input(event: InputEvent) -> void:
	if not _body.is_multiplayer_authority():
		return

	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity: float = mouse_sensitivity_fallback
		if ConfigManager:
			sensitivity = ConfigManager.get_value(
				"controls", "mouse_sensitivity", mouse_sensitivity_fallback
			)
		var motion: Vector2 = event.relative * sensitivity * MOUSE_LOOK_RADIANS_PER_PIXEL
		_camera_rig.rotation.y -= motion.x
		_spring_arm.rotation.x = clamp(_spring_arm.rotation.x - motion.y, PITCH_MIN, PITCH_MAX)
