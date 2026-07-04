extends CharacterBody3D
## Player.gd -- reusable Player prefab (res://characters/Player.tscn).
##
## TK-P1-01 (done): scaffold -- node tree, placeholder visuals, synced
## transform (position/rotation via MultiplayerSynchronizer).
## TK-P1-02 (this card): movement input + gravity + Sprint.
## Still out of scope here: real camera rig (TK-P1-03 replaces the
## placeholder Camera3D below with a SpringArm3D rig, and will make
## movement camera-relative -- see ASSUMPTION below), spawning (TK-P1-04),
## per-player authority assignment (TK-P1-05), Kick/Tag (TK-P2-0x).
##
## Reference: Tiger_Kick_Project_Docs/02_Technical/TDD.pdf
##   §3 Folder Structure -- res://characters/ # Player, TigerController.
##   §4 Scene Tree        -- Player (n): CharacterBody3D, CameraRig,
##                            MultiplayerSynchronizer, KickHitbox (Area3D),
##                            TagArea (Area3D). KickHitbox/TagArea are
##                            deferred to TK-P2-01/TK-P2-02 -- out of scope
##                            here.
##   §8.1 Player Role State -- Idle -> Move -> Sprint/Kick/Caught -> Tiger ->
##                            Outer -> Idle. Move/Sprint (this card) drive
##                            the body; Tag Sequence/Role state machine is
##                            TK-P2-0x future work.
##   §11 Game Balance       -- Player Speed 5.0 m/s baseline, Sprint
##                            Multiplier x1.4. These are design-owned
##                            tunables, so they are @export vars here (NOT
##                            hard-coded) so the producer/designer can tune
##                            them in the Inspector without touching code.
##                            `gravity` is NOT specified in TDD §11; defaulted
##                            to Godot's own default_gravity (9.8 m/s^2).
##
## ASSUMPTION (flag for TK-P1-03 reconciliation): movement here is
## WORLD-relative, not camera-relative -- input.x maps straight to world X,
## input.y maps straight to world Z (Godot forward = -Z, and
## Input.get_vector's "forward" axis is already negative, so no extra sign
## flip is needed). No player-facing rotation is applied. This is the
## simplest thing that satisfies TK-P1-02 ("keep it simple and documented");
## TK-P1-03's camera rig is expected to replace the direction basis with
## camera-relative axes (and likely add facing rotation) without touching
## the sprint/speed math below.
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
@onready var camera: Camera3D = $Camera3D
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


func _ready() -> void:
	GameLog.debug("[Player] ready (name=%s)" % name)


## Movement input (TK-P1-02): reads move_forward/back/left/right + sprint,
## drives horizontal velocity, applies gravity so the body stays grounded,
## and calls move_and_slide(). Horizontal input is gated on
## is_multiplayer_authority() so only the owning peer drives their own
## Player once TK-P1-05 assigns per-player authority; with no multiplayer
## peer set up (offline/solo test), is_multiplayer_authority() is true for
## everyone, so this still works standalone. Gravity applies regardless of
## authority (see network-engineer ASSUMPTION above).
func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		var input_dir: Vector2 = Input.get_vector(
			"move_left", "move_right", "move_forward", "move_back"
		)
		var sprinting: bool = Input.is_action_pressed("sprint")
		var horizontal: Vector3 = compute_velocity(
			input_dir, walk_speed, sprint_multiplier, sprinting
		)
		velocity.x = horizontal.x
		velocity.z = horizontal.z

	velocity.y = apply_gravity(velocity.y, gravity, delta, is_on_floor())

	move_and_slide()


## Pure, node-independent helper (GUT-testable without a scene tree/Input):
## given a 2D input vector (x = left(-)/right(+), y = forward(-)/back(+),
## e.g. straight from Input.get_vector) and the walk/sprint tunables, returns
## the intended horizontal velocity as a world-space Vector3 (Y always 0 --
## vertical motion is gravity's job, see apply_gravity() below).
## World-relative (not camera-relative) by design -- see ASSUMPTION above.
static func compute_velocity(
	input_dir: Vector2, walk: float, sprint_mult: float, sprinting: bool
) -> Vector3:
	var speed: float = walk * sprint_mult if sprinting else walk
	return Vector3(input_dir.x, 0.0, input_dir.y) * speed


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
