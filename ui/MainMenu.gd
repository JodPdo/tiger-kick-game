extends Control
## MainMenu.gd
##
## Entry-point UI: lets a player Host a game or Join one by IP:Port.
## Talks to the `NetworkManager` autoload (owned by network-engineer, TK-P0-04).
## Contract (must not diverge without producer sign-off):
##   NetworkManager.DEFAULT_PORT : int
##   NetworkManager.host(port: int = DEFAULT_PORT) -> Error
##   NetworkManager.join(address: String = "127.0.0.1", port: int = DEFAULT_PORT) -> Error
##   signals: server_started, connection_succeeded, connection_failed, peer_connected(id)

const DEFAULT_ADDRESS: String = "127.0.0.1"
const DEFAULT_PORT: int = 7777
const DEFAULT_ADDRESS_PORT: String = "%s:%d" % [DEFAULT_ADDRESS, DEFAULT_PORT]

## Minimal test level (TK-P0-05). Host and client both switch here once the
## connection is confirmed by NetworkManager (server_started / connection_succeeded).
## Path per TDD §3 Folder Structure: res://world/ -- Arena, SafeCircle.
const TEST_ARENA_SCENE: String = "res://world/TestArena.tscn"

@onready var address_port_edit: LineEdit = $CenterContainer/VBoxContainer/AddressPortEdit
@onready var host_button: Button = $CenterContainer/VBoxContainer/ButtonRow/HostButton
@onready var join_button: Button = $CenterContainer/VBoxContainer/ButtonRow/JoinButton
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel


func _ready() -> void:
	address_port_edit.text = DEFAULT_ADDRESS_PORT
	status_label.text = ""

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)

	# NetworkManager is an autoload registered by the producer (TK-P0-04).
	# It is not registered yet while this card is authored; the connections
	# below will resolve at runtime once project.godot lists the autoload.
	NetworkManager.server_started.connect(_on_server_started)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)


func _on_host_pressed() -> void:
	var parsed: Dictionary = _parse_address_port(address_port_edit.text)
	var port: int = parsed.port
	status_label.text = "Hosting on port %d..." % port

	var err: Error = NetworkManager.host(port)
	if err != OK:
		status_label.text = "Host failed (error %d)" % err


func _on_join_pressed() -> void:
	var parsed: Dictionary = _parse_address_port(address_port_edit.text)
	var address: String = parsed.address
	var port: int = parsed.port
	status_label.text = "Joining %s:%d..." % [address, port]

	var err: Error = NetworkManager.join(address, port)
	if err != OK:
		status_label.text = "Join failed (error %d)" % err


## Parses a single "address:port" text field into { address: String, port: int }.
## Falls back to DEFAULT_ADDRESS / DEFAULT_PORT for any missing/invalid part.
## Uses the *last* colon as the separator so IPv6-style input degrades safely
## to "use default" rather than crashing (full IPv6 support is out of scope here).
func _parse_address_port(text: String) -> Dictionary:
	var address: String = DEFAULT_ADDRESS
	var port: int = DEFAULT_PORT

	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		return {"address": address, "port": port}

	var last_colon: int = trimmed.rfind(":")
	if last_colon == -1:
		address = trimmed
		return {"address": address, "port": port}

	var address_part: String = trimmed.substr(0, last_colon)
	var port_part: String = trimmed.substr(last_colon + 1)

	if not address_part.is_empty():
		address = address_part
	if port_part.is_valid_int():
		port = port_part.to_int()

	return {"address": address, "port": port}


func _on_server_started() -> void:
	status_label.text = "Server started. Waiting for players..."
	_switch_to_test_arena()


func _on_connection_succeeded() -> void:
	status_label.text = "Connected to server."
	_switch_to_test_arena()


func _on_connection_failed() -> void:
	status_label.text = "Connection failed."


## Switches from MainMenu to the TestArena once a connection is confirmed.
## Host reacts to `server_started`; client reacts to `connection_succeeded`.
## Does not touch project.godot's run/main_scene -- the game still boots into
## MainMenu; this is a runtime-only transition (TK-P0-05).
func _switch_to_test_arena() -> void:
	var err: Error = get_tree().change_scene_to_file(TEST_ARENA_SCENE)
	if err != OK:
		push_warning("[MENU] failed to switch to %s (error %d)" % [TEST_ARENA_SCENE, err])
		status_label.text = "Failed to load arena (error %d)" % err
