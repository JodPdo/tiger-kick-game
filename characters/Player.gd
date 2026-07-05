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
## RESOLVED (TK-P1-06, network-engineer): the ASSUMPTION below (kept for
## history) predicted that running gravity + move_and_slide() on every peer's
## Player instance, even non-authority copies, would fight the
## MultiplayerSynchronizer's incoming position/rotation writes every physics
## tick and jitter. Confirmed -- fixed by making _physics_process() return
## immediately for any Player that is NOT the local multiplayer authority
## (see below): non-authority instances now run zero local physics; their
## `position`/`rotation` are driven ENTIRELY by the synchronizer's replicated
## writes, which land outside of and are not overwritten by
## _physics_process(). Only the owning peer's own copy still simulates
## input -> velocity -> gravity -> move_and_slide(), exactly as before.
##
## Historical ASSUMPTION (TK-P1-04/05/06, network-engineer): per the card,
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

## TK-P2-16 Step 1 (Ability System scaffold, gameplay-engineer): the movement
## Tunables (walk_speed/sprint_multiplier/gravity), _physics_process(), and
## the pure statics (compute_velocity, camera_relative_dir, apply_gravity)
## that used to live here have MOVED, verbatim/behavior-preserving, to
## characters/components/MovementComponent.gd (a new child node added in
## Player.tscn). This file's history above (TK-P1-02/03/06) is kept as
## context for that moved code -- see MovementComponent.gd for the current
## implementation and its own doc comments. Everything below this point is
## unchanged and still lives on Player.gd/PlayerRoot: authority/naming
## (_enter_tree), the camera rig + mouse-look (_ready/_unhandled_input,
## CameraRig stays on Player until Step 2/CameraComponent), and
## get_view_camera().

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


## TK-BUG-P1-01 fix (network-engineer): this Player's multiplayer authority
## used to be assigned by PlayerSpawner AFTER add_child() (host-side directly,
## client-side from the `spawned` signal) -- but `spawned` fires AFTER this
## node's own `_ready()`, and by then Godot has already started delivering
## this instance's MultiplayerSpawner spawn-state and rejects a late
## authority change with "unable to process the pending spawn since it has
## no network ID" -- confirmed reproducible (see PlayerSpawner.gd class doc)
## by moving the assignment to `_ready()` instead during investigation.
##
## Fix: `_enter_tree()` runs on EVERY peer the instant this node enters the
## SceneTree -- BEFORE `_ready()` and before the `spawned` signal, the timing
## Godot's own error message recommends. We derive authority from the
## deterministic node.name == str(peer_id) naming contract (PlayerSpawner's
## spawn_function sets instance.name = str(id) before returning the node to
## be parented, so it's already in place by the time _enter_tree fires, on
## every peer, replicated or not). set_multiplayer_authority() is a purely
## LOCAL call (never propagates over the network by itself), so every
## peer's local copy independently deriving the SAME authority from the
## SAME node name is what keeps them all in agreement -- this is now the
## ONE source of truth for authority; PlayerSpawner no longer sets it at all
## (see its class doc). recursive = true (default) also covers this
## Player's MultiplayerSynchronizer child, so it replicates FROM the owning
## peer with no separate call needed.
##
## NOTE (see PlayerSpawner.gd class doc for the full story): this alone does
## NOT get the host-decided spawn POSITION to the owning peer -- once a peer
## holds authority over its own Player, MultiplayerSynchronizer only ever
## replicates FROM that peer TO others, never the reverse, so an
## authoritative peer's local value can never be overwritten by an incoming
## write for a property it now owns. PlayerSpawner's spawn_function
## delivers the initial position directly (authority-independent) before
## this node is even parented, so by the time _enter_tree() below runs,
## `position` is already correct and authority is irrelevant to it.
func _enter_tree() -> void:
	if name.is_valid_int():
		set_multiplayer_authority(int(name))
	else:
		# Tripwire (TK-BUG-P1-02 review nit #3): the naming contract
		# (node.name == str(peer_id), set by PlayerSpawner's spawn_function)
		# should make this branch unreachable. If it ever fires, this Player
		# silently keeps the default authority (peer 1 / the server), which
		# would hand a client's avatar to the host -- exactly the kind of
		# authority mixup TK-BUG-P1-01 was about. Log loudly rather than
		# fail silently (mirrors the guard the old _on_spawned() had).
		GameLog.error(
			"[Player] _enter_tree: non-numeric name '%s' -- authority NOT set, keeping default" % name
		)


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
##
## TK-BUG-P1-02 (review fix): the ESC branch below is GATED on the mouse
## currently being CAPTURED, and CONSUMES the event
## (get_viewport().set_input_as_handled()) when it releases capture. This is
## load-bearing for the TestArena.gd Leave path: _unhandled_input propagates
## from the DEEPEST node UP, so this Player (deep in the tree) runs BEFORE the
## scene-root TestArena on the SAME event, and Input.mouse_mode readback is
## immediate. Without the gate+consume, a single ESC tap would (1) release
## capture here, then (2) TestArena would see mouse == VISIBLE on that very
## same press and immediately _leave() -- one reflexive ESC ends the whole
## session (fatal on the host). With the gate+consume: while CAPTURED, ESC is
## eaten here (release only, TestArena never sees it); only once the mouse is
## ALREADY visible does ESC fall through un-consumed to TestArena to trigger
## Leave. Net UX: first ESC releases the mouse, a distinct second ESC leaves.
func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
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
		camera_rig.rotation.y -= motion.x
		spring_arm.rotation.x = clamp(spring_arm.rotation.x - motion.y, PITCH_MIN, PITCH_MAX)


## CONTRACT (producer-defined, TK-P1-03/TK-P1-05): returns the rig's
## Camera3D -- the one TK-P1-05's PlayerSpawner should make `current` for
## the local player, instead of a hardcoded `$Camera3D` child path. Returns
## the actual node regardless of how deep the rig nests it (currently
## CameraRig/SpringArm3D/Camera3D).
func get_view_camera() -> Camera3D:
	return camera


## TK-P2-16 Step 1: movement input handling (_physics_process) and the pure
## statics (compute_velocity, camera_relative_dir, apply_gravity) that used
## to be here have moved to characters/components/MovementComponent.gd --
## see this file's header above and MovementComponent.gd's own doc comments
## for the full (unchanged) history and rationale.
