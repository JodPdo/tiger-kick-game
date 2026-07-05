extends Node
## MovementComponent (TK-P2-16 Step 1 of 3, gameplay-engineer) -- extracted,
## BEHAVIOR-PRESERVING, from characters/Player.gd's movement code.
##
## Part of the architect-approved Ability System scaffold (see
## Tiger_Kick_Project_Docs/04_Management/03_Change_Log.md [0.29] and
## CURRENT_PHASE.md): target Player tree is
##   Player -> MovementComponent · CameraComponent · AbilityController -> [abilities]
## THIS STEP (1 of 3) extracts ONLY movement. CameraComponent (Step 2) and
## AbilityController (Step 3) do NOT exist yet -- do not add camera or
## ability code to this file; that is later work.
##
## STEP 1 DISCIPLINE (per card): this is a pure code MOVE. No tunable value
## changed, no new feature, no behavior change. Everything below is copied
## verbatim from Player.gd (see that file's own header for the full
## TK-P1-02/03/06 history of WHY this code looks the way it does -- that
## history still applies unchanged, just relocated here).
##
## Coupling to the parent Player (documented per the card):
##   - This component is added as a child of Player (a CharacterBody3D) in
##     Player.tscn. It does NOT own a body of its own -- `velocity`,
##     `move_and_slide()`, and `is_on_floor()` all belong to the PARENT body,
##     so this script reaches up via `get_parent()` (cached, typed) to drive
##     them. `is_multiplayer_authority()` is likewise checked on the parent
##     body, not on `self` -- see the _physics_process doc below for why.
##   - CameraRig (yaw source for camera-relative movement) has NOT moved --
##     it stays a sibling under Player. This script reaches SIDEWAYS via
##     `get_parent().get_node("CameraRig")` purely to read its current
##     `rotation.y` each tick. This raw node-path reach-around is a known,
##     deliberate, PERMANENT coupling, not a Step-1-only stopgap: CameraComponent
##     (Step 2) now exists and also reaches CameraRig the same sideways way for
##     its own mouse-look, but rerouting THIS read through CameraComponent (a
##     getter/signal instead of both siblings reaching CameraRig directly) was
##     considered during Step 2 and deliberately deferred as lower-risk to leave
##     as-is -- see CameraComponent.gd's own class doc for that decision. Both
##     components reading the same node's `rotation.y` directly is harmless
##     (read-only, no ordering dependency), so there is no correctness reason to
##     revisit this; it is a possible future cleanup only, not a bug.

@onready var _body: CharacterBody3D = get_parent() as CharacterBody3D
@onready var _camera_rig: Node3D = get_parent().get_node("CameraRig") as Node3D

## -- Tunables (TDD §11 Game Balance; design-owned, NOT hard-coded) ----------
## Moved verbatim from Player.gd. Values UNCHANGED -- per-role balance tuning
## is explicitly OUT of scope for this step (a later card).

## Baseline walking speed, m/s. TDD §11 "Player Speed": 5.0 m/s baseline.
@export var walk_speed: float = 5.0

## Multiplier applied to walk_speed while `sprint` is held.
## TDD §11 "Sprint Multiplier": x1.4.
@export var sprint_multiplier: float = 1.4

## Downward acceleration, m/s^2. Not specified in TDD §11 -- defaulted to
## Godot's engine default (ProjectSettings physics/3d/default_gravity = 9.8).
@export var gravity: float = 9.8


## Movement input (TK-P1-02, made camera-relative by TK-P1-03; relocated here
## unchanged by TK-P2-16 Step 1): reads move_forward/back/left/right + sprint,
## rotates the input direction by CameraRig's current yaw (see
## camera_relative_dir() below) so WASD is relative to where the camera/rig is
## looking, drives the parent body's horizontal velocity, applies gravity so
## the body stays grounded, and calls move_and_slide() on the parent body.
##
## TK-P1-06 (network-engineer) INVARIANT -- preserved EXACTLY: the ENTIRE
## function is gated on the parent Player's is_multiplayer_authority().
## Non-authority Player instances (every remote peer's copy of a Player they
## don't own) return immediately and run NO local physics at all; their
## `position`/`rotation` are instead written directly by
## MultiplayerSynchronizer (Player.tscn's SceneReplicationConfig replicates
## exactly those two properties, TK-P1-01) outside of _physics_process.
## Without this gate, gravity + move_and_slide() running unconditionally on
## every peer's copy fights the synchronizer's incoming writes every physics
## tick -- jitter (see Player.gd's file header for the full original
## incident). Checked on `_body` (the parent Player), not on `self`, so this
## holds regardless of exactly how/when multiplayer authority propagates to
## child nodes -- the Player body is the single source of truth for its own
## authority (see Player._enter_tree()).
func _physics_process(delta: float) -> void:
	if not _body.is_multiplayer_authority():
		return

	var input_dir: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	)
	var sprinting: bool = Input.is_action_pressed("sprint")
	var rig_yaw: float = _camera_rig.rotation.y
	var relative_dir: Vector3 = camera_relative_dir(input_dir, rig_yaw)
	var horizontal: Vector3 = compute_velocity(
		Vector2(relative_dir.x, relative_dir.z), walk_speed, sprint_multiplier, sprinting
	)
	_body.velocity.x = horizontal.x
	_body.velocity.z = horizontal.z

	_body.velocity.y = apply_gravity(_body.velocity.y, gravity, delta, _body.is_on_floor())

	_body.move_and_slide()


## Pure, node-independent helper (GUT-testable without a scene tree/Input):
## given a 2D input vector (x = left(-)/right(+), y = forward(-)/back(+),
## e.g. straight from Input.get_vector) and the walk/sprint tunables, returns
## the intended horizontal velocity as a Vector3 (Y always 0 -- vertical
## motion is gravity's job, see apply_gravity() below). Operates in whatever
## space `input_dir` is already expressed in -- the caller (_physics_process)
## rotates raw input into camera-relative space via camera_relative_dir()
## BEFORE calling this, so the result ends up world-space. Kept unaware of
## rotation/yaw by design so this stays a pure speed/sprint calculation.
static func compute_velocity(
	input_dir: Vector2, walk: float, sprint_mult: float, sprinting: bool
) -> Vector3:
	var speed: float = walk * sprint_mult if sprinting else walk
	return Vector3(input_dir.x, 0.0, input_dir.y) * speed


## Pure, node-independent helper (GUT-testable, TK-P1-03): rotates a 2D
## input direction (x = left(-)/right(+), y = forward(-)/back(+), same
## convention as Input.get_vector/compute_velocity above) around the world
## Y axis by `yaw` radians, returning a Vector3 (Y always 0) in the
## resulting camera/rig-relative space. `yaw` is expected to be the
## CameraRig's rotation.y (radians) -- since the Player body itself is never
## rotated by camera-look (see Player.gd's HISTORICAL ASSUMPTION note),
## CameraRig's local yaw already equals its effective world yaw. Magnitude of
## `input` is preserved (not normalized), matching compute_velocity's
## existing diagonal-input behavior.
static func camera_relative_dir(input: Vector2, yaw: float) -> Vector3:
	var local_dir: Vector3 = Vector3(input.x, 0.0, input.y)
	return local_dir.rotated(Vector3.UP, yaw)


## Pure, node-independent helper: one tick of gravity integration for a
## CharacterBody3D's vertical velocity. Clamps to 0 while grounded (instead
## of letting downward velocity accumulate into the floor) so the body
## doesn't stick/dig in or "pop" on the next frame it leaves the floor.
static func apply_gravity(
	current_y_velocity: float, gravity_amount: float, delta: float, is_grounded: bool
) -> float:
	if is_grounded and current_y_velocity < 0.0:
		return 0.0
	return current_y_velocity - gravity_amount * delta
