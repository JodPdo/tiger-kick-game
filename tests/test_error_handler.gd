extends GutTest
## Unit tests for managers/ErrorHandler.gd -- pure formatting & report_if
## boolean semantics.
##
## Covers TK-PX-06 (centralized error handling). Only the pure,
## node-independent logic is tested here (format_error / should_report).
## No tree/disk/GameLog access is exercised -- `report()`/`report_if()`
## call into the GameLog autoload singleton as a side effect, which is out
## of scope for these node-independent GUT tests (mirrors the approach in
## tests/test_logger.gd for GameLog itself).

const ErrorHandlerScript := preload("res://managers/ErrorHandler.gd")


# --- format_error: output shape ------------------------------------------------

func test_format_error_shape_without_err_code() -> void:
	var line: String = ErrorHandlerScript.format_error("NetworkManager.join", "empty address")
	assert_eq(line, "[NetworkManager.join] empty address")


func test_format_error_omits_code_when_ok() -> void:
	var line: String = ErrorHandlerScript.format_error("Foo.bar", "something", OK)
	assert_eq(line, "[Foo.bar] something",
		"OK (0) must not be appended as an error code")


func test_format_error_appends_err_code_when_non_ok() -> void:
	var line: String = ErrorHandlerScript.format_error(
		"NetworkManager.join", "invalid port", ERR_INVALID_PARAMETER)
	assert_eq(line, "[NetworkManager.join] invalid port (error code %d)" % ERR_INVALID_PARAMETER)


func test_format_error_appends_different_err_codes() -> void:
	var line: String = ErrorHandlerScript.format_error("System.load", "missing file", ERR_FILE_NOT_FOUND)
	assert_eq(line, "[System.load] missing file (error code %d)" % ERR_FILE_NOT_FOUND)


func test_format_error_empty_message() -> void:
	var line: String = ErrorHandlerScript.format_error("Ctx", "")
	assert_eq(line, "[Ctx] ", "empty message still produces a well-formed line (no crash)")


func test_format_error_places_context_first_and_code_last() -> void:
	var line: String = ErrorHandlerScript.format_error("Ctx", "msg", ERR_UNAVAILABLE)
	assert_true(line.begins_with("[Ctx] msg"),
		"format_error must place context then message first")
	assert_true(line.ends_with("(error code %d)" % ERR_UNAVAILABLE),
		"format_error must append the error code last")


# --- should_report: report_if boolean semantics --------------------------------

func test_should_report_true_when_condition_failed() -> void:
	assert_true(ErrorHandlerScript.should_report(true),
		"should_report must mirror a failed condition (true) so callers can early-return")


func test_should_report_false_when_condition_ok() -> void:
	assert_false(ErrorHandlerScript.should_report(false),
		"should_report must mirror a passing condition (false) -- no error, no early-return")
