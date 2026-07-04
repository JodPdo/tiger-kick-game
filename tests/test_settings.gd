extends GutTest
## Unit tests for ui/SettingsMenu.gd -- pure, node-independent helper logic
## only (TK-PX-05).
##
## Covers: resolution string <-> Vector2i conversion, max-fps clamping, the
## volume-slider <-> dB mapping, rebind-key -> InputMap action-name mapping,
## and the ui_ action filter used to decide whether to show the Phase 1
## controls placeholder. None of these touch DisplayServer/AudioServer/
## InputMap/the scene tree -- they operate on plain values/arrays passed in,
## so GUT can run them headless. Live engine reflection (window mode/vsync/
## bus volume) and the actual rebind-capture UI flow are out of scope for GUT
## (per the card) and are exercised manually / by the producer's combined
## verification pass.

const SettingsMenuScript := preload("res://ui/SettingsMenu.gd")


# --- resolution_to_size -------------------------------------------------------

func test_resolution_to_size_parses_valid_string() -> void:
	var result: Vector2i = SettingsMenuScript.resolution_to_size("1920x1080")
	assert_eq(result, Vector2i(1920, 1080))


func test_resolution_to_size_case_insensitive() -> void:
	var result: Vector2i = SettingsMenuScript.resolution_to_size("1920X1080")
	assert_eq(result, Vector2i(1920, 1080))


func test_resolution_to_size_missing_separator_returns_zero() -> void:
	var result: Vector2i = SettingsMenuScript.resolution_to_size("19201080")
	assert_eq(result, Vector2i.ZERO)


func test_resolution_to_size_non_numeric_part_returns_zero() -> void:
	var result: Vector2i = SettingsMenuScript.resolution_to_size("abcx1080")
	assert_eq(result, Vector2i.ZERO)


func test_resolution_to_size_empty_string_returns_zero() -> void:
	var result: Vector2i = SettingsMenuScript.resolution_to_size("")
	assert_eq(result, Vector2i.ZERO)


func test_resolution_to_size_zero_dimension_returns_zero() -> void:
	var result: Vector2i = SettingsMenuScript.resolution_to_size("0x1080")
	assert_eq(result, Vector2i.ZERO)


func test_resolution_to_size_negative_dimension_returns_zero() -> void:
	var result: Vector2i = SettingsMenuScript.resolution_to_size("-100x1080")
	assert_eq(result, Vector2i.ZERO)


# --- size_to_resolution_string (inverse) --------------------------------------

func test_size_to_resolution_string_formats_correctly() -> void:
	var result: String = SettingsMenuScript.size_to_resolution_string(Vector2i(2560, 1440))
	assert_eq(result, "2560x1440")


func test_resolution_round_trip() -> void:
	var text: String = "1600x900"
	var size: Vector2i = SettingsMenuScript.resolution_to_size(text)
	var back: String = SettingsMenuScript.size_to_resolution_string(size)
	assert_eq(back, text)


# --- clamp_max_fps -------------------------------------------------------------

func test_clamp_max_fps_zero_stays_zero() -> void:
	assert_eq(SettingsMenuScript.clamp_max_fps(0), 0)


func test_clamp_max_fps_negative_becomes_zero() -> void:
	assert_eq(SettingsMenuScript.clamp_max_fps(-30), 0)


func test_clamp_max_fps_typical_value_unchanged() -> void:
	assert_eq(SettingsMenuScript.clamp_max_fps(144), 144)


func test_clamp_max_fps_caps_at_1000() -> void:
	assert_eq(SettingsMenuScript.clamp_max_fps(5000), 1000)


func test_clamp_max_fps_at_cap_boundary_unchanged() -> void:
	assert_eq(SettingsMenuScript.clamp_max_fps(1000), 1000)


# --- volume_to_db / db_to_volume -----------------------------------------------

func test_volume_to_db_full_volume_is_zero_db() -> void:
	var db: float = SettingsMenuScript.volume_to_db(1.0)
	assert_almost_eq(db, 0.0, 0.001)


func test_volume_to_db_zero_volume_floors_at_min_db() -> void:
	var db: float = SettingsMenuScript.volume_to_db(0.0)
	assert_eq(db, SettingsMenuScript.MIN_VOLUME_DB)


func test_volume_to_db_never_returns_negative_infinity() -> void:
	var db: float = SettingsMenuScript.volume_to_db(0.0)
	assert_false(is_inf(db), "volume_to_db must never leak -inf into AudioServer")


func test_volume_to_db_half_volume_is_negative() -> void:
	var db: float = SettingsMenuScript.volume_to_db(0.5)
	assert_true(db < 0.0, "half volume should be a negative dB attenuation")


func test_volume_to_db_clamps_out_of_range_input() -> void:
	var over: float = SettingsMenuScript.volume_to_db(2.0)
	var under: float = SettingsMenuScript.volume_to_db(-1.0)
	assert_almost_eq(over, 0.0, 0.001)
	assert_eq(under, SettingsMenuScript.MIN_VOLUME_DB)


func test_db_to_volume_zero_db_is_full_volume() -> void:
	var linear: float = SettingsMenuScript.db_to_volume(0.0)
	assert_almost_eq(linear, 1.0, 0.001)


func test_db_to_volume_at_or_below_floor_is_zero() -> void:
	var linear: float = SettingsMenuScript.db_to_volume(SettingsMenuScript.MIN_VOLUME_DB)
	assert_eq(linear, 0.0)


func test_volume_db_round_trip_mid_range() -> void:
	var original: float = 0.6
	var db: float = SettingsMenuScript.volume_to_db(original)
	var back: float = SettingsMenuScript.db_to_volume(db)
	assert_almost_eq(back, original, 0.01)


# --- rebind_key_to_action_name -------------------------------------------------

func test_rebind_key_to_action_name_strips_prefix() -> void:
	assert_eq(SettingsMenuScript.rebind_key_to_action_name("rebind_move_forward"), "move_forward")


func test_rebind_key_to_action_name_kick() -> void:
	assert_eq(SettingsMenuScript.rebind_key_to_action_name("rebind_kick"), "kick")


func test_rebind_key_to_action_name_without_prefix_unchanged() -> void:
	assert_eq(SettingsMenuScript.rebind_key_to_action_name("jump"), "jump")


# --- filter_custom_input_actions ------------------------------------------------

func test_filter_custom_input_actions_removes_ui_prefixed() -> void:
	var actions: Array = ["ui_accept", "ui_cancel", "ui_up"]
	var result: Array = SettingsMenuScript.filter_custom_input_actions(actions)
	assert_eq(result, [])


func test_filter_custom_input_actions_keeps_gameplay_actions() -> void:
	var actions: Array = ["ui_accept", "move_forward", "kick", "tag"]
	var result: Array = SettingsMenuScript.filter_custom_input_actions(actions)
	assert_eq(result, ["move_forward", "kick", "tag"])


func test_filter_custom_input_actions_empty_input_returns_empty() -> void:
	var result: Array = SettingsMenuScript.filter_custom_input_actions([])
	assert_eq(result, [])


func test_filter_custom_input_actions_all_custom_no_filtering_needed() -> void:
	var actions: Array = ["move_forward", "move_back"]
	var result: Array = SettingsMenuScript.filter_custom_input_actions(actions)
	assert_eq(result, actions)
