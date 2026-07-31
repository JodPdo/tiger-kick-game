extends GutTest
## Unit tests for characters/components/FootstepAudioComponent.gd (TK-P3-12,
## polish-agent).
##
## interval_for_speed() is a pure static, tested directly with plain values
## (no Node/scene tree) -- same pure-statics testing convention every other
## component in this codebase already uses (MovementComponent.compute_
## velocity(), StaggerRules.decayed_speed(), etc).
##
## The _physics_process() wiring tests below DO need a real Player.tscn scene
## tree (same PlayerScene.instantiate() + add_child_autofree() pattern
## tests/test_kick_rules.gd/tests/test_ability_system.gd already establish)
## -- per the TK-P2-33 lesson recorded in CURRENT_PHASE.md (a green suite that
## never observes the actual side effect firing has already let two real bugs
## ship, TK-P2-32 and TK-BUG-P2-01), these assert the OBSERVABLE side effect
## (`FootstepPlayer.playing` actually flips true) rather than just "no
## crash". _physics_process(delta) is called directly with a hand-picked
## delta (same "call the engine-callback method directly with a synthetic
## value" pattern MovementComponent.step_jump()'s own tests already use) --
## a manual call is fine here since the method is plain GDScript, not
## anything Godot-internal-only.

const FootstepAudioComponentScript := preload("res://characters/components/FootstepAudioComponent.gd")
const PlayerScene := preload("res://characters/Player.tscn")


# --- interval_for_speed (pure) -----------------------------------------------

func test_interval_at_reference_speed_returns_reference_interval() -> void:
	var result: float = FootstepAudioComponentScript.interval_for_speed(4.0, 4.0, 0.42, 0.18)
	assert_almost_eq(result, 0.42, 0.0001, "measured speed == reference speed must return the reference interval unscaled")


func test_interval_shortens_for_a_faster_sprinting_speed() -> void:
	var walk_interval: float = FootstepAudioComponentScript.interval_for_speed(4.0, 4.0, 0.42, 0.18)
	var sprint_interval: float = FootstepAudioComponentScript.interval_for_speed(6.0, 4.0, 0.42, 0.18)
	assert_true(sprint_interval < walk_interval,
		"a faster measured speed (sprint, 6.0 m/s) must produce a SHORTER step interval than the reference walk speed (4.0 m/s)")


func test_interval_lengthens_for_a_slower_speed() -> void:
	var walk_interval: float = FootstepAudioComponentScript.interval_for_speed(4.0, 4.0, 0.42, 0.18)
	var slow_interval: float = FootstepAudioComponentScript.interval_for_speed(1.0, 4.0, 0.42, 0.18)
	assert_true(slow_interval > walk_interval,
		"a slower measured speed must produce a LONGER step interval than the reference walk speed")


func test_interval_is_floored_at_min_interval_for_a_very_high_speed() -> void:
	var result: float = FootstepAudioComponentScript.interval_for_speed(100.0, 4.0, 0.42, 0.18)
	assert_eq(result, 0.18, "an unreasonably high speed must never produce an interval below min_interval_sec")


func test_interval_falls_back_to_reference_when_speed_is_zero_or_negative() -> void:
	assert_eq(FootstepAudioComponentScript.interval_for_speed(0.0, 4.0, 0.42, 0.18), 0.42)
	assert_eq(FootstepAudioComponentScript.interval_for_speed(-1.0, 4.0, 0.42, 0.18), 0.42)


func test_interval_falls_back_to_reference_when_reference_speed_is_zero_or_negative() -> void:
	assert_eq(FootstepAudioComponentScript.interval_for_speed(4.0, 0.0, 0.42, 0.18), 0.42,
		"a degenerate (<=0) reference speed must not divide by zero -- fall back to the reference interval unscaled")


# --- _physics_process() wiring (needs a real Player.tscn scene tree) --------

## Naming contract (TK-BUG-P1-01, node.name == str(peer_id)): set BEFORE
## entering the tree, same pattern every other Player.tscn-touching test file
## in this codebase already uses (e.g. tests/test_kick_rules.gd's own
## _spawn_kick_candidate()) -- Player._enter_tree() derives multiplayer
## authority from int(name) and logs an ERROR for a non-numeric name, which
## GUT's error tracker correctly treats as a test failure even if every
## assertion below it still passes.
func _spawn_player() -> CharacterBody3D:
	var player: CharacterBody3D = PlayerScene.instantiate()
	player.name = "1"
	add_child_autofree(player)
	return player


func test_first_tick_never_plays_before_a_prior_position_sample_exists() -> void:
	var player: CharacterBody3D = _spawn_player()
	var footstep_component: Node = player.get_node("FootstepAudioComponent")
	var footstep_player: AudioStreamPlayer3D = player.get_node("FootstepPlayer")

	footstep_component._physics_process(0.1)

	assert_false(footstep_player.playing,
		"the very first _physics_process() call only establishes the baseline position sample -- there is no prior tick to diff against yet, so it must not play")


func test_footstep_plays_once_horizontal_movement_exceeds_the_speed_gate() -> void:
	var player: CharacterBody3D = _spawn_player()
	var footstep_component: Node = player.get_node("FootstepAudioComponent")
	var footstep_player: AudioStreamPlayer3D = player.get_node("FootstepPlayer")

	footstep_component._physics_process(0.1) # baseline sample, see test above

	# 1.0m over the next 0.1s tick = 10 m/s -- comfortably over
	# min_horizontal_speed_mps (0.3 m/s default), same as a real moving Player
	# (owner via move_and_slide(), or a remote peer via MultiplayerSynchronizer
	# overwriting `position` -- see this component's own class doc for why
	# reading `position` this way is deliberately peer-agnostic).
	player.position += Vector3(1.0, 0.0, 0.0)
	footstep_component._physics_process(0.1)

	assert_true(footstep_player.playing,
		"sufficient measured horizontal speed must play a footstep -- _time_since_step starts at the RESET sentinel, so the very first qualifying tick after movement begins must fire immediately")


func test_footstep_does_not_replay_immediately_on_the_very_next_tick() -> void:
	var player: CharacterBody3D = _spawn_player()
	var footstep_component: Node = player.get_node("FootstepAudioComponent")
	var footstep_player: AudioStreamPlayer3D = player.get_node("FootstepPlayer")

	footstep_component._physics_process(0.1) # baseline
	player.position += Vector3(1.0, 0.0, 0.0)
	footstep_component._physics_process(0.1) # first step fires
	assert_true(footstep_player.playing, "sanity: first step must have fired")

	footstep_player.stop() # reset the observable flag so the next assert is meaningful
	player.position += Vector3(1.0, 0.0, 0.0) # keep moving at the same speed
	footstep_component._physics_process(0.1)

	assert_false(footstep_player.playing,
		"a step must not immediately re-fire on the very next tick -- footstep_reference_interval_sec (0.42s default) must elapse first")


func test_footstep_does_not_play_while_stationary() -> void:
	var player: CharacterBody3D = _spawn_player()
	var footstep_component: Node = player.get_node("FootstepAudioComponent")
	var footstep_player: AudioStreamPlayer3D = player.get_node("FootstepPlayer")

	footstep_component._physics_process(0.1) # baseline, no movement
	footstep_component._physics_process(0.1) # still no movement

	assert_false(footstep_player.playing, "zero horizontal movement must never trigger a footstep")


func test_footstep_does_not_play_while_airborne_even_when_moving_horizontally() -> void:
	var player: CharacterBody3D = _spawn_player()
	player.is_jumping = true # TK-P2-10's synced substitute for is_on_floor(), see this component's own class doc
	var footstep_component: Node = player.get_node("FootstepAudioComponent")
	var footstep_player: AudioStreamPlayer3D = player.get_node("FootstepPlayer")

	footstep_component._physics_process(0.1) # baseline
	player.position += Vector3(1.0, 0.0, 0.0)
	footstep_component._physics_process(0.1)

	assert_false(footstep_player.playing,
		"is_jumping == true (TK-P2-10's synced airborne substitute) must suppress footsteps even with qualifying horizontal movement")


func test_footstep_player_node_is_routed_to_the_sfx_bus() -> void:
	var player: CharacterBody3D = _spawn_player()
	var footstep_player: AudioStreamPlayer3D = player.get_node("FootstepPlayer")
	assert_eq(footstep_player.bus, "SFX",
		"footstep audio must route through the existing SFX bus (ConfigManager/TK-PX-05), not a new/second AudioBus")
