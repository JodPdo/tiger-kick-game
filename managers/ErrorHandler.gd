extends Node
## ErrorHandler (autoload singleton) -- registered in project.godot as
## ErrorHandler ("*res://managers/ErrorHandler.gd").
##
## Centralized error-handling convention for TK-PX-06: systems that hit an
## important failure (bad RPC payload, missing resource, invalid state
## transition, etc.) should call `ErrorHandler.report(...)` or
## `ErrorHandler.report_if(...)` instead of a bare `push_error()`/`print()`,
## so the failure is always:
##   1) formatted consistently (context + message + optional Error code), and
##   2) routed through GameLog.error(...) -- which prints to console AND
##      appends to the per-session file under user://logs/ (see
##      managers/Logger.gd / TK-PX-01).
##
## This is a *soft* assert layer: it never hard-crashes the game in release.
## Reporting an error just logs it (and, via GameLog, also calls Godot's
## push_error so it shows up in the editor/CI output) -- the caller is always
## responsible for deciding how to recover (early return, fallback value,
## disconnect, etc.). ErrorHandler only centralizes the *logging*, not the
## recovery policy.
##
## Convention:
##   ErrorHandler.report("NetworkManager.join", "invalid port", ERR_INVALID_PARAMETER)
##   if ErrorHandler.report_if(peer == null, "RoundManager", "no active peer"):
##       return
##
## Design goal (testability, per TK-PX-06, mirrors managers/Logger.gd): the
## *formatting* of a report line (`format_error`) and the boolean decision
## logic of `report_if` are pure, static/node-independent functions with no
## Node/disk/GameLog access, so GUT can test them directly
## (tests/test_error_handler.gd). Only the instance methods below actually
## call into GameLog.
##
## Engine-hook follow-up (NOT done here): Godot 4.7 has no simple, stable,
## public API to intercept *engine-internal* errors (e.g. a null deref
## inside a built-in call) from GDScript -- the closest primitive is
## `OS.add_logger(Logger)`, which GUT's own error_tracker
## (addons/gut/error_tracker.gd) already uses and which the codebase's own
## Logger.gd doc-comment calls out as "finicky" (it's why the autoload here
## is named GameLog, not Logger -- to avoid colliding with the engine's
## built-in `Logger` class that OS.add_logger expects). Stacking another
## OS.add_logger() on top of GUT's would risk fighting over the same engine
## hook mid-test-run. Given that risk for a Dev Infra card whose priority is
## "catch important errors + log", this script intentionally sticks to the
## explicit report()/report_if() API + documented convention above. If a
## future card wants engine-level interception, it should be scoped
## separately and coordinated with qa-engineer (GUT depends on the same
## engine logger hook).
##
## Reference: Tiger_Kick_Project_Docs/02_Technical/TDD.pdf §3 (managers/).


## Reports an important error: formats a consistent line via `format_error`
## and logs it through GameLog.error(...) (console + user://logs/). Always
## returns after logging -- callers decide their own recovery.
## `context` should identify the calling system/function, e.g.
## "NetworkManager.join" or "RoundManager._start_round".
## `err` defaults to OK; pass a Godot Error code (e.g. ERR_INVALID_PARAMETER)
## when the failure has one, and it will be appended to the log line.
func report(context: String, message: String, err: int = OK) -> void:
	var line: String = format_error(context, message, err)
	GameLog.error(line)


## Soft-assert guard helper: if `condition_failed` is true, logs the error
## (same as `report`) and returns true so the caller can early-return, e.g.:
##   if ErrorHandler.report_if(peer == null, "RoundManager", "no active peer"):
##       return
## If `condition_failed` is false, this is a no-op that returns false and
## logs nothing -- safe to call on every frame/branch without spamming logs.
## Never raises/crashes regardless of `condition_failed`.
func report_if(condition_failed: bool, context: String, message: String, err: int = OK) -> bool:
	if condition_failed:
		report(context, message, err)
	return condition_failed


## Pure formatting logic: builds a single error-report line from a context,
## message, and an optional Godot Error code. Shape:
##   "[<context>] <message>"                      when err == OK
##   "[<context>] <message> (error code <err>)"    when err != OK
## No Node/disk/GameLog access -- safe to unit test directly
## (tests/test_error_handler.gd).
static func format_error(context: String, message: String, err: int = OK) -> String:
	var line: String = "[%s] %s" % [context, message]
	if err != OK:
		line += " (error code %d)" % err
	return line


## Pure boolean decision logic behind `report_if`, extracted for direct unit
## testing without touching GameLog. Simply returns `condition_failed`
## unchanged -- kept as its own function so the *contract* ("report_if
## returns exactly what it was told to guard against") is explicit and
## tested, independent of the logging side effect.
static func should_report(condition_failed: bool) -> bool:
	return condition_failed
