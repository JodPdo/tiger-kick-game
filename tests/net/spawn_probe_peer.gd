extends SceneTree
## tests/net/spawn_probe_peer.gd
##
## Headless 2-instance regression probe for TK-BUG-P1-01 (spawn stacking /
## pending-spawn engine error) and TK-BUG-P1-02 (host-quit -> client stuck).
## Seed for TK-P1-07 (full ci.yml integration). Unlike net_smoke_peer.gd
## (connection-only), this drives the FULL TestArena scene (NetworkManager +
## PlayerSpawner + Player) over real ENet on localhost.
##
## What it asserts (see tests/net/run_spawn_probe.sh for the driver):
##   1. (TK-BUG-P1-01) the CLIENT own spawned Player lands at a position
##      that is neither (0,0,0) nor the host slot-0 spawn position -- i.e.
##      the host-seeded MultiplayerSpawner spawn state actually arrived,
##      instead of being silently discarded by a too-late authority change
##      (Player._enter_tree() now sets authority before _ready(), see
##      characters/Player.gd).
##   2. No "ERROR" lines (and specifically no "unable to process the pending
##      spawn" engine error) appear in either log.
##   3. (TK-BUG-P1-02) once the driver kills the host process, the client
##      NetworkManager fires server_disconnected and TestArena.gd handler
##      runs (both print distinct, greppable log lines).
##
## Run directly with:
##   godot --headless --path <repo> -s res://tests/net/spawn_probe_peer.gd -- \
##     --role=host|client [--port=7777] [--timeout=20]
## See tests/net/run_spawn_probe.sh, which launches host+client, waits for
## the client spawn check to pass, then kills the host to exercise the
## disconnect path.
##
## Non-GUT (SceneTree `-s` script, same pattern as net_smoke_peer.gd) --
## GUT -gdir=res://tests -ginclude_subdirs ignores it.

const DEFAULT_PORT := 7777
const DEFAULT_ADDRESS := "127.0.0.1"
const DEFAULT_TIMEOUT_SEC := 20.0
const TEST_ARENA_SCENE := "res://world/TestArena.tscn"
const CLIENT_START_DELAY_SEC := 0.5
# How often to poll the client own Player position after connecting, until
# it either passes the spawn check or the overall --timeout is hit.
const SPAWN_CHECK_POLL_SEC := 0.5

const SpawnPointUtilScript := preload("res://networking/SpawnPointUtil.gd")

var _net: Node
var _role := ""
var _done := false
var _arena: Node
var _spawn_check_passed := false


func _initialize() -> void:
	var args := _parse_args()
	_role = String(args.get("role", ""))

	if _role != "host" and _role != "client":
		print("[PROBE] ERROR invalid or missing --role= (expected host|client)")
		quit(1)
		return

	var port: int = int(args.get("port", DEFAULT_PORT))
	var timeout_sec: float = float(args.get("timeout", DEFAULT_TIMEOUT_SEC))

	# See net_smoke_peer.gd: root is not fully attached yet during
	# _initialize(); defer real setup to the first idle frame.
	await process_frame

	_net = _get_network_manager()
	_start_timeout(timeout_sec)

	if _role == "host":
		_start_host(port)
	else:
		_net.connection_succeeded.connect(_on_client_connected)
		_net.connection_failed.connect(_on_client_failed)
		_net.server_disconnected.connect(_on_client_server_disconnected)
		_start_client_delayed(DEFAULT_ADDRESS, port)


func _get_network_manager() -> Node:
	var existing := root.get_node_or_null("NetworkManager")
	if existing:
		return existing
	var script: GDScript = load("res://networking/NetworkManager.gd")
	var node: Node = script.new()
	node.name = "NetworkManager"
	root.add_child(node)
	return node


func _start_host(port: int) -> void:
	var err: int = _net.host(port)
	if err != OK:
		print("[PROBE][host] ERROR host() failed with code %d" % err)
		_finish(1)
		return
	print("[PROBE][host] listening on port %d, loading arena..." % port)
	_load_arena()


func _start_client_delayed(address: String, port: int) -> void:
	var delay_timer := Timer.new()
	delay_timer.wait_time = CLIENT_START_DELAY_SEC
	delay_timer.one_shot = true
	root.add_child(delay_timer)
	delay_timer.timeout.connect(func() -> void:
		var err: int = _net.join(address, port)
		if err != OK:
			print("[PROBE][client] ERROR join() failed with code %d" % err)
			_finish(1)
			return
		print("[PROBE][client] connecting to %s:%d ..." % [address, port])
	)
	delay_timer.start()


func _on_client_connected() -> void:
	print("[PROBE][client] CONNECTED, loading arena...")
	_load_arena()


func _on_client_failed() -> void:
	print("[PROBE][client] CONNECTION_FAILED")
	_finish(1)


## Loads TestArena the same way MainMenu does (res://world/TestArena.tscn),
## as the tree current_scene, so PlayerSpawner._ready() is_server() check
## and TestArena.gd own _ready() (server_disconnected wiring) run exactly
## as they would in the real game. current_scene is set explicitly (instead
## of via change_scene_to_file, which expects an existing current_scene to
## replace) so TestArena.gd later change_scene_to_file(MainMenu) call has a
## valid scene to swap out.
func _load_arena() -> void:
	var scene: PackedScene = load(TEST_ARENA_SCENE)
	_arena = scene.instantiate()
	root.add_child(_arena)
	current_scene = _arena

	if _role == "client":
		var poll_timer := Timer.new()
		poll_timer.wait_time = SPAWN_CHECK_POLL_SEC
		poll_timer.one_shot = false
		root.add_child(poll_timer)
		poll_timer.timeout.connect(func() -> void:
			if _spawn_check_passed or _done:
				poll_timer.stop()
				return
			_check_client_spawn()
		)
		poll_timer.start()


## TK-BUG-P1-01 core assertion: read back this CLIENT own Player node
## (named str(own_id) per PlayerSpawner naming contract) and confirm its
## replicated spawn position is neither the origin nor the host slot-0
## position -- either of which would mean the host-seeded spawn state was
## discarded (the exact symptom the audit found).
func _check_client_spawn() -> void:
	var own_id: int = _net.multiplayer.get_unique_id()
	var players_root: Node = root.get_node_or_null("TestArena/Players")
	if players_root == null:
		print("[PROBE][client] ERROR Players root not found under TestArena")
		_finish(1)
		return

	var own_player: Node3D = players_root.get_node_or_null(str(own_id)) as Node3D
	if own_player == null:
		print("[PROBE][client] ERROR own Player node (name=%d) not found under Players" % own_id)
		_finish(1)
		return

	var pos: Vector3 = own_player.position
	var slot0: Vector3 = SpawnPointUtilScript.spawn_point(0)
	print("[PROBE][client] own_id=%d own_position=%s host_slot0=%s" % [own_id, pos, slot0])

	# IMPORTANT (review nit #1): compare on the XZ plane ONLY, never full
	# Vector3. Gravity settles the Player's Y within ~0.45s, so a REGRESSED
	# client actually stuck at the origin reads as (0, ~0.04, 0), not exactly
	# Vector3.ZERO -- a full-Vector3 is_equal_approx would then be false and
	# the probe would FALSE-PASS the very S1 bug it exists to catch (the
	# silent "spawn state never arrived" variant). XZ is where SpawnPointUtil
	# actually places players; Y is gravity's business and irrelevant here.
	var pos_xz := Vector2(pos.x, pos.z)
	var origin_xz := Vector2.ZERO
	var slot0_xz := Vector2(slot0.x, slot0.z)
	const XZ_TOLERANCE := 0.5

	if pos_xz.distance_to(origin_xz) < XZ_TOLERANCE:
		print("[PROBE][client] still at origin (XZ), waiting for spawn state to land...")
		return
	if pos_xz.distance_to(slot0_xz) < XZ_TOLERANCE:
		print("[PROBE][client] FAIL own position stacked on host slot-0 position (XZ)")
		_finish(1)
		return

	print("[PROBE][client] SPAWN_CHECK_PASS (no stack, no origin)")
	_spawn_check_passed = true
	# Deliberately do NOT quit here -- stay alive so the driver can kill the
	# host process and we can observe the TK-BUG-P1-02 disconnect path below
	# (bounded by the overall --timeout started in _initialize()).


## TK-BUG-P1-02: fires once NetworkManager detects the host connection is
## lost (driver kills the host process). TestArena.gd (already in the tree,
## added in _load_arena() above) independently reacts to the same signal and
## logs its own "[NET] host disconnected -- returning to MainMenu" line via
## GameLog -- this print is this probe own independent confirmation that
## the signal reached listeners, kept separate from TestArena line so the
## driver has two distinct markers to grep.
func _on_client_server_disconnected() -> void:
	print("[PROBE][client] SERVER_DISCONNECTED_SIGNAL_FIRED")
	_finish(0 if _spawn_check_passed else 1)


func _start_timeout(timeout_sec: float) -> void:
	var timeout_timer := Timer.new()
	timeout_timer.wait_time = timeout_sec
	timeout_timer.one_shot = true
	root.add_child(timeout_timer)
	timeout_timer.timeout.connect(_on_timeout)
	timeout_timer.start()


func _on_timeout() -> void:
	if _done:
		return
	print("[PROBE][%s] TIMEOUT (spawn_check_passed=%s)" % [_role, _spawn_check_passed])
	_finish(1)


func _finish(code: int) -> void:
	if _done:
		return
	_done = true
	quit(code)


func _parse_args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var stripped: String = arg.substr(2)
		var eq_idx: int = stripped.find("=")
		if eq_idx == -1:
			result[stripped] = true
			continue
		var key: String = stripped.substr(0, eq_idx)
		var value: String = stripped.substr(eq_idx + 1)
		result[key] = value
	return result
