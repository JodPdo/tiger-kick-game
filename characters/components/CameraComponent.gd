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
## STEP 2 (TK-P2-16) extracted ONLY the camera/mouse-look code and was
## THIRD-PERSON ONLY at that point (no FP/first-person mode -- that was
## explicitly deferred to this exact card, TK-P2-05, see that step's own
## history below).
##
## TK-P2-05 (gameplay-engineer, THIS pass): adds the FP/TP swap design doc §5
## step 3 calls for -- Tiger = first-person, everyone else (Outer) =
## third-person. Decision logic lives in CameraModeRules.gd (pure static,
## same "pure helper, thin caller" split as RoleRules.gd/JumpRules.gd); this
## file only wires it: `_body.role_changed` SIGNAL SUBSCRIBE (see _ready()
## below) -- chosen over adding a second direct call inside
## Player.set_role() per the TK-P2-04 code-review nit ("decide signal-
## subscribe vs. a direct call, don't do both"); Player.gd is NOT touched by
## this card. `_apply_camera_mode()` is gated on `_body.is_multiplayer_
## authority()` (same authority caveat this file's mouse-look already
## documents) -- see CameraModeRules.gd's own class doc for why: only the
## owning peer's own Camera3D is ever `current` (PlayerSpawner.
## _activate_local_camera_if_own), so applying the swap to a NON-owned copy
## of some other Player's rig would be a silent no-op for the spring-arm
## pull-back, and actively WRONG for the own-mesh-hide half (it would hide
## that Player's model from every OTHER peer's view, not just switch that
## Player's OWN first-person view). No new RPC/network state: `role` itself
## already arrives host-authoritatively via GameManager.apply_role_switch()
## -> Player.set_role() (TK-P2-03/04) -- this card only reacts, client-side,
## to a value that has already been decided.
##
## OUT OF SCOPE (flagged, not decided here): the GDD's "limited view" phrase
## for the Tiger (core-loop paragraph) could mean a narrower FOV/vision-cone,
## which is a separate design/balance decision (e.g. Phase 3 Crouch/Lean/Peek
## body-language ladder) -- NOT assumed or implemented by this card, which is
## scoped strictly to the FP/TP camera-rig swap the card title names. Escalate
## to `designer` if "limited view" needs to become a real mechanic before
## Phase 3.
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

## TK-P2-05: sideways reach to the sibling MeshInstance3D, same
## get_parent().get_node(...) pattern this file already uses for CameraRig/
## SpringArm3D above (and MovementComponent uses for CameraRig) -- needed so
## the OWNING peer can hide their own body mesh while first-person (otherwise
## the camera would be looking out from inside their own capsule). Only ever
## mutated from `_apply_camera_mode()` below, which is itself gated on
## `_body.is_multiplayer_authority()` -- see that method's doc for why a
## non-owning peer's copy of this same node must never touch this.
@onready var _mesh: MeshInstance3D = get_parent().get_node("MeshInstance3D") as MeshInstance3D

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

## -- FP/TP mode tunables (TK-P2-05) ------------------------------------------

## Spring-arm length while first-person (Tiger): 0.0 pulls the Camera3D all
## the way in to CameraRig's own position (already ~head height, see
## Player.tscn's CameraRig transform y=1.5), i.e. no third-person pull-back at
## all. A feel constant (like MOUSE_LOOK_RADIANS_PER_PIXEL above), not a GDD/
## Game_Balance.md-specified value, so a plain @export rather than a design-
## owned tunable.
@export var first_person_spring_length: float = 0.0

## Cached at _ready() from whatever Player.tscn's SpringArm3D.spring_length
## already is (currently 4.0) -- read back rather than hardcoded as a second
## magic number here, so the third-person distance stays the single value
## already authored on the scene (no drift if that scene value is ever
## retuned) and switching back to Outer always restores exactly what TP
## looked like before this card touched anything.
var _third_person_spring_length: float = 0.0


## Mouse capture UX (documented, kept simple per the card, unchanged by this
## move): captured on _ready() for the authority player; Esc releases it
## (e.g. to reach OS/UI); a left-click while released recaptures it. No pause
## menu exists yet -- a future pause/menu card should decide how capture
## interacts with that UI (e.g. suspend capture while a menu is open) rather
## than this script owning that policy.
func _ready() -> void:
	if _body.is_multiplayer_authority():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# TK-P2-05: cache the scene-authored TP distance BEFORE anything can
	# mutate spring_length, then self-apply this Player's CURRENT role once
	# (same "build my own state from PlayerRoot's `role` the instant I exist,
	# without waiting for a broadcast" reasoning MovementComponent._ready()/
	# AbilityController._ready() already use for their own role-driven state --
	# matters for a late-join/reconnect Tiger, design doc §9 open question),
	# then subscribe to `role_changed` for every subsequent swap. SIGNAL
	# SUBSCRIBE chosen over a second direct call added into Player.set_role()
	# per the TK-P2-04 review nit -- see this file's header doc.
	_third_person_spring_length = _spring_arm.spring_length
	_apply_camera_mode(_body.role)
	_body.role_changed.connect(_on_role_changed)


## TK-P2-05: `role_changed` handler -- see this file's header doc for why
## this is a signal subscription rather than a direct call from
## Player.set_role().
func _on_role_changed(new_role: StringName) -> void:
	_apply_camera_mode(new_role)


## TK-P2-05: applies the FP/TP swap for `role` -- gated on `_body.
## is_multiplayer_authority()` (see this file's header + CameraModeRules.gd's
## own doc for why a non-owning peer's copy of this same node must never
## mutate its rig/mesh: only the owning peer's own Camera3D is ever `current`,
## and mutating a non-owned copy's mesh visibility would hide that Player's
## model from every OTHER peer's view too, not just switch its own).
func _apply_camera_mode(role: StringName) -> void:
	if not _body.is_multiplayer_authority():
		return

	var first_person: bool = CameraModeRules.is_first_person(role)
	_spring_arm.spring_length = (
		first_person_spring_length if first_person else _third_person_spring_length
	)
	# Hide the owning peer's own body mesh while first-person -- otherwise
	# the camera (pulled all the way in) would be looking out from inside
	# their own capsule. Cosmetic-only, local to this peer's own render (see
	# `_mesh`'s own doc above); every OTHER peer's separate instantiated copy
	# of this same Player is untouched (this whole method already returned
	# above on their machine, since they are not this Player's authority).
	if _mesh:
		_mesh.visible = not first_person


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
