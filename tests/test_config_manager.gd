extends GutTest
## Unit tests for managers/ConfigManager.gd -- pure get/default/override logic.
##
## Covers TK-PX-04 (ConfigManager autoload). Only the pure, node-independent
## static functions (resolve_value, apply_defaults) are tested here -- they
## operate on plain Dictionaries and never touch ConfigFile/disk. Actual
## `user://settings.cfg` read/write is out of scope for GUT (per the card)
## and is exercised manually / by the producer's combined verification pass.

const ConfigManagerScript := preload("res://managers/ConfigManager.gd")

const DEFAULTS: Dictionary = {
	"graphics": {
		"fullscreen": false,
		"max_fps": 60,
	},
	"audio": {
		"master_volume": 1.0,
	},
}


# --- resolve_value: value present in store -----------------------------------

func test_resolve_value_returns_stored_value_when_present() -> void:
	var store: Dictionary = {"graphics": {"fullscreen": true}}
	var result: Variant = ConfigManagerScript.resolve_value(store, DEFAULTS, "graphics", "fullscreen", "fallback")
	assert_eq(result, true, "a value present in the store must win over defaults/fallback")


func test_resolve_value_stored_value_overrides_default() -> void:
	# store has a DIFFERENT value than DEFAULTS for the same key
	var store: Dictionary = {"graphics": {"max_fps": 144}}
	var result: Variant = ConfigManagerScript.resolve_value(store, DEFAULTS, "graphics", "max_fps", null)
	assert_eq(result, 144, "stored override must be returned, not the DEFAULTS value (60)")


# --- resolve_value: value missing from store, present in defaults -----------

func test_resolve_value_falls_back_to_default_when_key_missing() -> void:
	var store: Dictionary = {"graphics": {}}
	var result: Variant = ConfigManagerScript.resolve_value(store, DEFAULTS, "graphics", "max_fps", "fallback")
	assert_eq(result, 60, "missing key in store should fall back to DEFAULTS")


func test_resolve_value_falls_back_to_default_when_section_missing() -> void:
	var store: Dictionary = {}
	var result: Variant = ConfigManagerScript.resolve_value(store, DEFAULTS, "audio", "master_volume", "fallback")
	assert_eq(result, 1.0, "missing section in store should fall back to DEFAULTS")


# --- resolve_value: value missing everywhere ---------------------------------

func test_resolve_value_returns_fallback_when_missing_everywhere() -> void:
	var result: Variant = ConfigManagerScript.resolve_value({}, DEFAULTS, "controls", "rebind_kick", "unbound")
	assert_eq(result, "unbound", "key absent from both store and defaults should return the fallback param")


func test_resolve_value_returns_null_fallback_by_default() -> void:
	var result: Variant = ConfigManagerScript.resolve_value({}, {}, "nope", "nope")
	assert_eq(result, null, "fallback defaults to null when not supplied")


# --- set-then-get override semantics (simulated on plain dictionaries) ------

func test_set_then_get_override_beats_default() -> void:
	var store: Dictionary = {}
	# simulate what set_value() does to the in-memory store
	store["graphics"] = {"fullscreen": true}
	var before: Variant = ConfigManagerScript.resolve_value({}, DEFAULTS, "graphics", "fullscreen", null)
	var after: Variant = ConfigManagerScript.resolve_value(store, DEFAULTS, "graphics", "fullscreen", null)
	assert_eq(before, false, "before the override, DEFAULTS value (false) should be returned")
	assert_eq(after, true, "after the simulated override, the overridden value should be returned")


# --- apply_defaults: missing sections/keys backfilled -----------------------

func test_apply_defaults_fills_missing_section() -> void:
	var merged: Dictionary = ConfigManagerScript.apply_defaults({}, DEFAULTS)
	assert_true(merged.has("graphics"), "missing section should be created from defaults")
	assert_eq(merged["graphics"]["fullscreen"], false)
	assert_eq(merged["graphics"]["max_fps"], 60)
	assert_eq(merged["audio"]["master_volume"], 1.0)


func test_apply_defaults_fills_missing_key_without_touching_existing_keys() -> void:
	var store: Dictionary = {"graphics": {"fullscreen": true}}
	var merged: Dictionary = ConfigManagerScript.apply_defaults(store, DEFAULTS)
	assert_eq(merged["graphics"]["fullscreen"], true, "existing key must not be overwritten by defaults")
	assert_eq(merged["graphics"]["max_fps"], 60, "missing key in the same section should be backfilled")


func test_apply_defaults_does_not_mutate_inputs() -> void:
	var store: Dictionary = {"graphics": {"fullscreen": true}}
	var defaults_copy: Dictionary = DEFAULTS.duplicate(true)
	ConfigManagerScript.apply_defaults(store, DEFAULTS)
	assert_eq(store, {"graphics": {"fullscreen": true}}, "input store must not be mutated")
	assert_eq(DEFAULTS, defaults_copy, "input defaults must not be mutated")


func test_apply_defaults_on_empty_store_equals_defaults() -> void:
	var merged: Dictionary = ConfigManagerScript.apply_defaults({}, DEFAULTS)
	assert_eq(merged, DEFAULTS, "an empty store fully backfilled by apply_defaults should equal DEFAULTS")
