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
## TK-P2-10 (gameplay-engineer, later card): Jump added here, NOT as a new
## characters/abilities/*Ability.gd -- see JumpRules.gd's own class doc (same
## folder) for the full architecture note/citations resolving the
## CURRENT_PHASE.md-vs-design-doc phrasing question for this exact card.
## Jump is authority-side local physics + MultiplayerSynchronizer sync
## (Player.gd's new `is_jumping` channel-A property), same shape as the
## Sprint/gravity code already below -- it does NOT go through
## AbilityController's RPC surface.
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

## TK-P2-10: this component's OWN authoritative "am I currently mid-jump"
## flag -- independent of `_body.is_on_floor()`, which is only ever accurate
## on the owning peer's copy (non-authority Players never call
## move_and_slide(), see the class doc above, so their is_on_floor() is
## whatever it last happened to be, not live physics). Set true the instant
## a jump fires, cleared once a REAL landing is detected (see step_jump()
## below) -- this is the "no double-jump mid-air" guard the card's DoD calls
## out, checked together with is_on_floor() by JumpRules.can_jump()
## (belt-and-suspenders against is_on_floor() lagging a frame while still
## rising, a known CharacterBody3D quirk on slopes/moving floors -- see
## step_jump()'s own doc for the fix that makes this guard load-bearing
## rather than redundant with is_on_floor() alone).
## NAMING (review nit): named `_is_jumping`, not `_airborne` -- it is ONLY
## ever set true by an actual jump impulse, and cleared on landing. A player
## walking off a ledge (falling, never jumped) is genuinely airborne
## (is_on_floor() == false) but this flag stays false the whole time -- see
## is_jumping()'s own doc below for why that gap matters to TK-P2-11.
## THIS local flag only ever actually CHANGES value at those two transitions
## (jump-fire / real-landing, both inside step_jump()); mirrored onto
## `_body.is_jumping` (see Player.gd) every _physics_process tick for
## simplicity (an unconditional assignment of the current value, not a
## conditional "only on change" write) so it replicates to every OTHER peer
## via MultiplayerSynchronizer (design doc §4 channel A, same owner-authored
## pattern as `stance`/`lean`) -- writing the SAME value every tick is a
## harmless no-op (MultiplayerSynchronizer's own ON_CHANGE replication mode
## is what actually gates outgoing network traffic to real value changes,
## not this assignment).
var _is_jumping: bool = false

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

## TK-P2-10 (gameplay-engineer): Jump impulse, m/s applied to velocity.y the
## instant a grounded jump fires. Not yet in Game_Balance.md (no jump entry
## exists there today) -- placeholder tuned for "readable, not floaty" feel;
## @export (not hard-coded) so producer/designer can retune once Jump is
## recorded in Game_Balance.md/GDD (per this card's own DoD note to do so),
## same "expose design-owned tunables" rule CLAUDE.md sets for every other
## balance value in this file.
@export var jump_speed: float = 5.0


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

	# TK-P2-10: is_on_floor() reflects the result of LAST tick's
	# move_and_slide() (no physics has run yet this tick) -- read once and
	# reuse for both step_jump() and gravity below, same "one read, two uses"
	# shape apply_gravity's own doc already relies on.
	var is_grounded: bool = _body.is_on_floor()

	# Mouse-mode guard (TK-P2-10, matching AbilityController's own kick-input
	# guard, design doc §4a spirit + CameraComponent's ESC gate/consume): while
	# the mouse is released (paused-for-UI / mid ESC-ESC Leave), Space is not
	# gameplay intent -- without this, jump would still fire while the player
	# has tabbed out to a menu with the mouse visible. Movement's WASD axis
	# itself is left as-is (pre-existing behavior, out of scope for this card)
	# -- only the newly-added jump TRIGGER gets this guard.
	var jump_input_pressed: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and Input.is_action_just_pressed("jump")

	_body.velocity.y = step_jump(is_grounded, _body.velocity.y, jump_input_pressed)
	_body.is_jumping = _is_jumping

	_body.velocity.y = apply_gravity(_body.velocity.y, gravity, delta, is_grounded)

	_body.move_and_slide()


## TK-P2-10 (code-review fix S2): the landing-clear + jump-trigger decision,
## extracted out of _physics_process specifically so it is reachable by GUT
## WITHOUT a live CharacterBody3D/physics tick -- the Phase-1 lesson (see
## CURRENT_PHASE.md's [0.28] audit note) is that per-card PURE-function tests
## (JumpRules.can_jump() alone) can stay green while the surrounding WIRING
## defeats them; this method IS that wiring, isolated so a GUT test can drive
## it directly with hand-built is_grounded/velocity_y/jump_input_pressed
## values instead of only being exercisable inside a live physics tick. Not a
## static/pure function like JumpRules' own helpers -- it deliberately owns
## the `_is_jumping` mutation (the one piece of state this whole card is
## about), so an instance method is the honest shape; JumpRules.can_jump()/
## jump_velocity() stay the pure decision logic this method is a thin shell
## around (same "pure statics + thin caller" split KickAbility.host_validate()
## uses around KickRules).
##
## Landing-clear ordering (the actual bug the review caught): clearing
## `_is_jumping` on `is_grounded` ALONE let a stray is_on_floor()-true tick
## while genuinely still RISING (a known CharacterBody3D lag on slopes/moving
## floors -- never reproduces on the flat TestArena, which is exactly why
## manual flat-ground testing alone missed it) silently clear the flag and
## permit an illegal mid-air re-jump -- i.e. JumpRules.can_jump()'s own
## is_jumping guard became dead code, reducing the whole gate to
## `is_grounded` alone. Requiring `current_velocity_y <= 0.0` too (a landing
## must be BOTH grounded AND non-upward) keeps a REAL landing (velocity.y
## goes <= 0 at touchdown) clearing the flag the SAME tick -- same-tick
## land-then-jump still works -- while a stale floor-true during the RISING
## half of a jump (velocity.y > 0.0) cannot falsely clear it, making the
## can_jump() guard actually load-bearing.
##
## Returns the (possibly jump-modified) vertical velocity for the CALLER to
## assign to `_body.velocity.y` -- this method never touches `_body` itself,
## which is exactly what makes it callable with no scene tree.
func step_jump(is_grounded: bool, current_velocity_y: float, jump_input_pressed: bool) -> float:
	if is_grounded and _is_jumping and current_velocity_y <= 0.0:
		_is_jumping = false

	if jump_input_pressed and JumpRules.can_jump(is_grounded, _is_jumping):
		_is_jumping = true
		return JumpRules.jump_velocity(jump_speed)

	return current_velocity_y


## TK-P2-11 HOOK (Jump-Kick, gameplay-engineer): owner-side query for "did
## THIS peer's own Player jump and not land yet" -- e.g. for a future
## JumpKickAbility.can_activate()'s owner-predicted precheck (design doc §3:
## can_activate is always an owner-side PREDICTION, never authoritative) to
## gate "kick while jumping" input the same local-feel way KickAbility.
## can_activate() gates its own cooldown. Deliberately just a getter over
## `_is_jumping` -- no new state, no ability-shaped API here (this file stays
## a movement primitive, per the design doc; see JumpRules.gd's own class doc
## for the full architecture note).
##
## SCOPE GAP (review nit, read before wiring TK-P2-11): this flag is ONLY
## ever set by an actual jump impulse and cleared on landing -- a player
## simply walking off a ledge (falling, is_on_floor() == false, never
## pressed jump) is genuinely airborne but this returns false for them the
## entire fall. If TK-P2-11's "Jump Kick" is meant to also cover "kick while
## falling off a ledge" (not just "kick after pressing jump"), this getter is
## NOT enough on its own -- that card must either accept the narrower
## "must have actually jumped" scope (matching its own name), or add a
## separate general "not is_on_floor()" check alongside this one. Not
## resolved here on purpose -- a design-scope call for that later card.
##
## NOT authoritative either way: a HOST_AUTHORITATIVE Jump-Kick ability's
## host_validate() must independently re-derive whether the ATTACKER was
## really jumping/airborne server-side rather than trust this getter's
## remote/replicated `_body.is_jumping` mirror at face value -- that mirror
## is channel-A owner-authored state (design doc §4), spoofable the same
## "cheating this only ever shows a remote a wrong pose" way `stance`/`lean`
## already are documented to be. Left as an explicitly OPEN question for
## TK-P2-11 to resolve (e.g. re-derive jumping-ness from a host-side
## position/velocity trend, or accept the channel-A signal, or ratify a
## wider host-side landing tolerance) -- deliberately NOT decided by this
## card.
func is_jumping() -> bool:
	return _is_jumping


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
