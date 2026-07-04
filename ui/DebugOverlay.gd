extends CanvasLayer
## DebugOverlay (autoload singleton) -- registered in project.godot as
## DebugOverlay (line reported to the producer, see TK-PX-02 handoff; this
## agent does not edit project.godot).
##
## A globally available F3-toggled debug HUD: FPS / ping / state (current
## scene, network role, peer count). Implemented as an autoload CanvasLayer
## (rather than a per-scene .tscn) so it is present in every scene --
## MainMenu, TestArena, and every future scene -- without each scene needing
## to instance it. `layer = 100` keeps it drawn above normal game UI.
##
## Hidden by default; F3 flips visibility (raw InputEventKey check in
## _input(), NOT an InputMap action -- avoids touching project.godot per the
## card's constraint; see the handoff report if an action is preferred
## instead).
##
## Design goal (testability, per TK-PX-02): the *text-building* logic
## (`format_overlay`) is a pure, static, node-independent function operating
## on plain fps/ping_ms/state values -- no Node/Performance/multiplayer
## access -- so GUT can test it directly (tests/test_debug_overlay.gd). Only
## the instance methods below touch Performance/Engine/multiplayer/the scene
## tree, and they degrade gracefully (never crash) when offline or when a
## multiplayer peer is missing/incompatible.
##
## Reference: Tiger_Kick_Project_Docs/02_Technical/TDD.pdf §3 (managers/ +
## debug tooling). Uses GameLog.debug() (not raw print()) for the toggle
## on/off notice, per project convention (see managers/Logger.gd).

## Refresh cadence: ~4x/sec, per the card ("not every frame").
const REFRESH_INTERVAL_SEC: float = 0.25

## Sentinel returned by _compute_ping_ms() / accepted by format_overlay()
## when a ping figure isn't available (offline, no multiplayer peer, peer
## not fully connected, or a non-ENet peer). Rendered as "n/a".
const PING_UNAVAILABLE: int = -1

var _label: Label = null
var _refresh_timer: Timer = null


func _ready() -> void:
	layer = 100
	visible = false
	_build_ui()
	_start_refresh_timer()
	_refresh() # populate text immediately so the first F3 toggle shows fresh data, not a blank label


## Builds the on-screen Label as a plain code-built child (no separate
## DebugOverlay.tscn / theme asset needed) -- keeps this autoload
## self-contained in a single script file.
func _build_ui() -> void:
	_label = Label.new()
	_label.name = "DebugOverlayLabel"
	_label.position = Vector2(8, 8)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_font_size_override("font_size", 16)
	add_child(_label)


## Starts the ~4x/sec refresh timer (avoids recomputing FPS/ping/state every
## frame, per the card).
func _start_refresh_timer() -> void:
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = REFRESH_INTERVAL_SEC
	_refresh_timer.one_shot = false
	_refresh_timer.autostart = true
	_refresh_timer.timeout.connect(_refresh)
	add_child(_refresh_timer)


## Raw key check (per the card): F3 toggles visibility. Deliberately NOT an
## InputMap action, so no project.godot edit is required. `not event.echo`
## avoids re-toggling repeatedly while the key is held down.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_F3 and event.pressed and not event.echo:
		_toggle()


func _toggle() -> void:
	visible = not visible
	GameLog.debug("[DebugOverlay] toggled %s" % ("ON" if visible else "OFF"))
	if visible:
		_refresh() # show fresh numbers immediately, don't wait for the next timer tick


## Instance-side entry point: gathers live FPS/ping/state and rewrites the
## label text via the pure format_overlay(). Called on a timer, not every
## frame.
func _refresh() -> void:
	if _label == null:
		return
	var fps: int = Engine.get_frames_per_second()
	var ping_ms: int = _compute_ping_ms()
	var state: Dictionary = _gather_state()
	_label.text = format_overlay(fps, ping_ms, state)


## Best-effort snapshot of "state": current scene name, network role
## (host/client/offline), and peer count (including the host itself when we
## are the host). Never crashes when offline -- falls back to
## scene "n/a" / role "offline" / peer_count 0.
func _gather_state() -> Dictionary:
	var scene_name: String = "n/a"
	var tree: SceneTree = get_tree()
	if tree != null and tree.current_scene != null:
		scene_name = tree.current_scene.name

	var role: String = "offline"
	var peer_count: int = 0
	var mp: MultiplayerAPI = multiplayer
	if mp != null and mp.has_multiplayer_peer():
		role = "host" if mp.is_server() else "client"
		peer_count = mp.get_peers().size()
		if mp.is_server():
			peer_count += 1 # include the host itself in the headcount

	return {
		"scene": scene_name,
		"role": role,
		"peer_count": peer_count,
	}


## Best-effort round-trip time in ms via ENetMultiplayerPeer/ENetPacketPeer
## statistics. Returns PING_UNAVAILABLE (-1) -- never crashes -- when
## offline, not yet connected, or on a non-ENet peer (e.g. no peer set,
## or a future transport). A client reports RTT to the host (peer id 1,
## always the host under NetworkManager's server-authoritative model); a
## host reports RTT to its first connected peer as a single representative
## figure (multi-peer per-client ping breakdown is out of scope for this
## card).
func _compute_ping_ms() -> int:
	var mp: MultiplayerAPI = multiplayer
	if mp == null or not mp.has_multiplayer_peer():
		return PING_UNAVAILABLE

	var peer: MultiplayerPeer = mp.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return PING_UNAVAILABLE
	if not (peer is ENetMultiplayerPeer):
		return PING_UNAVAILABLE

	var enet_peer: ENetMultiplayerPeer = peer as ENetMultiplayerPeer
	var target_id: int = 1 # host's peer id is always 1 (client's best-effort target)
	if mp.is_server():
		var peers: PackedInt32Array = mp.get_peers()
		if peers.is_empty():
			return PING_UNAVAILABLE
		target_id = peers[0]

	var enet_packet_peer: ENetPacketPeer = enet_peer.get_peer(target_id)
	if enet_packet_peer == null:
		return PING_UNAVAILABLE
	return int(enet_packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))


## Pure formatting logic: builds the overlay's single display line from
## already-computed values. No Node/Performance/multiplayer/Engine access --
## safe to unit test directly (tests/test_debug_overlay.gd).
##
## `ping_ms == PING_UNAVAILABLE` (-1) renders as "n/a" instead of a bogus
## number -- this is how offline/disconnected state is shown without
## crashing.
##
## `state` keys (all optional, defaults shown if missing):
##   "scene": String (default "n/a")       -- current scene name
##   "role": String (default "offline")     -- "host" | "client" | "offline"
##   "peer_count": int (default 0)          -- connected peers (host counts itself)
static func format_overlay(fps: int, ping_ms: int, state: Dictionary) -> String:
	var scene_name: String = state.get("scene", "n/a")
	var role: String = state.get("role", "offline")
	var peer_count: int = state.get("peer_count", 0)
	var ping_str: String = "n/a" if ping_ms == PING_UNAVAILABLE else "%d ms" % ping_ms
	return "FPS: %d | Ping: %s | Scene: %s | Role: %s | Peers: %d" % [fps, ping_str, scene_name, role, peer_count]
