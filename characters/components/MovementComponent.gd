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

## TK-P2-18 (Pounce, gameplay-engineer): this component's own authoritative
## "pounce burst in flight" state -- same "short-lived LOCAL physics override
## _physics_process() consults instead of the normal WASD velocity calc"
## precedent `_is_jumping`/step_jump() immediately above already establishes,
## just overriding the HORIZONTAL axes instead of the vertical one. Sentinel
## convention matches KickRules/TagAbilityRules/PounceRules' own
## `last_fire_ms < 0` == "not active" shape: `_pounce_end_ms < 0` means no
## burst is currently in flight; once set, it holds the wall-clock ms
## (Time.get_ticks_msec()) the burst naturally expires -- see
## resolve_horizontal_velocity() below, which owns clearing it again.
##
## Owner-side ONLY: this state exists purely so the OWNING peer's own
## _physics_process() can apply the burst velocity locally (see
## characters/abilities/PounceAbility.gd's on_activate_local() doc for why
## Pounce's owner-side "prediction" is the actual movement itself, going
## further than Kick/Tag's windup-only prediction). host_validate()/
## host_apply() on PounceAbility never read or write this -- they only gate
## LEGALITY (cooldown/sequence_active); the movement already happened here,
## owner-side, by the time the host round-trip resolves.
var _pounce_end_ms: int = -1
var _pounce_velocity: Vector3 = Vector3.ZERO

## TK-P2-17 (Kick Stagger, gameplay-engineer): this component's own
## authoritative "stagger knockback in flight" state -- same "short-lived
## LOCAL physics state _physics_process() consults" precedent
## _pounce_end_ms/_pounce_velocity immediately above already establishes,
## but ADDITIVE rather than an override (see resolve_horizontal_velocity()
## below for exactly why that difference is the load-bearing part of this
## card's "stagger, not stun" requirement). Sentinel convention matches
## _pounce_end_ms's own `< 0` == "not active" shape: `_stagger_start_ms < 0`
## means no stagger is currently in flight; once set, it holds the wall-clock
## ms (Time.get_ticks_msec()) the knockback BEGAN (not when it ends -- unlike
## Pounce's fixed-speed burst, the knockback continuously DECAYS from
## `_stagger_speed` toward 0 over `_stagger_duration_ms`, so the caller needs
## the start time to compute "how far into the decay am I right now", see
## resolve_stagger_knockback() below).
##
## Owner-side ONLY, same reasoning _pounce_end_ms's own doc gives: this state
## exists purely so the STAGGERED player's own peer can apply the knockback
## to itself locally (see characters/abilities/KickAbility.gd's on_confirmed()
## doc for why the TARGET's own client -- not the kicker's -- is the one that
## calls start_stagger(), reusing the existing rpc_confirm broadcast rather
## than a new RPC). There is no host-side ledger for this at all: unlike
## Kick/Tag/Pounce, Kick Stagger has no legality/cooldown decision of its own
## to make -- by the time on_confirmed() runs, the KICK itself has already
## been authoritatively decided (KickAbility.host_validate()); the stagger is
## purely a COSMETIC/local movement consequence of that already-confirmed
## result, same "cosmetic, not authoritative, a cheating client can ignore
## this locally" caveat every other owner-side effect in this codebase already
## documents (Pounce's burst, the Safe Circle owner clamp, both per Change Log
## [0.45]/TK-P2-28's ruling that this class of limitation is accepted for
## Phase 2).
var _stagger_start_ms: int = -1
var _stagger_duration_ms: int = 0
var _stagger_direction: Vector3 = Vector3.ZERO
var _stagger_speed: float = 0.0

## -- Tunables (TDD §11 Game Balance; design-owned, NOT hard-coded) ----------
## Moved verbatim from Player.gd, TK-P2-16 Step 1. Values were UNCHANGED at
## that step -- per-role balance tuning was explicitly OUT of scope there.

## Currently-ACTIVE walk speed, m/s -- what _physics_process() actually reads
## every tick. TK-P2-04 (gameplay-engineer): this is now a DERIVED/working
## value, overwritten by set_role() below the instant a role is known (see
## _ready() below, which calls set_role(_body.role) at spawn, same pattern
## AbilityController._ready() already uses for the ability catalog). The
## @export default (5.0, the old pre-role-profile TDD §11 stand-in Game_
## Balance.md §2 explicitly calls out as superseded) only matters for an
## instance that is never given a role -- e.g. a bare `.new()` in a unit test
## that calls compute_velocity() directly without ever calling set_role() --
## kept as a safe, previously-shipped fallback rather than deleted outright.
@export var walk_speed: float = 5.0

## Currently-ACTIVE multiplier applied to walk_speed while `sprint` is held.
## Same "derived, overwritten by set_role()" status as walk_speed above.
@export var sprint_multiplier: float = 1.4

## -- Per-role speed profile (TK-P2-04, gameplay-engineer) -------------------
## Wires Tiger_Kick_Project_Docs/01_Design/Game_Balance.md §2 ("ความเร็ว
## (m/s) — per-role") into MovementComponent for the first time -- design doc
## Ability_System_Design.md §5 step 3 lists "MovementComponent apply role
## speed profile" as one of exactly three things PlayerRoot.set_role()
## distributes (AbilityController catalog swap and this profile; the third,
## CameraComponent FP/TP, is TK-P2-05's separate job). Game_Balance.md §2
## itself flags these as "ค่าเป้า...จนกว่า role speed profile จะ wire" -- this
## card/commit IS that wiring landing. Absolute m/s (not multipliers) to
## match the balance table directly; @export (not hard-coded) per CLAUDE.md's
## "expose design-owned tunables" rule, same as every other balance value in
## this file.
##
## Human (Outer): walk 4.0 / sprint 6.0 m/s.
@export var outer_walk_speed: float = 4.0
@export var outer_sprint_speed: float = 6.0

## Tiger: walk AND sprint both capped at human-walk (4.0) -- "เสือกด sprint
## ได้แต่เพดาน = human walk": sprinting gives the Tiger no speed advantage at
## all, by design (hunt-not-chase; see Game_Balance.md §3 locked intent).
@export var tiger_walk_speed: float = 4.0
@export var tiger_sprint_speed: float = 4.0

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

## -- Safe Circle boundary (TK-P2-06, gameplay-engineer) ---------------------
## Design-locked balance value (Tiger_Kick_Project_Docs/01_Design/
## Game_Balance.md §4 "Safe Circle radius" = 5.0m, Change Log [0.34]/[0.42]
## design ruling) -- @export per CLAUDE.md's "expose design-owned tunables"
## rule, same as every other balance value in this file. See
## managers/GameManager.gd's own matching @export for the host-side
## correction half of this boundary (an independent copy, not a shared
## constant -- same "each file keeps its own balance-value copy" convention
## exit_radius_m there already uses; there is no single shared autoload for
## design-locked values in this codebase).
##
## Applied ONLY to the Tiger (design ruling point 2: Outer/human players must
## stay free to walk in AND out of the circle to Kick and flee -- see
## apply_safe_circle_boundary() below for the role gate). This is the OWNER'S
## OWN local prediction half of the boundary -- runs every physics tick on
## the owning peer only (the whole _physics_process() below is already gated
## on is_multiplayer_authority(), see that method's TK-P1-06 invariant doc),
## same "owning client predicts locally" shape KickAbility/TagAbility's
## on_activate_local() already use for their own local feel. A compromised
## client could skip this local clamp -- see managers/GameManager.gd's own
## host-side correction (_physics_process()/correct_tiger_position()) for the
## authoritative backstop design ruling point 3 requires; this export/method
## pair is deliberately NOT that backstop by itself.
@export var safe_circle_radius: float = 5.0


## TK-P2-04 (gameplay-engineer): apply the initial speed profile at spawn,
## same "build my own ITS OWN state from PlayerRoot's `role` the instant I
## exist, without waiting for GameManager" reasoning
## AbilityController._ready() already documents for the ability catalog
## (GameManager/the real Role state machine's caller, TK-P2-03, does not
## broadcast a role for the FIRST Tiger until TK-P2-09 lands) -- default
## &"outer" (Player.gd's own default) means every Player starts at Human
## walk/sprint speeds until a real role-swap broadcast changes it.
func _ready() -> void:
	set_role(_body.role)


## TK-P2-04 (Role state machine, gameplay-engineer): the "property" half of
## this card's title (design doc §5 step 3 / §6 balance table) -- selects
## this Player's ACTIVE walk_speed/sprint_multiplier from the per-role
## tunables above. Called by Player.set_role() (PlayerRoot) alongside
## AbilityController.set_role() -- see that method's own doc. Idempotent,
## same as AbilityController.set_role(): always recomputes from the tunables
## above rather than diffing, so re-applying the same role is a harmless
## no-op recompute.
##
## Unrecognized role values cannot reach here in practice -- Player.set_role()
## rejects them via RoleRules.is_valid_role() before ever calling this -- but
## this still defaults any non-&"tiger" value to the Outer/Human profile
## (fail-safe: an unrecognized role should never accidentally grant the
## SLOWER/weaker Tiger movement profile to what might actually be a Human,
## nor vice versa grant Tiger speed to an unrecognized value).
func set_role(role: StringName) -> void:
	if role == &"tiger":
		walk_speed = tiger_walk_speed
		sprint_multiplier = speed_profile_multiplier(tiger_walk_speed, tiger_sprint_speed)
	else:
		walk_speed = outer_walk_speed
		sprint_multiplier = speed_profile_multiplier(outer_walk_speed, outer_sprint_speed)


## Pure, node-independent helper (GUT-testable, TK-P2-04): compute_velocity()
## multiplies walk_speed by sprint_multiplier while sprinting (see that
## function below) -- this converts the balance table's ABSOLUTE sprint
## speed (Game_Balance.md §2, e.g. Human sprint 6.0 m/s) into the multiplier
## compute_velocity() already expects, without changing that pure function's
## existing signature/behavior (kept identical on purpose -- it is already
## covered by tests/test_player_movement.gd and used as-is elsewhere).
## Guards walk == 0.0 (degenerate/misconfigured tunable) by returning 1.0
## (sprint == walk, i.e. sprinting grants no advantage) rather than dividing
## by zero.
static func speed_profile_multiplier(walk: float, sprint: float) -> float:
	if walk <= 0.0:
		return 1.0
	return sprint / walk


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
	# TK-P2-18 (Pounce, gameplay-engineer): while a burst is in flight this
	# OVERRIDES the normal WASD result outright (see resolve_horizontal_velocity()
	# below for why override-not-blend is the right shape, same relationship
	# step_jump() already has with gravity on the vertical axis).
	horizontal = resolve_horizontal_velocity(Time.get_ticks_msec(), horizontal)
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

	# TK-P2-06 (Safe Circle, gameplay-engineer): post-move radial clamp, role-
	# gated to the Tiger only -- see apply_safe_circle_boundary()'s own doc
	# (extracted the same "GUT-testable without a live physics tick" way
	# step_jump() below is) for why this reads `_body.position` AFTER
	# move_and_slide() rather than pre-empting velocity: ordinary collision
	# (the Floor, any future scenery) resolves first, then the boundary is
	# enforced as a final position clamp on top.
	_body.position = apply_safe_circle_boundary(_body.role, _body.position)


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


## TK-P2-18 (Pounce, gameplay-engineer): starts a horizontal velocity-override
## burst -- called from characters/abilities/PounceAbility.gd's
## on_activate_local() (owner-side IMMEDIATE execution, not a host round-trip
## -- see that method's own doc for why Pounce's "prediction" IS the actual
## movement, unlike Kick/Tag's windup-only prediction). `direction` need not
## already be flat/normalized on entry -- flattened (Y zeroed) and normalized
## here so a caller passing a raw camera-relative direction (which may carry
## residual Y, or a non-unit length from diagonal input) can't accidentally
## scale the burst speed; a degenerate zero-length direction (e.g. a caller
## bug) safely no-ops to Vector3.ZERO rather than dividing by zero in
## normalized().
func start_pounce_burst(direction: Vector3, speed: float, duration_sec: float) -> void:
	var flat_dir: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if flat_dir.length() > 0.0001:
		flat_dir = flat_dir.normalized()
	_pounce_velocity = flat_dir * speed
	_pounce_end_ms = Time.get_ticks_msec() + int(duration_sec * 1000.0)


## TK-P2-18: owner-only cancel. Called from PounceAbility.on_rejected() when
## the host rejects an activation that ALREADY started moving owner-side (see
## that method's own doc for why this is the one step genuinely different
## from Kick/Tag's on_rejected() template -- a windup animation has nothing
## physical to undo; a Pounce burst does). Also usable generically as "stop
## whatever burst is active right now" without needing to know its remaining
## time.
func cancel_pounce_burst() -> void:
	_pounce_end_ms = -1
	_pounce_velocity = Vector3.ZERO


## TK-P2-18: the horizontal-velocity-override DECISION, extracted out of
## _physics_process the same "GUT-testable without a live physics tick"
## reason step_jump()/apply_safe_circle_boundary() are already extracted for
## -- callable directly with a hand-built `now_ms`/`wasd_velocity` pair, no
## scene tree required. While a burst is active (`_pounce_end_ms >= 0`) this
## OVERRIDES the caller's normal WASD compute_velocity() result outright (not
## blended/added) -- a burst is meant to feel like a committed dash, not
## something WASD can fight against mid-flight, the same "override, not
## additive" relationship step_jump() already has with gravity on the
## vertical axis. Auto-expires the burst once `now_ms` reaches
## `_pounce_end_ms` -- this method owns clearing that state itself (same
## self-clearing shape step_jump()'s landing-clear already has for
## `_is_jumping`), so callers never need to separately notice/cancel a burst
## that simply ran its course.
##
## TK-P2-17 (Kick Stagger, gameplay-engineer): a stagger knockback (see
## resolve_stagger_knockback() below) is then ADDED on top of whichever base
## result the Pounce check above produced (Pounce-override or plain WASD) --
## this is the ONE deliberate, load-bearing difference from how Pounce's own
## burst is handled just above, and it is exactly what satisfies this card's
## hard "ห้าม stun เต็ม" (no full stun) requirement: an override (like
## Pounce's, or like a hypothetical "freeze velocity to knockback_vector for
## 0.3s") would remove 100% of the Tiger's own WASD control for the whole
## window, which the card explicitly forbids. Adding instead means the
## staggered Tiger can immediately fight the knockback with WASD, walk out of
## it sideways, or lean into it to get pushed further -- full agency is
## retained the entire ~0.3s, only the NET displacement is affected (pushed
## back on top of whatever they were already doing), which is what "stagger"
## (impaired, still playable) means as distinct from "stun" (frozen). See
## characters/components/StaggerRules.gd's own class doc for the matching
## "why linear decay, not a flat cutoff" half of this same reasoning.
func resolve_horizontal_velocity(now_ms: int, wasd_velocity: Vector3) -> Vector3:
	var base_velocity: Vector3 = wasd_velocity
	if _pounce_end_ms >= 0:
		if now_ms >= _pounce_end_ms:
			cancel_pounce_burst()
		else:
			base_velocity = _pounce_velocity
	return base_velocity + resolve_stagger_knockback(now_ms)


## TK-P2-18 HOOK: owner-side query for "is a Pounce burst currently in
## flight" -- same plain-getter-over-internal-state shape is_jumping() above
## already uses (no new ability-shaped API here; this file stays a movement
## primitive, per the design doc). Not consumed by any other card yet; left
## available for e.g. a future can_activate() precheck ("don't let a Tiger
## re-trigger Pounce mid-burst") should design ever want one -- see
## PounceAbility.gd's own can_activate()/host_validate() docs for why that
## guard is NOT added there yet (cooldown_sec alone already prevents
## back-to-back bursts at the current placeholder tuning).
func is_pouncing() -> bool:
	return _pounce_end_ms >= 0


## TK-P2-17 (Kick Stagger, gameplay-engineer): starts a decaying knockback --
## called from characters/abilities/KickAbility.gd's on_confirmed() on the
## STAGGERED player's OWN peer (not the kicker's), once that peer recognizes
## itself as the confirmed kick's `target_id` (see that method's own doc for
## the full "why the target's own client calls this, reusing rpc_confirm's
## existing broadcast" reasoning -- no new RPC). `direction` need not already
## be flat/normalized on entry -- flattened (Y zeroed) and normalized here,
## same guard shape start_pounce_burst() above already uses, so a caller
## passing a raw kicker->target vector (which may carry residual Y from
## slightly different ground heights) can't accidentally scale the knockback
## speed. A degenerate zero-length direction (see
## characters/components/StaggerRules.gd's own direction_away_from() doc for
## when that can happen) safely no-ops to Vector3.ZERO -- the stagger's TIME
## WINDOW still starts (is_staggered() still reports true, for any future
## cosmetic/animation use), it just carries no actual push, rather than
## crashing on normalized().
func start_stagger(direction: Vector3, speed: float, duration_sec: float) -> void:
	var flat_dir: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if flat_dir.length() > 0.0001:
		flat_dir = flat_dir.normalized()
	else:
		flat_dir = Vector3.ZERO
	_stagger_direction = flat_dir
	_stagger_speed = speed
	_stagger_start_ms = Time.get_ticks_msec()
	_stagger_duration_ms = int(duration_sec * 1000.0)


## TK-P2-17: owner-only cancel/reset -- clears the stagger immediately,
## regardless of how far through its decay it was. Not currently called by
## any real gameplay path (Kick Stagger has no owner-predicted "on_rejected"
## undo the way Pounce's cancel_pounce_burst() does -- see
## characters/components/MovementComponent.gd's own `_stagger_start_ms` doc
## above for why there is no legality decision left to reject by the time
## on_confirmed() runs the stagger already happened, authoritatively, on the
## host). Kept available the same "generic stop-whatever's-active-right-now"
## utility reason cancel_pounce_burst() itself documents -- e.g. a future
## role-swap-mid-stagger edge case, or test cleanup, might want it.
func cancel_stagger() -> void:
	_stagger_start_ms = -1
	_stagger_duration_ms = 0
	_stagger_direction = Vector3.ZERO
	_stagger_speed = 0.0


## TK-P2-17: owner-side query for "is a stagger currently in flight" -- same
## plain-getter-over-internal-state shape is_pouncing()/is_jumping() above
## already use (no new ability-shaped API here; this file stays a movement
## primitive). Available for e.g. a future animation/pose flag (staggered
## Tigers could play a stumble animation for the ~0.3s window) -- NOT
## currently consumed for any movement-RESTRICTION purpose anywhere in this
## codebase, which is the point: per this card's hard "no full stun"
## requirement, nothing gates WASD input on this flag. See
## resolve_horizontal_velocity() above for the one place this state actually
## affects movement (an ADDITIVE knockback, never a control override).
func is_staggered() -> bool:
	return _stagger_start_ms >= 0


## TK-P2-17: the knockback-velocity DECISION for THIS tick, extracted out of
## resolve_horizontal_velocity() the same "GUT-testable without a live
## physics tick" reason step_jump()/is_pouncing()'s own resolve method
## already are -- callable directly with a hand-built `now_ms`, no scene tree
## required. Returns Vector3.ZERO when no stagger is active. Delegates the
## actual decay MATH to StaggerRules.decayed_speed() (pure, GUT-tested
## directly with no MovementComponent instance at all) -- this method's own
## job is just the STATEFUL half: turning "how long ago did the stagger
## start" into the `elapsed_ms` that pure function expects, and self-clearing
## (calling cancel_stagger()) once the decay reaches 0, the same self-clearing
## shape resolve_horizontal_velocity()'s own Pounce-expiry branch already has
## for `_pounce_end_ms` -- callers never need to separately notice/cancel a
## stagger that simply ran its course.
func resolve_stagger_knockback(now_ms: int) -> Vector3:
	if _stagger_start_ms < 0:
		return Vector3.ZERO
	var elapsed_ms: int = now_ms - _stagger_start_ms
	var speed: float = StaggerRules.decayed_speed(elapsed_ms, _stagger_duration_ms, _stagger_speed)
	if speed <= 0.0:
		cancel_stagger()
		return Vector3.ZERO
	return _stagger_direction * speed


## TK-P2-06 (Safe Circle, gameplay-engineer): role-gated Safe Circle clamp,
## extracted out of _physics_process the same reason step_jump() above is --
## so GUT can drive it directly with a hand-built role/position pair, with no
## live CharacterBody3D/physics tick required. Confines the Tiger only
## (design ruling point 2: an Outer must be returned UNCHANGED, always free
## to walk in/out) -- delegates the actual boundary math to
## SafeCircleRules.clamp_to_circle() (see that file's own class doc for the
## "why a radial clamp, not a collision shape" reasoning and the exact wall
## behavior). Returns the (possibly-clamped) position for the CALLER to
## assign back to `_body.position`; never touches `_body` itself, which is
## exactly what makes it callable with no scene tree.
func apply_safe_circle_boundary(role: StringName, position: Vector3) -> Vector3:
	if role != RoleRules.TIGER:
		return position
	return SafeCircleRules.clamp_to_circle(position, safe_circle_radius)


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
