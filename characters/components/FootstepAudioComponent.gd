extends Node
## FootstepAudioComponent (TK-P3-12, polish-agent) -- MINIMAL Phase 3 gameplay
## audio gate (see this card's own notes in `_backlog.json` /
## CURRENT_PHASE.md "Next -- Phase 3" for why this exists ahead of the full
## Phase 4 audio system, TK-P4-02: the Tiger's hunt-not-chase design leans on
## HEARING an approaching Outer, so a playtest with zero gameplay audio would
## measure a different, quieter game than intended).
##
## WHAT THIS DOES: plays a one-shot footstep sound on an interval while the
## Player this is attached to is moving horizontally and not airborne. Client-
## local/cosmetic only, same "cosmetic, a cheating client can only ever distort
## their own screen" class every other owner-side effect in this codebase
## already documents (see characters/components/MovementComponent.gd's own
## Pounce/Safe-Circle/Stagger docs for the precedent) -- no RPC, no
## host-authority surface added.
##
## WHY POSITION-DELTA, NOT `_body.velocity`/`is_on_floor()` (read this before
## "fixing" it to use those instead): this component must produce the SAME
## audible result on every peer, not just the owning one -- design doc/card
## requirement "must trigger off the same synced movement state on every
## client... so all peers hear all players' footsteps, not just their own".
## MovementComponent.gd's own class doc is explicit that `_body.velocity` and
## `_body.is_on_floor()` are only ever LIVE/accurate on the owning peer's own
## copy (non-authority Players never call move_and_slide(), see that file's
## _physics_process() doc) -- a straight port of "velocity.length() > 0 and
## is_on_floor()" would therefore work perfectly for the owner and silently
## never fire for every OTHER peer watching that same Player run past them.
## `_body.position`, by contrast, IS kept live on every peer -- either by the
## owner's own physics (move_and_slide()) or by Player.tscn's
## MultiplayerSynchronizer (channel A, ON_CHANGE, see that scene's
## SceneReplicationConfig) overwriting it on every remote peer -- so measuring
## this tick's horizontal position DELTA against last tick's is a source of
## "is this Player currently moving" that is honestly identical in shape on
## every peer, owner included (the owner just happens to be the one actually
## producing the position change; the math is the same either way).
##
## AIRBORNE SUBSTITUTE: same reasoning rules out `is_on_floor()` directly, but
## `_body.is_jumping` (MovementComponent's own `_is_jumping`, mirrored onto the
## Player body every tick and replicated via the same MultiplayerSynchronizer,
## see MovementComponent.gd's own `_is_jumping` doc) IS synced identically on
## every peer -- used here as the "don't play footsteps while jumping" gate.
## Known, accepted scope gap (same one MovementComponent.is_jumping()'s own
## doc already flags for Jump-Kick): a Player who walks off a ledge (falling,
## never jumped) is not caught by this flag and could still get a stray
## footstep mid-fall -- acceptable for this minimal gate card, not a Phase 3
## Exit Gate blocker.
##
## CADENCE (nice-to-have per the card, not required for DoD): interval_
## for_speed() below scales the step interval inversely with measured
## horizontal speed, so a sprinting Outer (6.0 m/s) naturally taps faster than
## a walking one (4.0 m/s) or a capped-walk-speed Tiger (4.0 m/s) -- one sound
## asset, no separate sprint-cadence bookkeeping/synced flag needed. Pure,
## GUT-testable static function (tests/test_footstep_audio.gd), same
## "pure statics + thin _physics_process shell" split MovementComponent.gd's
## own step_jump()/apply_safe_circle_boundary() already establish.
##
## NODE WIRING: expects a sibling AudioStreamPlayer3D named "FootstepPlayer"
## under the same parent Player (see characters/Player.tscn) -- looked up via
## get_node_or_null so a Player scene instantiated without one (e.g. a future
## test double) degrades to a silent no-op rather than crashing.
##
## ASSET SOURCING (Character_Art_Bible.md section 9 -- audio/art assets are
## human-supplied, agents do not generate final art/audio): FootstepPlayer's
## stream in characters/Player.tscn preloads
## res://audio/sfx/footstep_walk.wav, currently a tiny placeholder generated
## tone (NOT a real recording) so the whole pipeline is wired and audible
## end-to-end before the real CC0 asset lands. Drop a real footstep sound at
## that EXACT path/filename (see this card's handoff note for the full asset
## spec) and nothing here needs to change.

## Reference speed (m/s) footstep_reference_interval_sec is tuned for --
## Game_Balance.md's Outer walk speed (4.0 m/s, MovementComponent.
## outer_walk_speed). Design-owned-adjacent tunable (audio feel, not gameplay
## balance) -- @export per CLAUDE.md's "expose design-owned tunables" rule,
## same as every other tunable in this codebase.
@export var footstep_reference_speed_mps: float = 4.0

## Step interval (seconds) AT footstep_reference_speed_mps -- a placeholder
## "readable, not floaty" feel value, same status every other un-locked
## placeholder tunable in this codebase carries (see e.g. MovementComponent.
## jump_speed's own doc) pending a designer/producer feel-pass.
@export var footstep_reference_interval_sec: float = 0.42

## Below this measured horizontal speed (m/s), a Player is considered
## stationary -- guards tiny per-tick position jitter (e.g. network
## resync noise on a remote peer) from ever being read as "walking".
@export var min_horizontal_speed_mps: float = 0.3

## Floor on the scaled interval (see interval_for_speed() below) so a very
## fast burst (e.g. mid-Pounce) can't degenerate into a footstep spam buzz.
@export var min_step_interval_sec: float = 0.18

## Sentinel _time_since_step value written the instant a Player stops
## moving/goes airborne -- guarantees the FIRST footstep after movement
## resumes plays immediately (no up-to-footstep_reference_interval_sec
## delay), regardless of what interval the resumed speed computes to.
const _RESET_TIME_SINCE_STEP: float = 999.0

@onready var _body: CharacterBody3D = get_parent() as CharacterBody3D
@onready var _footstep_player: AudioStreamPlayer3D = get_parent().get_node_or_null("FootstepPlayer") as AudioStreamPlayer3D

var _has_last_position: bool = false
var _last_position: Vector3 = Vector3.ZERO
var _time_since_step: float = _RESET_TIME_SINCE_STEP


## Runs on EVERY peer's copy of a Player (unlike MovementComponent's own
## _physics_process(), this is deliberately NOT gated on
## is_multiplayer_authority() -- see this file's class doc for why: every
## peer must hear every OTHER Player's footsteps too, not just their own).
func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return

	var current_position: Vector3 = _body.position
	if not _has_last_position:
		# First tick ever seen -- no prior sample to diff against yet.
		_last_position = current_position
		_has_last_position = true
		return

	var horizontal_delta: Vector3 = Vector3(
		current_position.x - _last_position.x, 0.0, current_position.z - _last_position.z
	)
	_last_position = current_position
	var horizontal_speed_mps: float = horizontal_delta.length() / delta

	_time_since_step += delta

	var is_moving: bool = horizontal_speed_mps > min_horizontal_speed_mps
	var is_airborne: bool = _body.is_jumping

	if not is_moving or is_airborne:
		_time_since_step = _RESET_TIME_SINCE_STEP
		return

	var interval_sec: float = interval_for_speed(
		horizontal_speed_mps, footstep_reference_speed_mps, footstep_reference_interval_sec, min_step_interval_sec
	)
	if _time_since_step >= interval_sec:
		_time_since_step = 0.0
		_play_footstep()


func _play_footstep() -> void:
	if _footstep_player == null:
		return
	# Headless-CI safety (real risk this card's DoD explicitly calls out to
	# check): a scene with the node present but no stream assigned (or an
	# import that failed to produce one) must degrade silently, not throw a
	# SCRIPT ERROR under --headless --import/GUT.
	if _footstep_player.stream == null:
		return
	_footstep_player.play()


## Pure, node-independent (GUT-testable, tests/test_footstep_audio.gd): the
## step-interval DECISION for a given measured horizontal speed. Scales
## inversely with speed around reference_speed_mps/reference_interval_sec
## (faster movement -> shorter interval -> quicker cadence), floored at
## min_interval_sec so an unreasonably high speed can't produce a
## near-zero/spammy interval. Degenerate inputs (speed or reference speed
## <= 0) fall back to reference_interval_sec unscaled rather than dividing
## by zero.
static func interval_for_speed(
	speed_mps: float, reference_speed_mps: float, reference_interval_sec: float, min_interval_sec: float
) -> float:
	if speed_mps <= 0.0 or reference_speed_mps <= 0.0:
		return reference_interval_sec
	var scaled: float = reference_interval_sec * (reference_speed_mps / speed_mps)
	return max(scaled, min_interval_sec)
