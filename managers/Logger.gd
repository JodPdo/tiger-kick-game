extends Node
## GameLog (autoload singleton) -- registered in project.godot as GameLog.
##
## NOTE: registered as autoload **GameLog** -- do NOT name the autoload
## "Logger": it collides with Godot's built-in `Logger` engine class and
## breaks GUT's error_tracker (addons/gut/error_tracker.gd extends Logger +
## OS.add_logger; a "Logger" autoload silently shadows it, causing
## `rp_logger is null` and leaked objects during GUT runs). The script file
## stays named Logger.gd; call the singleton via
## GameLog.info()/warn()/error()/debug().
##
## Centralized logging with levels (DEBUG/INFO/WARN/ERROR) and a settable
## minimum level threshold. Every emitted line is printed to the console AND
## appended to a per-session file under `user://logs/`, so QA/other agents
## can grab a log file after a run instead of relying on captured stdout.
##
## Design goal (testability, per TK-PX-01): the *decision* of whether a
## message passes the threshold (`should_log`) and the *formatting* of a
## line (`format_line`) are pure, static, node-independent functions with
## no disk/Node access, so GUT can test them directly (tests/test_logger.gd).
## Only the instance methods below touch the filesystem, and they are
## written to never crash the game if the log file can't be opened/written
## (degrades to console-only logging).
##
## Reference: Tiger_Kick_Project_Docs/02_Technical/TDD.pdf §3 (managers/).
## Other systems should prefer GameLog.info()/warn()/error()/debug() over
## raw print()/push_warning() so log level + file capture stay consistent.
## (NetworkManager's "[NET]" prefixed prints predate this and are a separate
## concern -- domain tag vs. log level -- GameLog does not replace them.)

enum Level { DEBUG, INFO, WARN, ERROR }

const _LEVEL_NAMES: Dictionary = {
	Level.DEBUG: "DEBUG",
	Level.INFO: "INFO",
	Level.WARN: "WARN",
	Level.ERROR: "ERROR",
}

const LOG_DIR: String = "user://logs/"

var _min_level: Level = Level.DEBUG
var _log_file: FileAccess = null


func _ready() -> void:
	_open_log_file()


## Sets the minimum level that will actually be logged. Messages below this
## level are silently dropped (both console and file).
func set_level(level: Level) -> void:
	_min_level = level


## Returns the current minimum log level.
func get_level() -> Level:
	return _min_level


func debug(msg: String) -> void:
	_log(Level.DEBUG, msg)


func info(msg: String) -> void:
	_log(Level.INFO, msg)


func warn(msg: String) -> void:
	_log(Level.WARN, msg)


func error(msg: String) -> void:
	_log(Level.ERROR, msg)


## Returns the human-readable name for a Level (e.g. Level.INFO -> "INFO").
## Pure / node-independent -- safe to unit test directly.
static func level_to_string(level: Level) -> String:
	return _LEVEL_NAMES.get(level, "UNKNOWN")


## Pure decision logic: should a message at `msg_level` be emitted when the
## current minimum level is `current_level`? Higher enum value = more severe
## (DEBUG < INFO < WARN < ERROR), so a message passes when
## `msg_level >= current_level`. ERROR therefore always passes regardless of
## `current_level`, and DEBUG is dropped whenever the threshold is above DEBUG.
## No Node/disk access -- safe to unit test directly (tests/test_logger.gd).
static func should_log(current_level: Level, msg_level: Level) -> bool:
	return msg_level >= current_level


## Pure formatting logic: builds a single log line from a level, message, and
## an already-computed timestamp string. `timestamp` is injected (rather than
## read from Time inside this function) so tests are deterministic and need
## no engine/OS clock. Shape: "[<timestamp>][<LEVEL>] <message>", e.g.
## "[2026-07-04T12:00:00][INFO] message".
## No Node/disk access -- safe to unit test directly (tests/test_logger.gd).
static func format_line(level: Level, msg: String, timestamp: String) -> String:
	return "[%s][%s] %s" % [timestamp, level_to_string(level), msg]


## Instance-side entry point: checks the threshold, formats the line with
## the current real timestamp, prints it, and appends it to the log file
## (if one is open). Never raises even if the file is unavailable.
func _log(level: Level, msg: String) -> void:
	if not should_log(_min_level, level):
		return

	var timestamp: String = Time.get_datetime_string_from_system()
	var line: String = format_line(level, msg, timestamp)

	print(line)
	if level == Level.WARN:
		push_warning(line)
	elif level == Level.ERROR:
		push_error(line)

	_write_to_file(line)


## Creates user://logs/ if missing and opens a new per-session log file for
## appending. Degrades to console-only (leaves _log_file == null) on any
## failure -- a broken/missing log directory must never crash the game.
func _open_log_file() -> void:
	var dir_err: Error = DirAccess.make_dir_recursive_absolute(LOG_DIR)
	if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
		print("[Logger] could not create log directory %s (error code %d); console-only" % [LOG_DIR, dir_err])
		_log_file = null
		return

	var session_stamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var path: String = "%ssession_%s.log" % [LOG_DIR, session_stamp]

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("[Logger] could not open log file %s (error code %d); console-only" % [path, FileAccess.get_open_error()])
		_log_file = null
		return

	_log_file = file


## Appends one line to the open log file, if any. No-op (console-only
## degrade) if there is no open file -- never crashes.
func _write_to_file(line: String) -> void:
	if _log_file == null:
		return
	_log_file.store_line(line)
