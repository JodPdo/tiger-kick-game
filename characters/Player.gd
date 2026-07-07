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
@onready var camera: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var ability_controller: Node = $AbilityController

## TK-P2-16 Step 3 (Ability System scaffold, gameplay-engineer): role +
## replicated pose plumbing. See
## Tiger_Kick_Project_Docs/02_Technical/Ability_System_Design.md §5/§4.
##
## PlayerRoot is the single place `role` lives (design doc §2 table). Default
## &"outer" -- everyone starts as a plain player until GameManager (later
## card) says otherwise. Deliberately NOT part of MultiplayerSynchronizer /
## SceneReplicationConfig (design doc §4 channel B): role is HOST-DECIDED and
## must only ever arrive via GameManager's future apply_role_switch RPC --
## never inferred from ordinary owner-sync state, or a client could simply
## declare itself Tiger.
var role: StringName = &"outer"

## Replicated pose channel A (design doc §4): authored by the OWNING peer,
## replicated ON_CHANGE via MultiplayerSynchronizer -- see this scene's
## SceneReplicationConfig, same settings as position/rotation (spawn = false,
## replication_mode = ON_CHANGE). Default 0 / 0.0 means zero replication
## traffic until some future LOCAL_ONLY ability (Crouch/Lean -- TK-P3-05)
## actually sets them; nothing writes these yet this step (scaffold only).
## Cheating these only ever shows a remote a wrong pose, never a game-
## deciding lie (design doc §3 resolution criterion), which is exactly why
## they live in owner-sync state (channel A) and not host-RPC (channel B),
## unlike `role` above.
@export var stance: int = 0
@export var lean: float = 0.0

## TK-P2-10 (gameplay-engineer): replicated pose channel A, same rules as
## stance/lean above -- authored by the OWNING peer's MovementComponent (see
## MovementComponent._is_jumping, mirrored onto this property unconditionally
## every physics tick for simplicity; the underlying flag itself only ever
## actually CHANGES value at two transitions -- jump-fire / real-landing --
## so this property's VALUE only changes at those same two moments even
## though the assignment runs every tick), replicated ON_CHANGE via
## MultiplayerSynchronizer (this scene's SceneReplicationConfig) -- ON_CHANGE
## is what gates actual outgoing network traffic to real value changes, not
## the local assignment. Lets every
## OTHER peer (and the host, which is just "another peer" for a client-owned
## Player) know a Player has jumped and not landed yet, without needing that
## Player's own is_on_floor()/physics to be live locally -- non-authority
## copies never run physics at all (TK-P1-06 invariant, see
## MovementComponent's own doc), so this is the only way a remote observer
## can tell "this Player is mid-jump" at all.
##
## NAMING (review nit): named `is_jumping`, not `airborne` -- it is ONLY ever
## true from an actual jump impulse to landing; a player falling off a ledge
## (never jumped) reads false here the whole fall. See
## MovementComponent.is_jumping()'s own doc for why that scope gap matters to
## TK-P2-11 ("kick while jumping" vs "kick while falling").
##
## Cosmetic-only by design (design doc §3 resolution criterion: "cheating
## this only ever shows a remote a wrong pose") -- MUST NOT be trusted as an
## authoritative signal by any future HOST_AUTHORITATIVE ability (e.g.
## TK-P2-11 Jump-Kick); see MovementComponent.is_jumping()'s own doc for that
## open question, deliberately left for that later card.
@export var is_jumping: bool = false

## TK-P2-16 Step 1 (Ability System scaffold, gameplay-engineer): the movement
## Tunables (walk_speed/sprint_multiplier/gravity), _physics_process(), and
## the pure statics (compute_velocity, camera_relative_dir, apply_gravity)
## that used to live here have MOVED, verbatim/behavior-preserving, to
## characters/components/MovementComponent.gd (a new child node added in
## Player.tscn). This file's history above (TK-P1-02/03/06) is kept as
## context for that moved code -- see MovementComponent.gd for the current
## implementation and its own doc comments.
##
## TK-P2-16 Step 2 (same scaffold): the camera-rig tunables, _ready()'s mouse
## capture, and _unhandled_input() (mouse-look, ESC gate+consume, mouse-button
## recapture) that used to live here have MOVED, verbatim/behavior-preserving,
## to characters/components/CameraComponent.gd (a new child node added in
## Player.tscn) -- this file's TK-P1-03/TK-BUG-P1-02 history above is kept as
## context for that moved code -- see CameraComponent.gd for the current
## implementation, its own doc comments, and (critically) the ESC gate+consume
## banner. Everything below this point is unchanged and still lives on
## Player.gd/PlayerRoot: authority/naming (_enter_tree) and get_view_camera()
## (this file keeps its own `camera` @onready ref for that accessor --
## CameraRig/SpringArm3D/Camera3D themselves stay in the scene tree under
## Player; CameraComponent only holds the LOGIC that rotates
## CameraRig/SpringArm3D, reached via get_parent().get_node(...), same pattern
## as MovementComponent).


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


## CONTRACT (producer-defined, TK-P1-03/TK-P1-05): returns the rig's
## Camera3D -- the one TK-P1-05's PlayerSpawner should make `current` for
## the local player, instead of a hardcoded `$Camera3D` child path. Returns
## the actual node regardless of how deep the rig nests it (currently
## CameraRig/SpringArm3D/Camera3D).
func get_view_camera() -> Camera3D:
	return camera


## TK-P2-16 Step 3 (design doc §5 step 3): idempotent role setter. PlayerRoot
## is the single place `role` lives; calling this with the role it already
## has is a safe no-op rebuild (AbilityController.set_role() below always
## fully rebuilds from AbilityCatalog rather than diffing, so re-applying
## the same role is harmless, just wasteful).
##
## Distributes the new role to AbilityController now. CameraComponent's
## FP/TP swap (TK-P2-05) and MovementComponent's per-role speed profile
## (design doc §6 balance) are explicitly OUT of scope for this card/step --
## neither component has role-handling code yet, so nothing is called here
## for them; those later cards add their own handler and call it from here.
##
## Nobody calls this "for real" yet -- GameManager (TK-P2-04/09, later) is
## the intended caller once the real Role state machine and role-swap RPC
## (design doc §5 step 1: apply_role_switch) exist.
func set_role(new_role: StringName) -> void:
	role = new_role
	# Review nit (TK-P2-01 carried over from the TK-P2-16 Step 3 review):
	# `ability_controller` is an @onready var (assigned just before this
	# node's own _ready()) -- guard against a hypothetical caller invoking
	# set_role() on a Player that has not entered the tree yet (not ready),
	# where ability_controller would still be null. Not reachable today
	# (nobody calls set_role() before spawn), but this keeps the method safe
	# regardless of future callers/timing.
	if ability_controller:
		ability_controller.set_role(new_role)


## TK-P2-16 Step 1: movement input handling (_physics_process) and the pure
## statics (compute_velocity, camera_relative_dir, apply_gravity) that used
## to be here have moved to characters/components/MovementComponent.gd --
## see this file's header above and MovementComponent.gd's own doc comments
## for the full (unchanged) history and rationale.
##
## TK-P2-16 Step 2: mouse capture (_ready()), mouse-look/ESC-gate/recapture
## (_unhandled_input()), and the camera tunables that used to be here have
## moved to characters/components/CameraComponent.gd -- see this file's
## header above and CameraComponent.gd's own doc comments (including the ESC
## gate+consume banner) for the full (unchanged) history and rationale.
