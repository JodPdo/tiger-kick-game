extends GutTest
## Unit tests for ui/DebugOverlay.gd -- pure text-building logic only.
##
## Covers TK-PX-02 (debug overlay). Only format_overlay() is tested here: it
## is a pure, static, node-independent function that takes already-computed
## fps/ping_ms/state values and returns a String -- no scene tree, no
## Performance/Engine/multiplayer access, no rendering. Live F3 toggle
## behavior, real FPS/ping sampling, and CanvasLayer visibility are out of
## scope for GUT (per the card) and are exercised manually / by the
## producer's combined verification pass.
##
## NOTE: assert_string_contains(text, search, match_case) -- the 3rd param is
## a case-sensitivity flag, NOT a free-text assertion message -- so we don't
## pass one; intent is documented via comments/test names instead.

const DebugOverlayScript := preload("res://ui/DebugOverlay.gd")


# --- shape: all fields present, online -----------------------------------

func test_format_overlay_includes_fps_ping_and_state_online() -> void:
	var state: Dictionary = {"scene": "TestArena", "role": "host", "peer_count": 4}
	var result: String = DebugOverlayScript.format_overlay(60, 42, state)
	assert_string_contains(result, "FPS: 60")
	assert_string_contains(result, "Ping: 42 ms")
	assert_string_contains(result, "Scene: TestArena")
	assert_string_contains(result, "Role: host")
	assert_string_contains(result, "Peers: 4")


func test_format_overlay_client_role() -> void:
	var state: Dictionary = {"scene": "TestArena", "role": "client", "peer_count": 4}
	var result: String = DebugOverlayScript.format_overlay(60, 15, state)
	assert_string_contains(result, "Role: client")
	assert_string_contains(result, "Ping: 15 ms")


# --- offline: ping n/a, must never crash / never show a bogus number -----

func test_format_overlay_shows_na_ping_when_unavailable() -> void:
	# offline/unavailable ping must render as "n/a", not "-1" and not a crash
	var state: Dictionary = {"scene": "MainMenu", "role": "offline", "peer_count": 0}
	var result: String = DebugOverlayScript.format_overlay(60, DebugOverlayScript.PING_UNAVAILABLE, state)
	assert_string_contains(result, "Ping: n/a")
	assert_string_contains(result, "Role: offline")
	assert_string_contains(result, "Peers: 0")


func test_format_overlay_ping_unavailable_sentinel_is_negative_one() -> void:
	# format_overlay() and _compute_ping_ms() agree on this sentinel value.
	assert_eq(DebugOverlayScript.PING_UNAVAILABLE, -1)


# --- defaults: missing dictionary keys must not crash ---------------------

func test_format_overlay_defaults_scene_when_missing() -> void:
	var result: String = DebugOverlayScript.format_overlay(30, DebugOverlayScript.PING_UNAVAILABLE, {})
	assert_string_contains(result, "Scene: n/a")
	assert_string_contains(result, "Role: offline")
	assert_string_contains(result, "Peers: 0")
	assert_string_contains(result, "Ping: n/a")


func test_format_overlay_partial_state_dictionary_does_not_crash() -> void:
	# only "scene" supplied -- role/peer_count must fall back to defaults, not crash
	var result: String = DebugOverlayScript.format_overlay(15, 100, {"scene": "TestArena"})
	assert_string_contains(result, "Scene: TestArena")
	assert_string_contains(result, "Role: offline")
	assert_string_contains(result, "Peers: 0")


# --- low fps / zero ping edge values --------------------------------------

func test_format_overlay_handles_zero_fps_and_zero_ping() -> void:
	# an actual 0ms ping must be distinguished from "n/a" (PING_UNAVAILABLE == -1, not 0)
	var result: String = DebugOverlayScript.format_overlay(0, 0, {"scene": "Loading", "role": "offline", "peer_count": 0})
	assert_string_contains(result, "FPS: 0")
	assert_string_contains(result, "Ping: 0 ms")
