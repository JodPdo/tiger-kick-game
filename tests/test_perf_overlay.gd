extends GutTest
## Unit tests for ui/PerfOverlay.gd -- pure text-building logic only.
##
## Covers TK-PX-03 (performance overlay). Only format_perf() is tested here:
## it is a pure, static, node-independent function that takes an
## already-computed metrics Dictionary and returns a String -- no scene
## tree, no Performance/Engine access, no rendering. Live F4 toggle
## behavior, real Performance singleton sampling, and CanvasLayer visibility
## are out of scope for GUT (same rationale as tests/test_debug_overlay.gd)
## and are exercised manually / by the producer's combined verification pass.
##
## NOTE: assert_string_contains(text, search, match_case) -- the 3rd param is
## a case-sensitivity flag, NOT a free-text assertion message -- so we don't
## pass one; intent is documented via comments/test names instead.

const PerfOverlayScript := preload("res://ui/PerfOverlay.gd")


# --- shape: all fields present --------------------------------------------

func test_format_perf_includes_all_fields() -> void:
	var metrics: Dictionary = {
		"memory_static_bytes": 100.0 * 1024.0 * 1024.0, # 100 MB
		"draw_calls": 42,
		"objects": 500,
		"primitives": 12345,
		"node_count": 87,
		"process_ms": 3.456,
		"physics_process_ms": 1.234,
	}
	var result: String = PerfOverlayScript.format_perf(metrics)
	assert_string_contains(result, "Mem: 100.0 MB")
	assert_string_contains(result, "Draw Calls: 42")
	assert_string_contains(result, "Objects: 500")
	assert_string_contains(result, "Primitives: 12345")
	assert_string_contains(result, "Nodes: 87")
	assert_string_contains(result, "Process: 3.46 ms")
	assert_string_contains(result, "Physics: 1.23 ms")


# --- byte -> MB conversion / rounding --------------------------------------

func test_format_perf_converts_bytes_to_mb_with_one_decimal() -> void:
	# 1.5 MB expressed in raw bytes must render as "1.5 MB", not bytes.
	var metrics: Dictionary = {"memory_static_bytes": 1.5 * 1024.0 * 1024.0}
	var result: String = PerfOverlayScript.format_perf(metrics)
	assert_string_contains(result, "Mem: 1.5 MB")


func test_format_perf_zero_memory_renders_zero_mb() -> void:
	var metrics: Dictionary = {"memory_static_bytes": 0.0}
	var result: String = PerfOverlayScript.format_perf(metrics)
	assert_string_contains(result, "Mem: 0.0 MB")


func test_format_perf_rounds_mb_to_one_decimal_place() -> void:
	# 10 MB + a few KB should round to one decimal, not show raw noise.
	var metrics: Dictionary = {"memory_static_bytes": 10.04 * 1024.0 * 1024.0}
	var result: String = PerfOverlayScript.format_perf(metrics)
	assert_string_contains(result, "Mem: 10.0 MB")


# --- defaults: missing dictionary keys must not crash ---------------------

func test_format_perf_defaults_all_fields_when_empty_dictionary() -> void:
	var result: String = PerfOverlayScript.format_perf({})
	assert_string_contains(result, "Mem: 0.0 MB")
	assert_string_contains(result, "Draw Calls: 0")
	assert_string_contains(result, "Objects: 0")
	assert_string_contains(result, "Primitives: 0")
	assert_string_contains(result, "Nodes: 0")
	assert_string_contains(result, "Process: 0.00 ms")
	assert_string_contains(result, "Physics: 0.00 ms")


func test_format_perf_partial_dictionary_does_not_crash() -> void:
	# only "node_count" supplied -- everything else must fall back to
	# defaults, not crash.
	var result: String = PerfOverlayScript.format_perf({"node_count": 250})
	assert_string_contains(result, "Nodes: 250")
	assert_string_contains(result, "Mem: 0.0 MB")
	assert_string_contains(result, "Draw Calls: 0")


# --- process/physics timing formatting ------------------------------------

func test_format_perf_process_and_physics_timings_two_decimals() -> void:
	var metrics: Dictionary = {"process_ms": 16.0, "physics_process_ms": 8.0}
	var result: String = PerfOverlayScript.format_perf(metrics)
	assert_string_contains(result, "Process: 16.00 ms")
	assert_string_contains(result, "Physics: 8.00 ms")
