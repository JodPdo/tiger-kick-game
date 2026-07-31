extends GutTest
## Unit tests for characters/abilities/PounceRules.gd (TK-P2-18), the
## owner-side cooldown prediction on characters/abilities/PounceAbility.gd,
## and the node-independent burst-override seam on
## characters/components/MovementComponent.gd (start_pounce_burst() /
## cancel_pounce_burst() / resolve_horizontal_velocity() / is_pouncing()).
##
## Only node-independent logic is covered here (design doc section 3
## testability note, same pattern as tests/test_kick_rules.gd /
## tests/test_jump_rules.gd): PounceRules is a pure static helper, and
## PounceAbility.can_activate()/on_rejected() touch nothing but their own
## member state + a null-guarded MovementComponent reference -- no scene
## tree, no multiplayer context, so a bare PounceAbility.new() (never added
## to a tree, @onready members left unresolved) is safe to exercise
## directly, same as tests/test_kick_rules.gd's bare KickAbility instances.
## host_validate()/host_apply()/on_confirmed()/on_activate_local() DO need a
## live scene tree + multiplayer context (sibling MovementComponent/
## CameraRig, GameManager, multiplayer.is_server()) and are NOT covered here
## -- see this card's handoff note for the manual 2-instance pass that
## exercises those instead.

const PounceRulesScript := preload("res://characters/abilities/PounceRules.gd")
const PounceAbilityScript := preload("res://characters/abilities/PounceAbility.gd")
const MovementComponentScript := preload("res://characters/components/MovementComponent.gd")


# --- PounceRules.can_fire (pure cooldown ledger) ----------------------------

func test_can_fire_true_when_never_fired_before() -> void:
	assert_true(PounceRulesScript.can_fire(-1, 2.0, 1000))


func test_can_fire_false_immediately_after_firing() -> void:
	assert_false(PounceRulesScript.can_fire(1000, 2.0, 1500), "500ms after a 2.0s-cooldown fire must still be on cooldown")


func test_can_fire_true_once_cooldown_has_fully_elapsed() -> void:
	assert_true(PounceRulesScript.can_fire(1000, 2.0, 3000), "exactly cooldown_sec later should be allowed again (inclusive)")


func test_can_fire_true_well_after_cooldown_elapsed() -> void:
	assert_true(PounceRulesScript.can_fire(1000, 2.0, 9000))


func test_can_fire_zero_cooldown_always_allows() -> void:
	assert_true(PounceRulesScript.can_fire(1000, 0.0, 1000), "cooldown_sec == 0.0 must never block a fire")


# --- PounceAbility owner-side cooldown prediction (can_activate/on_rejected) --

var _pounce: PounceAbility
var _movement: Node


func after_each() -> void:
	if is_instance_valid(_pounce):
		_pounce.free()
		_pounce = null
	if is_instance_valid(_movement):
		_movement.free()
		_movement = null


func test_pounce_ability_defaults() -> void:
	_pounce = PounceAbilityScript.new()
	assert_eq(_pounce.ability_id, &"pounce", "PounceAbility must set its own ability_id (overridden in _init, not the base default)")
	assert_eq(_pounce.input_action, &"pounce")
	assert_eq(_pounce.cooldown_sec, 2.0)
	assert_eq(_pounce.pounce_speed_mps, 8.0, "Game_Balance.md section 4 Pounce burst speed")
	assert_eq(_pounce.pounce_duration_sec, 0.35)
	assert_eq(_pounce.resolution, Ability.Resolution.HOST_AUTHORITATIVE, "Pounce must stay HOST_AUTHORITATIVE (design doc section 3: Kick, Jump-Kick, Tag, Pounce -- HOST)")


func test_pounce_ability_is_a_tiger_ability() -> void:
	_pounce = PounceAbilityScript.new()
	assert_true(_pounce is TigerAbility, "PounceAbility must extend TigerAbility, per AbilityCatalog's Tiger registration")


func test_can_activate_true_before_ever_firing() -> void:
	_pounce = PounceAbilityScript.new()
	assert_true(_pounce.can_activate({}))


func test_can_activate_false_immediately_after_a_predicted_fire() -> void:
	_pounce = PounceAbilityScript.new()
	_pounce._owner_last_fire_ms = Time.get_ticks_msec()
	assert_false(_pounce.can_activate({}), "owner-predicted cooldown must block an immediate second activation")


func test_on_rejected_clears_the_owner_predicted_cooldown() -> void:
	_pounce = PounceAbilityScript.new()
	_pounce._owner_last_fire_ms = Time.get_ticks_msec()
	assert_false(_pounce.can_activate({}), "sanity: cooldown should be active before the rejection")
	_pounce.on_rejected("cooldown")
	assert_true(_pounce.can_activate({}), "on_rejected must roll back the owner-predicted cooldown -- the burst never actually landed")


func test_on_rejected_does_not_crash_with_no_scene_tree() -> void:
	# Regression for the _movement null-guard in on_rejected() -- a bare
	# instance never entered a tree, so @onready _movement is unresolved
	# (null). on_rejected() must still roll back the cooldown without
	# crashing on a null MovementComponent reference.
	_pounce = PounceAbilityScript.new()
	_pounce._owner_last_fire_ms = Time.get_ticks_msec()
	_pounce.on_rejected("sequence_active")
	assert_true(_pounce.can_activate({}))


# --- MovementComponent Pounce burst-override seam ---------------------------
# start_pounce_burst() / cancel_pounce_burst() / resolve_horizontal_velocity()
# / is_pouncing() are extracted out of _physics_process the same
# "GUT-testable without a live physics tick" reason step_jump() already is
# (tests/test_jump_rules.gd) -- a bare MovementComponent.new() (never added
# to a tree, @onready _body/_camera_rig left unresolved) is safe here because
# none of these methods touch _body/_camera_rig, only the component's own
# _pounce_end_ms/_pounce_velocity state. Cleaned up by the single after_each()
# above (shared with the PounceAbility tests).

func test_is_pouncing_false_by_default() -> void:
	_movement = MovementComponentScript.new()
	assert_false(_movement.is_pouncing(), "a freshly created MovementComponent must not report is_pouncing before any burst has fired")


func test_resolve_horizontal_velocity_returns_wasd_when_no_burst_active() -> void:
	_movement = MovementComponentScript.new()
	var wasd: Vector3 = Vector3(1.0, 0.0, 2.0)
	var result: Vector3 = _movement.resolve_horizontal_velocity(1000, wasd)
	assert_eq(result, wasd, "with no burst active, WASD velocity must pass through unchanged")


func test_start_pounce_burst_overrides_wasd_while_active() -> void:
	_movement = MovementComponentScript.new()
	_movement.start_pounce_burst(Vector3(1.0, 0.0, 0.0), 8.0, 0.35)
	assert_true(_movement.is_pouncing(), "is_pouncing must be true immediately after start_pounce_burst")

	var wasd: Vector3 = Vector3(-5.0, 0.0, -5.0) # deliberately different from the burst direction
	var now: int = Time.get_ticks_msec() # burst just started, still well inside duration
	var result: Vector3 = _movement.resolve_horizontal_velocity(now, wasd)
	assert_eq(result, Vector3(8.0, 0.0, 0.0), "an active burst must OVERRIDE the WASD result outright, not blend with it")


func test_start_pounce_burst_normalizes_direction() -> void:
	_movement = MovementComponentScript.new()
	# A non-unit, diagonal direction (e.g. straight from camera_relative_dir()
	# on diagonal input) must not scale the burst speed above pounce_speed_mps.
	_movement.start_pounce_burst(Vector3(2.0, 0.0, 2.0), 8.0, 0.35)
	var result: Vector3 = _movement.resolve_horizontal_velocity(Time.get_ticks_msec(), Vector3.ZERO)
	assert_almost_eq(result.length(), 8.0, 0.001, "burst speed must be exactly pounce_speed_mps regardless of the input direction's original magnitude")


func test_start_pounce_burst_flattens_vertical_component() -> void:
	_movement = MovementComponentScript.new()
	_movement.start_pounce_burst(Vector3(1.0, 5.0, 0.0), 8.0, 0.35)
	var result: Vector3 = _movement.resolve_horizontal_velocity(Time.get_ticks_msec(), Vector3.ZERO)
	assert_eq(result.y, 0.0, "the burst must never carry a vertical component -- gravity/step_jump own the Y axis")


func test_start_pounce_burst_degenerate_zero_direction_is_safe() -> void:
	_movement = MovementComponentScript.new()
	_movement.start_pounce_burst(Vector3.ZERO, 8.0, 0.35)
	var result: Vector3 = _movement.resolve_horizontal_velocity(Time.get_ticks_msec(), Vector3.ZERO)
	assert_eq(result, Vector3.ZERO, "a zero-length direction must not crash (normalized()) and must yield zero velocity")


func test_resolve_horizontal_velocity_expires_burst_after_duration() -> void:
	_movement = MovementComponentScript.new()
	var start_ms: int = 1000
	_movement.start_pounce_burst(Vector3(1.0, 0.0, 0.0), 8.0, 0.35)
	# Force a deterministic start clock so the expiry check below does not
	# depend on real wall-clock timing.
	_movement._pounce_end_ms = start_ms + int(0.35 * 1000.0)

	var wasd: Vector3 = Vector3(2.0, 0.0, 0.0)
	var still_active: Vector3 = _movement.resolve_horizontal_velocity(start_ms + 100, wasd)
	assert_eq(still_active, Vector3(8.0, 0.0, 0.0), "burst must still override 100ms into a 350ms duration")

	var expired: Vector3 = _movement.resolve_horizontal_velocity(start_ms + 350, wasd)
	assert_eq(expired, wasd, "once now_ms reaches the burst's end time, WASD must take back over")
	assert_false(_movement.is_pouncing(), "expiry must clear is_pouncing (self-clearing, same shape step_jump's landing-clear has)")


func test_cancel_pounce_burst_stops_it_immediately() -> void:
	_movement = MovementComponentScript.new()
	_movement.start_pounce_burst(Vector3(1.0, 0.0, 0.0), 8.0, 0.35)
	assert_true(_movement.is_pouncing())

	_movement.cancel_pounce_burst()
	assert_false(_movement.is_pouncing(), "cancel_pounce_burst must clear is_pouncing immediately")

	var wasd: Vector3 = Vector3(3.0, 0.0, 3.0)
	var result: Vector3 = _movement.resolve_horizontal_velocity(Time.get_ticks_msec(), wasd)
	assert_eq(result, wasd, "after cancel, WASD must take back over on the very next resolve call")
