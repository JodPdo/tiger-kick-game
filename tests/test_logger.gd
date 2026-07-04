extends GutTest
## Unit tests for managers/Logger.gd -- level filtering & line formatting.
##
## Covers TK-PX-01 (Logger autoload). Only the pure, node-independent logic
## is tested here (should_log / format_line / level_to_string). No disk I/O
## is exercised -- file writing is instance/OS-dependent and out of scope
## for GUT per the card's constraints; the instance methods are written to
## never crash if the log file can't be opened (see Logger._open_log_file).

const LoggerScript := preload("res://managers/Logger.gd")


# --- should_log: level filtering ----------------------------------------------

func test_debug_dropped_when_min_level_is_info() -> void:
	assert_false(
		LoggerScript.should_log(LoggerScript.Level.INFO, LoggerScript.Level.DEBUG),
		"DEBUG message must be dropped when the minimum level is INFO")


func test_debug_dropped_when_min_level_is_warn() -> void:
	assert_false(
		LoggerScript.should_log(LoggerScript.Level.WARN, LoggerScript.Level.DEBUG),
		"DEBUG message must be dropped when the minimum level is WARN")


func test_debug_dropped_when_min_level_is_error() -> void:
	assert_false(
		LoggerScript.should_log(LoggerScript.Level.ERROR, LoggerScript.Level.DEBUG),
		"DEBUG message must be dropped when the minimum level is ERROR")


func test_debug_passes_when_min_level_is_debug() -> void:
	assert_true(
		LoggerScript.should_log(LoggerScript.Level.DEBUG, LoggerScript.Level.DEBUG),
		"DEBUG message must pass when the minimum level is DEBUG")


func test_info_dropped_when_min_level_is_warn() -> void:
	assert_false(
		LoggerScript.should_log(LoggerScript.Level.WARN, LoggerScript.Level.INFO),
		"INFO message must be dropped when the minimum level is WARN")


func test_warn_passes_when_min_level_is_warn() -> void:
	assert_true(
		LoggerScript.should_log(LoggerScript.Level.WARN, LoggerScript.Level.WARN),
		"WARN message must pass when the minimum level is WARN")


func test_error_always_passes() -> void:
	# ERROR must pass regardless of the current minimum level.
	assert_true(LoggerScript.should_log(LoggerScript.Level.DEBUG, LoggerScript.Level.ERROR))
	assert_true(LoggerScript.should_log(LoggerScript.Level.INFO, LoggerScript.Level.ERROR))
	assert_true(LoggerScript.should_log(LoggerScript.Level.WARN, LoggerScript.Level.ERROR))
	assert_true(LoggerScript.should_log(LoggerScript.Level.ERROR, LoggerScript.Level.ERROR))


# --- level_to_string -----------------------------------------------------------

func test_level_to_string_names() -> void:
	assert_eq(LoggerScript.level_to_string(LoggerScript.Level.DEBUG), "DEBUG")
	assert_eq(LoggerScript.level_to_string(LoggerScript.Level.INFO), "INFO")
	assert_eq(LoggerScript.level_to_string(LoggerScript.Level.WARN), "WARN")
	assert_eq(LoggerScript.level_to_string(LoggerScript.Level.ERROR), "ERROR")


# --- format_line: output shape --------------------------------------------------

func test_format_line_shape() -> void:
	var line: String = LoggerScript.format_line(
		LoggerScript.Level.INFO, "hello world", "2026-07-04T12:00:00")
	assert_eq(line, "[2026-07-04T12:00:00][INFO] hello world")


func test_format_line_uses_correct_level_tag() -> void:
	var line: String = LoggerScript.format_line(
		LoggerScript.Level.ERROR, "boom", "2026-01-01T00:00:00")
	assert_true(line.begins_with("[2026-01-01T00:00:00][ERROR]"),
		"format_line must place the timestamp then the level tag first")
	assert_true(line.ends_with("boom"),
		"format_line must place the message last")


func test_format_line_empty_message() -> void:
	var line: String = LoggerScript.format_line(
		LoggerScript.Level.WARN, "", "2026-07-04T12:00:00")
	assert_eq(line, "[2026-07-04T12:00:00][WARN] ",
		"empty message still produces a well-formed line (no crash)")
