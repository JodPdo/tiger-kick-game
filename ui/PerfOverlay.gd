extends CanvasLayer
## PerfOverlay (autoload singleton) -- registered in project.godot as
## PerfOverlay (line reported to the producer, see TK-PX-03 handoff; this
## agent does not edit project.godot).
##
## A globally available F4-toggled performance HUD reading raw engine
## counters from Godot's `Performance` singleton: static memory, render draw
## calls/objects/primitives-in-frame, live node count, and process/physics
## process time. This is deliberately a SEPARATE overlay from TK-PX-02's
## ui/DebugOverlay.gd (FPS/ping/state, F3) -- different concern (engine load
## vs. network/game state), different key, different script/autoload, no
## shared code. A small overlap (DebugOverlay already shows FPS; this one
## does not repeat it) is fine per the card.
##
## Implemented as an autoload CanvasLayer (rather than a per-scene .tscn) so
## it is present in every scene without each scene needing to instance it.
## `layer = 101` (one above DebugOverlay's 100) keeps it drawn above normal
## game UI and, if both overlays are visible at once, above DebugOverlay too.
##
## Hidden by default; F4 flips visibility (raw InputEventKey check in
## _input(), NOT an InputMap action -- avoids touching project.godot per the
## card's constraint, same pattern as DebugOverlay's F3 handling).
##
## Design goal (testability, per TK-PX-03): the *text-building* logic
## (`format_perf`) is a pure, static, node-independent function operating on
## a plain metrics Dictionary -- no Node/Performance access -- so GUT can
## test it directly (tests/test_perf_overlay.gd). Only the instance methods
## below touch Performance/Engine/the scene tree.
##
## Reference: Tiger_Kick_Project_Docs/02_Technical/TDD.pdf §3 (managers/ +
## debug tooling). Uses GameLog.debug() (not raw print()) for the toggle
## on/off notice, per project convention (see managers/Logger.gd).

## Refresh cadence: ~4x/sec, per the card ("not per-frame").
const REFRESH_INTERVAL_SEC: float = 0.25

## Bytes per megabyte, used to convert Performance.MEMORY_STATIC (raw bytes)
## into the MB figure shown on-screen.
const BYTES_PER_MB: float = 1024.0 * 1024.0

var _label: Label = null
var _refresh_timer: Timer = null


func _ready() -> void:
	layer = 101
	visible = false
	_build_ui()
	_start_refresh_timer()
	_refresh() # populate text immediately so the first F4 toggle shows fresh data, not a blank label


## Builds the on-screen Label as a plain code-built child (no separate
## PerfOverlay.tscn / theme asset needed) -- keeps this autoload
## self-contained in a single script file, same approach as DebugOverlay.
func _build_ui() -> void:
	_label = Label.new()
	_label.name = "PerfOverlayLabel"
	# Positioned below where DebugOverlay's label would sit (top-left, y=8)
	# so the two overlays don't overlap if both are toggled on at once.
	_label.position = Vector2(8, 40)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_font_size_override("font_size", 16)
	add_child(_label)


## Starts the ~4x/sec refresh timer (avoids recomputing Performance monitors
## every frame, per the card).
func _start_refresh_timer() -> void:
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = REFRESH_INTERVAL_SEC
	_refresh_timer.one_shot = false
	_refresh_timer.autostart = true
	_refresh_timer.timeout.connect(_refresh)
	add_child(_refresh_timer)


## Raw key check (per the card): F4 toggles visibility. Deliberately NOT an
## InputMap action, so no project.godot edit is required. `not event.echo`
## avoids re-toggling repeatedly while the key is held down. Same pattern as
## DebugOverlay's F3 handling.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_F4 and event.pressed and not event.echo:
		_toggle()


func _toggle() -> void:
	visible = not visible
	GameLog.debug("[PerfOverlay] toggled %s" % ("ON" if visible else "OFF"))
	if visible:
		_refresh() # show fresh numbers immediately, don't wait for the next timer tick


## Instance-side entry point: gathers live Performance monitors and rewrites
## the label text via the pure format_perf(). Called on a timer, not every
## frame.
func _refresh() -> void:
	if _label == null:
		return
	var metrics: Dictionary = _gather_metrics()
	_label.text = format_perf(metrics)


## Reads raw counters from Godot's Performance singleton. Kept as thin/dumb
## as possible -- all interpretation/formatting happens in format_perf().
## Monitor choices (per the card):
##   MEMORY_STATIC                       -- static memory usage (bytes)
##   RENDER_TOTAL_DRAW_CALLS_IN_FRAME     -- draw calls in the last frame
##   RENDER_TOTAL_OBJECTS_IN_FRAME        -- objects rendered in the last frame
##   RENDER_TOTAL_PRIMITIVES_IN_FRAME     -- primitives rendered in the last frame
##   OBJECT_NODE_COUNT                    -- live Node count in the scene tree
##   TIME_PROCESS / TIME_PHYSICS_PROCESS  -- last _process()/_physics_process()
##                                           duration, in seconds (converted
##                                           to ms below)
func _gather_metrics() -> Dictionary:
	return {
		"memory_static_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_process_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
	}


## Pure formatting logic: builds the overlay's single display line from an
## already-computed metrics Dictionary. No Node/Performance/Engine access --
## safe to unit test directly (tests/test_perf_overlay.gd).
##
## `metrics` keys (all optional, defaults shown if missing):
##   "memory_static_bytes": float (default 0.0) -- static memory, raw bytes;
##                                                  converted to MB (1 decimal)
##   "draw_calls": int (default 0)
##   "objects": int (default 0)
##   "primitives": int (default 0)
##   "node_count": int (default 0)
##   "process_ms": float (default 0.0)          -- 2 decimals
##   "physics_process_ms": float (default 0.0)  -- 2 decimals
static func format_perf(metrics: Dictionary) -> String:
	var mem_bytes: float = metrics.get("memory_static_bytes", 0.0)
	var mem_mb: float = mem_bytes / BYTES_PER_MB
	var draw_calls: int = metrics.get("draw_calls", 0)
	var objects: int = metrics.get("objects", 0)
	var primitives: int = metrics.get("primitives", 0)
	var node_count: int = metrics.get("node_count", 0)
	var process_ms: float = metrics.get("process_ms", 0.0)
	var physics_ms: float = metrics.get("physics_process_ms", 0.0)
	return "Mem: %.1f MB | Draw Calls: %d | Objects: %d | Primitives: %d | Nodes: %d | Process: %.2f ms | Physics: %.2f ms" % [mem_mb, draw_calls, objects, primitives, node_count, process_ms, physics_ms]
