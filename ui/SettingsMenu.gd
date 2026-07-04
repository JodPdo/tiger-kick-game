extends Control
## SettingsMenu.gd
##
## Settings screen (TK-PX-05): Graphics / Audio / Controls (rebind), backed by
## the ConfigManager autoload (TK-PX-04). Reads current values from
## ConfigManager.get_value() on _ready(), writes them back via set_value() +
## save() when "Apply & Save" is pressed, and reflects Graphics/Audio changes
## to the live engine (DisplayServer/Engine/AudioServer) at the same time.
##
## Design goal (testability, per the card): resolution string <-> Vector2i
## conversion, max-fps clamping, the volume-slider <-> dB mapping, and the
## rebind-key/InputMap-action naming/filtering logic are pure, static,
## node-independent functions with no Node/DisplayServer/AudioServer/InputMap
## access, so GUT can test them directly (tests/test_settings.gd). Only the
## instance methods below touch the engine/ConfigManager/InputMap, and every
## engine call is guarded so a headless run (no display server, no audio
## buses configured yet, empty InputMap) degrades gracefully -- logs via
## GameLog.warn(), never crashes.
##
## Controls/rebind note: the gameplay input actions (move/kick/tag) belong to
## Phase 1 (see _backlog.json TK-P1-xx) and do not exist in the InputMap yet
## (project.godot has no [input] section as of this card). This screen still
## lets a player pre-configure the controls.rebind_star keys via ConfigManager
## (so the choice is remembered) and shows a placeholder notice explaining
## why the rows are not live yet; it only pushes a captured binding into
## InputMap.action_add_event() when the matching action already exists, and
## otherwise logs a warning and leaves InputMap untouched -- no gameplay
## bindings are invented here.
##
## Reference: Tiger_Kick_Project_Docs/02_Technical/TDD.pdf sec 3 (managers/ +
## Settings menu). Entry point: MainMenu Settings button switches here via
## change_scene_to_file(); Back switches back the same way (see MainMenu.gd
## for the existing pattern used by TestArena transition).

const MAIN_MENU_SCENE: String = "res://ui/MainMenu.tscn"

## Common resolution choices offered in the Graphics tab dropdown.
const RESOLUTION_CHOICES: Array[String] = [
	"1280x720",
	"1600x900",
	"1920x1080",
	"2560x1440",
	"3840x2160",
]

## dB floor used when a volume slider is at (or near) 0 -- avoids feeding
## -inf (linear_to_db(0) == -inf) into AudioServer.set_bus_volume_db().
const MIN_VOLUME_DB: float = -80.0

## Prefix stripped by rebind_key_to_action_name() to turn a ConfigManager
## controls key (e.g. rebind_move_forward) into an InputMap action name
## (e.g. move_forward).
const REBIND_PREFIX: String = "rebind_"

## controls keys (per ConfigManager.DEFAULTS) this screen builds a rebind
## row for, in display order.
const REBIND_KEYS: Array[String] = [
	"rebind_move_forward",
	"rebind_move_back",
	"rebind_move_left",
	"rebind_move_right",
	"rebind_kick",
	"rebind_tag",
]

@onready var resolution_option: OptionButton = $MarginContainer/VBoxContainer/TabContainer/Graphics/ResolutionRow/ResolutionOption
@onready var fullscreen_check: CheckBox = $MarginContainer/VBoxContainer/TabContainer/Graphics/FullscreenCheck
@onready var vsync_check: CheckBox = $MarginContainer/VBoxContainer/TabContainer/Graphics/VSyncCheck
@onready var max_fps_spinbox: SpinBox = $MarginContainer/VBoxContainer/TabContainer/Graphics/MaxFpsRow/MaxFpsSpinBox

@onready var master_slider: HSlider = $MarginContainer/VBoxContainer/TabContainer/Audio/MasterRow/MasterSlider
@onready var music_slider: HSlider = $MarginContainer/VBoxContainer/TabContainer/Audio/MusicRow/MusicSlider
@onready var sfx_slider: HSlider = $MarginContainer/VBoxContainer/TabContainer/Audio/SfxRow/SfxSlider
@onready var mute_check: CheckBox = $MarginContainer/VBoxContainer/TabContainer/Audio/MuteCheck

@onready var sensitivity_slider: HSlider = $MarginContainer/VBoxContainer/TabContainer/Controls/SensitivityRow/SensitivitySlider
@onready var invert_y_check: CheckBox = $MarginContainer/VBoxContainer/TabContainer/Controls/InvertYCheck
@onready var phase1_notice_label: Label = $MarginContainer/VBoxContainer/TabContainer/Controls/Phase1NoticeLabel
@onready var rebind_rows_container: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/Controls/RebindRowsContainer

@onready var apply_button: Button = $MarginContainer/VBoxContainer/ButtonRow/ApplyButton
@onready var back_button: Button = $MarginContainer/VBoxContainer/ButtonRow/BackButton
@onready var status_label: Label = $MarginContainer/VBoxContainer/StatusLabel

## Rebind key (e.g. rebind_kick) currently waiting for the next
## key/mouse-button press, or empty string when not in rebind-listening mode.
var _listening_for_key: String = ""

## rebind_key -> the Button whose text shows the current binding, so a
## just-captured rebind can update its label without rebuilding every row.
var _rebind_buttons: Dictionary = {}


func _ready() -> void:
	status_label.text = ""
	_populate_resolution_options()
	_load_from_config()
	_build_rebind_rows()

	apply_button.pressed.connect(_on_apply_pressed)
	back_button.pressed.connect(_on_back_pressed)


# --- load / populate --------------------------------------------------------

func _populate_resolution_options() -> void:
	resolution_option.clear()
	for choice in RESOLUTION_CHOICES:
		resolution_option.add_item(choice)


func _load_from_config() -> void:
	var res_x: int = ConfigManager.get_value("graphics", "resolution_x", 1920)
	var res_y: int = ConfigManager.get_value("graphics", "resolution_y", 1080)
	var res_str: String = size_to_resolution_string(Vector2i(res_x, res_y))
	var res_index: int = RESOLUTION_CHOICES.find(res_str)
	resolution_option.selected = res_index if res_index != -1 else RESOLUTION_CHOICES.find("1920x1080")

	fullscreen_check.button_pressed = ConfigManager.get_value("graphics", "fullscreen", false)
	vsync_check.button_pressed = ConfigManager.get_value("graphics", "vsync", true)
	max_fps_spinbox.value = ConfigManager.get_value("graphics", "max_fps", 60)

	master_slider.value = ConfigManager.get_value("audio", "master_volume", 1.0)
	music_slider.value = ConfigManager.get_value("audio", "music_volume", 0.8)
	sfx_slider.value = ConfigManager.get_value("audio", "sfx_volume", 1.0)
	mute_check.button_pressed = ConfigManager.get_value("audio", "mute", false)

	sensitivity_slider.value = ConfigManager.get_value("controls", "mouse_sensitivity", 1.0)
	invert_y_check.button_pressed = ConfigManager.get_value("controls", "invert_y", false)


## Builds one row per REBIND_KEYS entry under RebindRowsContainer: a Label
## with the friendly action name, a Button showing the current bound
## key/mouse-button (from ConfigManager), and a Rebind button that starts
## listening mode. Also shows/hides phase1_notice_label depending on
## whether ANY non-ui_ prefixed action already exists in the InputMap --
## Phase 1 (TK-P1-xx) is expected to add move/kick/tag actions; until then
## this is a clear placeholder rather than a silent no-op.
func _build_rebind_rows() -> void:
	for child in rebind_rows_container.get_children():
		child.queue_free()
	_rebind_buttons.clear()

	var custom_actions: Array = filter_custom_input_actions(InputMap.get_actions())
	phase1_notice_label.visible = custom_actions.is_empty()

	for rebind_key in REBIND_KEYS:
		rebind_rows_container.add_child(_build_rebind_row(rebind_key))


func _build_rebind_row(rebind_key: String) -> HBoxContainer:
	var action_name: String = rebind_key_to_action_name(rebind_key)
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "RebindRow_%s" % action_name

	var label: Label = Label.new()
	label.text = action_name.capitalize()
	label.custom_minimum_size = Vector2(140, 0)
	row.add_child(label)

	var current_value: String = ConfigManager.get_value("controls", rebind_key, "")
	var bind_button: Button = Button.new()
	bind_button.name = "BindButton"
	bind_button.custom_minimum_size = Vector2(120, 0)
	bind_button.text = current_value if not current_value.is_empty() else "(unbound)"
	row.add_child(bind_button)

	var rebind_button: Button = Button.new()
	rebind_button.text = "Rebind"
	rebind_button.pressed.connect(_on_rebind_button_pressed.bind(rebind_key))
	row.add_child(rebind_button)

	if not InputMap.has_action(action_name):
		var note: Label = Label.new()
		note.text = "(Phase 1 -- not yet in InputMap)"
		note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		row.add_child(note)

	_rebind_buttons[rebind_key] = bind_button
	return row


# --- rebind capture ----------------------------------------------------------

func _on_rebind_button_pressed(rebind_key: String) -> void:
	_listening_for_key = rebind_key
	var bind_button: Button = _rebind_buttons.get(rebind_key)
	if bind_button != null:
		bind_button.text = "Press any key..."


func _input(event: InputEvent) -> void:
	if _listening_for_key.is_empty():
		return

	var captured: String = ""
	if event is InputEventKey and event.pressed and not event.echo:
		captured = OS.get_keycode_string(event.physical_keycode)
	elif event is InputEventMouseButton and event.pressed:
		captured = "mouse_%d" % event.button_index

	if captured.is_empty():
		return

	var rebind_key: String = _listening_for_key
	_listening_for_key = ""

	ConfigManager.set_value("controls", rebind_key, captured)
	var bind_button: Button = _rebind_buttons.get(rebind_key)
	if bind_button != null:
		bind_button.text = captured
	_apply_rebind_to_input_map(rebind_key, event)

	get_viewport().set_input_as_handled()


## Pushes a just-captured rebind into the live InputMap IF the matching
## action already exists (Phase 1 dependency, see class doc). Never invents
## a new InputMap action here -- if it does not exist yet, logs a warning
## and leaves InputMap untouched (the choice is still saved in ConfigManager
## for whenever Phase 1 wires the action up).
func _apply_rebind_to_input_map(rebind_key: String, event: InputEvent) -> void:
	var action_name: String = rebind_key_to_action_name(rebind_key)
	if not InputMap.has_action(action_name):
		GameLog.warn("[Settings] InputMap action %s does not exist yet (Phase 1 dependency); binding stored in config only" % action_name)
		return

	InputMap.action_erase_events(action_name)
	InputMap.action_add_event(action_name, event)


# --- apply / save ------------------------------------------------------------

func _on_apply_pressed() -> void:
	_save_graphics()
	_save_audio()
	_save_controls()

	var err: Error = ConfigManager.save()
	if err != OK:
		status_label.text = "Save failed (error %d) -- see logs" % err
	else:
		status_label.text = "Settings saved."

	_apply_graphics_to_engine()
	_apply_audio_to_engine()


func _save_graphics() -> void:
	var res_text: String = resolution_option.get_item_text(resolution_option.selected)
	var size: Vector2i = resolution_to_size(res_text)
	if size.x > 0 and size.y > 0:
		ConfigManager.set_value("graphics", "resolution_x", size.x)
		ConfigManager.set_value("graphics", "resolution_y", size.y)

	ConfigManager.set_value("graphics", "fullscreen", fullscreen_check.button_pressed)
	ConfigManager.set_value("graphics", "vsync", vsync_check.button_pressed)
	ConfigManager.set_value("graphics", "max_fps", clamp_max_fps(int(max_fps_spinbox.value)))


func _save_audio() -> void:
	ConfigManager.set_value("audio", "master_volume", master_slider.value)
	ConfigManager.set_value("audio", "music_volume", music_slider.value)
	ConfigManager.set_value("audio", "sfx_volume", sfx_slider.value)
	ConfigManager.set_value("audio", "mute", mute_check.button_pressed)


func _save_controls() -> void:
	ConfigManager.set_value("controls", "mouse_sensitivity", sensitivity_slider.value)
	ConfigManager.set_value("controls", "invert_y", invert_y_check.button_pressed)
	# rebind_* keys are already written directly to ConfigManager as each
	# rebind is captured (see _input()); nothing left to do here.


## Reflects Graphics settings to the live engine. Guards every DisplayServer
## call behind a headless check -- CI / GUT runs have no window, so calling
## these would be meaningless (or error on some platforms); this keeps the
## screen usable in automated/headless contexts without crashing.
func _apply_graphics_to_engine() -> void:
	Engine.max_fps = clamp_max_fps(int(max_fps_spinbox.value))

	if DisplayServer.get_name() == "headless":
		GameLog.warn("[Settings] headless display server; skipping window mode/vsync/resolution apply")
		return

	var mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen_check.button_pressed else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)

	var vsync_mode: DisplayServer.VSyncMode = DisplayServer.VSYNC_ENABLED if vsync_check.button_pressed else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(vsync_mode)

	var size: Vector2i = resolution_to_size(resolution_option.get_item_text(resolution_option.selected))
	if size.x > 0 and size.y > 0 and mode == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_size(size)


## Reflects Audio settings to the live engine, one bus at a time. Degrades
## gracefully (GameLog.warn + skip, never crashes) when a bus by that name
## does not exist yet -- only Master is guaranteed to exist by default;
## Music/SFX need a bus layout resource that is not part of this card
## (see report to producer).
func _apply_audio_to_engine() -> void:
	_apply_volume_to_bus("Master", master_slider.value, mute_check.button_pressed)
	_apply_volume_to_bus("Music", music_slider.value, mute_check.button_pressed)
	_apply_volume_to_bus("SFX", sfx_slider.value, mute_check.button_pressed)


func _apply_volume_to_bus(bus_name: String, linear_value: float, muted: bool) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		GameLog.warn("[Settings] audio bus %s not found; skipping (bus layout not configured yet)" % bus_name)
		return
	AudioServer.set_bus_volume_db(bus_index, volume_to_db(linear_value))
	AudioServer.set_bus_mute(bus_index, muted)


func _on_back_pressed() -> void:
	var err: Error = get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	if err != OK:
		push_warning("[Settings] failed to switch to %s (error %d)" % [MAIN_MENU_SCENE, err])
		status_label.text = "Failed to return to menu (error %d)" % err


# --- pure / node-independent helpers (safe to unit test, tests/test_settings.gd) --

## Parses a WIDTHxHEIGHT resolution string (e.g. 1920x1080) into a
## Vector2i. Returns Vector2i.ZERO on anything malformed (missing x,
## non-numeric parts, zero/negative parts, empty string) -- callers should
## treat ZERO as keep-current-size, never crash on bad input.
static func resolution_to_size(text: String) -> Vector2i:
	var parts: PackedStringArray = text.to_lower().split("x")
	if parts.size() != 2:
		return Vector2i.ZERO
	if not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	var w: int = parts[0].to_int()
	var h: int = parts[1].to_int()
	if w <= 0 or h <= 0:
		return Vector2i.ZERO
	return Vector2i(w, h)


## Inverse of resolution_to_size(): formats a Vector2i as WIDTHxHEIGHT.
static func size_to_resolution_string(size: Vector2i) -> String:
	return "%dx%d" % [size.x, size.y]


## Clamps a requested max-fps to a sane range: 0 (Godot uncapped sentinel)
## stays 0, negative values are treated as 0, and anything above 1000 is
## capped at 1000 (guards against a stray huge value locking the engine loop).
static func clamp_max_fps(value: int) -> int:
	if value <= 0:
		return 0
	return min(value, 1000)


## Maps a linear volume slider value (0.0..1.0, per ConfigManager.DEFAULTS
## *_volume keys) to a dB value suitable for AudioServer.set_bus_volume_db().
## Floors at MIN_VOLUME_DB instead of returning -inf for 0/near-zero input
## (linear_to_db(0) == -inf, which AudioServer would accept but which is
## clearer to just clamp to a very-quiet-but-finite floor here).
static func volume_to_db(linear_value: float) -> float:
	var clamped: float = clamp(linear_value, 0.0, 1.0)
	if clamped <= 0.0001:
		return MIN_VOLUME_DB
	return max(linear_to_db(clamped), MIN_VOLUME_DB)


## Inverse of volume_to_db(): maps a dB value back to a 0.0..1.0 linear slider
## value (e.g. to initialize a slider from a value read from AudioServer).
## Anything at/below MIN_VOLUME_DB maps to 0.0.
static func db_to_volume(db_value: float) -> float:
	if db_value <= MIN_VOLUME_DB:
		return 0.0
	return clamp(db_to_linear(db_value), 0.0, 1.0)


## Strips the rebind_ prefix off a ConfigManager controls key to get the
## InputMap action name it controls, e.g. rebind_move_forward ->
## move_forward. Returns the input unchanged if it does not have the prefix.
static func rebind_key_to_action_name(rebind_key: String) -> String:
	if rebind_key.begins_with(REBIND_PREFIX):
		return rebind_key.substr(REBIND_PREFIX.length())
	return rebind_key


## Filters Godot built-in ui_ prefixed InputMap actions out of a full action
## list, returning only project-specific (gameplay) actions. Used to decide
## whether to show the Controls tab Phase 1 placeholder notice (i.e. the
## move/kick/tag actions from TK-P1-xx are not defined yet). Pure -- takes
## the action list as a parameter rather than calling InputMap itself, so it
## is unit-testable without touching the InputMap singleton.
static func filter_custom_input_actions(actions: Array) -> Array:
	var result: Array = []
	for action in actions:
		var action_name: String = str(action)
		if not action_name.begins_with("ui_"):
			result.append(action_name)
	return result
