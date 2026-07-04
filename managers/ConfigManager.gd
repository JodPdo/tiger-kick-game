extends Node
## ConfigManager (autoload singleton)
##
## Wraps a Godot `ConfigFile` persisted at `user://settings.cfg` and exposes a
## small, stable get/set API that other systems (and, next, the Settings menu
## in TK-PX-05) can build on without touching `ConfigFile` directly.
##
## Public API: get_value() / set_value() / save() / load_config() (NOT
## `load()` -- that name collides with GDScript's global `load(path)`
## builtin and is a hard parse error; see load_config() doc below).
##
## Design goal (testability, per TK-PX-04): the *decision* of what value comes
## back for a given section/key (`resolve_value`) and how a stored dictionary
## gets backfilled with defaults (`apply_defaults`) are pure, static,
## node-independent functions that operate on plain Dictionaries -- no
## ConfigFile/disk access -- so GUT can test get/default/override semantics
## directly (tests/test_config_manager.gd). Only the instance methods below
## touch the filesystem, and they are written to never crash the game if
## `user://settings.cfg` is missing or can't be read/written (falls back to
## DEFAULTS, logs a warning, returns an Error).
##
## Reference: Tiger_Kick_Project_Docs/02_Technical/TDD.pdf §3 (managers/).
## This is the config backend TK-PX-05 (Settings menu: Graphics/Audio/Controls
## rebind) consumes -- keep get_value()/set_value()/save()/load_config() and
## DEFAULTS stable; extend DEFAULTS rather than renaming existing keys.

const CONFIG_PATH: String = "user://settings.cfg"

## Default values applied whenever a section/key is missing from the store.
## Sections match the planned Settings menu tabs (TK-PX-05): Graphics, Audio,
## Controls. Extend this dictionary (don't rename existing keys) as new
## settings are added.
const DEFAULTS: Dictionary = {
	"graphics": {
		"resolution_x": 1920,
		"resolution_y": 1080,
		"fullscreen": false,
		"vsync": true,
		"max_fps": 60,
	},
	"audio": {
		"master_volume": 1.0,
		"music_volume": 0.8,
		"sfx_volume": 1.0,
		"mute": false,
	},
	"controls": {
		"mouse_sensitivity": 1.0,
		"invert_y": false,
		"rebind_move_forward": "w",
		"rebind_move_back": "s",
		"rebind_move_left": "a",
		"rebind_move_right": "d",
		"rebind_kick": "mouse_left",
		"rebind_tag": "mouse_left",
	},
}

var _config: ConfigFile = ConfigFile.new()

## In-memory mirror of everything actually present in `_config` (i.e. values
## the user overrode / previously saved). Kept as a plain Dictionary so the
## get/default resolution logic can be pure and disk-free (see resolve_value).
var _store: Dictionary = {}


func _ready() -> void:
	load_config()


## Returns the value for `section`/`key`: a previously-saved override if one
## exists, otherwise the DEFAULTS entry, otherwise `default`. Never touches
## disk (reads from the in-memory `_store` populated by load_config()/set_value()).
func get_value(section: String, key: String, default: Variant = null) -> Variant:
	return resolve_value(_store, DEFAULTS, section, key, default)


## Stores `value` for `section`/`key` in memory and in the underlying
## ConfigFile. Call save() afterwards to persist to disk.
func set_value(section: String, key: String, value: Variant) -> void:
	if not _store.has(section):
		_store[section] = {}
	_store[section][key] = value
	_config.set_value(section, key, value)


## Writes the current ConfigFile contents to `user://settings.cfg`. Creates
## the file if it doesn't exist yet. Returns OK on success, or the Error code
## from ConfigFile.save() on failure (e.g. bad permissions) -- never crashes.
func save() -> Error:
	var err: Error = _config.save(CONFIG_PATH)
	if err != OK:
		push_warning("[CONFIG] save() failed for %s (error code %d)" % [CONFIG_PATH, err])
		print("[CONFIG] save() failed for %s (error code %d)" % [CONFIG_PATH, err])
	return err


## Loads `user://settings.cfg` into memory. If the file doesn't exist yet
## (fresh install), this is treated as success: the in-memory store simply
## stays empty and get_value() falls back to DEFAULTS. Any other read failure
## is logged and reported via the returned Error, but never crashes -- the
## store is left as-is (defaults still apply through get_value()).
##
## NOTE: named load_config() rather than load() -- a method literally named
## `load` shadows GDScript's global builtin `load(path)` within this class's
## own scope. Calling `load()` with zero args (e.g. from _ready()) then binds
## to the global builtin, which requires 1 argument -- a hard PARSE ERROR,
## not a runtime one, so the whole script fails to compile. Keep this name;
## do not rename it back to `load()`.
func load_config() -> Error:
	var err: Error = _config.load(CONFIG_PATH)
	if err == OK:
		_store = _config_to_dict(_config)
		return OK
	if err == ERR_FILE_NOT_FOUND:
		# No settings.cfg yet -- fine, DEFAULTS cover everything until save().
		_store = {}
		return OK

	push_warning("[CONFIG] load_config() failed for %s (error code %d); using defaults" % [CONFIG_PATH, err])
	print("[CONFIG] load_config() failed for %s (error code %d); using defaults" % [CONFIG_PATH, err])
	return err


## Pure lookup: does `store[section][key]` exist? Return it. Otherwise fall
## back to `defaults[section][key]` if present, otherwise `fallback`.
## No ConfigFile/disk/Node access -- safe to unit test directly
## (tests/test_config_manager.gd).
static func resolve_value(store: Dictionary, defaults: Dictionary, section: String, key: String, fallback: Variant = null) -> Variant:
	if store.has(section) and (store[section] as Dictionary).has(key):
		return store[section][key]
	if defaults.has(section) and (defaults[section] as Dictionary).has(key):
		return defaults[section][key]
	return fallback


## Pure merge: returns a NEW dictionary equal to `store` with any section/key
## present in `defaults` but missing from `store` filled in. Existing values
## in `store` are never overwritten. Neither input dictionary is mutated.
## No ConfigFile/disk/Node access -- safe to unit test directly
## (tests/test_config_manager.gd).
static func apply_defaults(store: Dictionary, defaults: Dictionary) -> Dictionary:
	var merged: Dictionary = store.duplicate(true)
	for section in defaults:
		if not merged.has(section):
			merged[section] = {}
		var section_defaults: Dictionary = defaults[section]
		for key in section_defaults:
			if not merged[section].has(key):
				merged[section][key] = section_defaults[key]
	return merged


## Instance-side helper: flattens a loaded ConfigFile into a plain Dictionary
## of the shape {section: {key: value}}, so the rest of this class can work
## against Dictionaries (and so resolve_value/apply_defaults stay disk-free).
func _config_to_dict(config: ConfigFile) -> Dictionary:
	var dict: Dictionary = {}
	for section in config.get_sections():
		var section_dict: Dictionary = {}
		for key in config.get_section_keys(section):
			section_dict[key] = config.get_value(section, key)
		dict[section] = section_dict
	return dict
