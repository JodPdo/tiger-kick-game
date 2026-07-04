extends CharacterBody3D
## Player.gd -- reusable Player prefab (res://characters/Player.tscn).
##
## TK-P1-01 (done): scaffold -- node tree, placeholder visuals, synced
## transform (position/rotation via MultiplayerSynchronizer).
## TK-P1-02 (done): movement input + gravity + Sprint.
## TK-P1-03 (this card): third-person camera rig (CameraRig -> SpringArm3D
## -> Camera3D), mouse-look, and camera-relative movement -- resolves the
## TK-P1-02 world-relative ASSUMPTION below (now historical; kept for
## context). Still out of scope here: spawning (TK-P1-04, done),
## per-player authority assignment (TK-P1-05), Kick/Tag (TK-P2-0x).
##
## Reference: Tiger_Kick_Project_Docs/02_Technical/TDD.pdf
##   §3 Folder Structure -- res://characters/ # Player, TigerController.
##   §4 Scene Tree        -- Player (n): CharacterBody3D, CameraRig,
##                            MultiplayerSynchronizer, KickHitbox (Area3D),
##                            TagArea (Area3D). KickHitbox/TagArea are
##                            deferred to TK-P2-01/TK-P2-02 -- out of scope
##                            here. CameraRig is implemented here as
##                            CameraRig (Node3D, yaw) -> SpringArm3D (pitch,
##                            clamped, wall-avoidance via its built-in
##                            shape/ray cast) -> Camera3D (pulled back by
##                            SpringArm3D.spring_length).
##   §8.1 Player Role State -- Idle -> Move -> Sprint/Kick/Caught -> Tiger ->
##                            Outer -> Idle. Move/Sprint drive the body;
##                            Tag Sequence/Role state machine is TK-P2-0x
##                            future work.
##   §11 Game Balance       -- Player Speed 5.0 m/s baseline, Sprint
##                            Multiplier x1.4. These are design-owned
##                            tunables, so they are @export vars here (NOT
##                            hard-coded) so the producer/designer can tune
##                            them in the Inspector without touching code.
##                            `gravity` is NOT specified in TDD §11; defaulted
##                            to Godot's own default_gravity (9.8 m/s^2).
##                            Mouse sensitivity is a controls setting
##                            (ConfigManager DEFAULTS.controls.mouse_sensitivity,
##                            wired by TK-PX-05 Settings > Controls), read
##                            here via ConfigManager.get_value() with an
##                            @export fallback default for standalone/no-
##                            autoload contexts (e.g. isolated unit tests).
##
## HISTORICAL ASSUMPTION (TK-P1-02, resolved by this card): movement used to
## be WORLD-relative (input.x -> world X, input.y -> world Z, no rotation
## applied). TK-P1-03 replaces this: WASD is now relative to CameraRig's
## yaw (see camera_relative_dir() below), which is also what mouse-look
## rotates. The Player body itself is never rotated by camera-look (no
## character model yet to face); CameraRig is a free-look yaw independent
## of the body. NEW ASSUMPTION (flag for later polish/animation cards, once
## a real player model exists): MultiplayerSynchronizer replicates the
## Player node's own `.:rotation` (TK-P1-01), which stays at identity under
## this scheme -- remote peers currently have no way to see which way a
## Player is "facing" from replicated state alone. That's fine while the
## mesh is a placeholder capsule with no facing-dependent visual, but a
## future card (character model / animation, Phase 4, or a Phase 2 role
## state machine card) should decide whether the body should instead yaw to
## match the camera (so replicated rotation means something) or whether a
## separate replicated "facing" property is needed.
##
## ASSUMPTION (flag for TK-P1-04/05/06, network-engineer): per the card,
## input-driven horizontal movement is gated on `is_multiplayer_authority()`,
## but gravity + move_and_slide() run every frame on every peer's Player
## instance regardless of authority. Once MultiplayerSynchronizer is
## actively overwriting position/rotation on non-authority peers (already
## wired in TK-P1-01), that peer's own local gravity/collision fighting the
## synced transform every physics tick may cause jitter. Flagging this now;
## network-engineer may want non-authority instances to skip
## move_and_slide() entirely once TK-P1-05 authority is live.

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var camera_rig: Node3D = $CameraRig
@onready var spring_arm: SpringArm3D = $CameraRig/SpringArm3D
@onready var camera: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer

## -- Tunables (TDD §11 Game Balance; design-owned, NOT hard-coded) ----------

## Baseline walking speed, m/s. TDD §11 "Player Speed": 5.0 m/s baseline.
@export var walk_speed: float = 5.0

## Multiplier applied to walk_speed while `sprint` is held.
## TDD §11 "Sprint Multiplier": x1.4.
@export var sprint_multiplier: float = 1.4

## Downward acceleration, m/s^2. Not specified in TDD §11 -- defaulted to
## Godot's engine default (ProjectSettings physics/3d/default_gravity = 9.8).
@export var gravity: float = 9.8

## -- Camera rig tunables (TK-P1-03) ------------------------------------------

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


func _ready() -> void:
	GameLog.debug("[Player] ready (name=%s)" % name)
	if is_multiplayer_authority():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Mouse-look (TK-P1-03): rotates CameraRig's yaw (Y) and SpringArm3D's
## pitch (X, clamped to PITCH_MIN..PITCH_MAX) from raw mouse motion. Gated on
## is_multiplayer_authority() so only the local/owning peer's rig responds
## (same authority caveat as _physics_process below applies pre-TK-P1-05).
## Mouse capture UX (documented, kept simple per the card): captured on
## _ready() for the authority player; Esc releases it (e.g. to reach OS/UI);
## a left-click while released recaptures it. No pause menu exists yet --
## a future pause/menu card should decide how capture interacts with that UI
## (e.g. suspend capture while a menu is open) rather than this script owning
## that policy.
func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
		camera_rig.rotation.y -= motion.x
		spring_arm.rotation.x = clamp(spring_arm.rotation.x - motion.y, PITCH_MIN, PITCH_MAX)


## CONTRACT (producer-defined, TK-P1-03/TK-P1-05): returns the rig's
## Camera3D -- the one TK-P1-05's PlayerSpawner should make `current` for
## the local player, instead of a hardcoded `$Camera3D` child path. Returns
## the actual node regardless of how deep the rig nests it (currently
## CameraRig/SpringArm3D/Camera3D).
func get_view_camera() -> Camera3D:
	return camera


## Movement input (TK-P1-02, made camera-relative by TK-P1-03): reads
## move_forward/back/left/right + sprint, rotates the input direction by
## CameraRig's current yaw (see camera_relative_dir() below) so WASD is
## relative to where the camera/rig is looking, drives horizontal velocity,
## applies gravity so the body stays grounded, and calls move_and_slide().
## Horizontal input is gated on is_multiplayer_authority() so only the
## owning peer drives their own Player once TK-P1-05 assigns per-player
## authority; with no multiplayer peer set up (offline/solo test),
## is_multiplayer_authority() is true for everyone, so this still works
## standalone. Gravity applies regardless of authority (see network-engineer
## ASSUMPTION above).
func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		var input_dir: Vector2 = Input.get_vector(
			"move_left", "move_right", "move_forward", "move_back"
		)
		var sprinting: bool = Input.is_action_pressed("sprint")
		var rig_yaw: float = camera_rig.rotation.y
		var relative_dir: Vector3 = camera_relative_dir(input_dir, rig_yaw)
		var horizontal: Vector3 = compute_velocity(
			Vector2(relative_dir.x, relative_dir.z), walk_speed, sprint_multiplier, sprinting
		)
		velocity.x = horizontal.x
		velocity.z = horizontal.z

	velocity.y = apply_gravity(velocity.y, gravity, delta, is_on_floor())

	move_and_slide()


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
## rotated by camera-look (see HISTORICAL ASSUMPTION above), CameraRig's
## local yaw already equals its effective world yaw. Magnitude of `input` is
## preserved (not normalized), matching compute_velocity's existing
## diagonal-input behavior.
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
