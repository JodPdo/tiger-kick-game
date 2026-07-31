extends SceneTree
## tests/net/spawn_probe_together_peer.gd
##
## Headless 2-instance regression probe for the TK-P2-13 readiness-BARRIER S1
## fix in networking/PlayerSpawner.gd. Sibling of spawn_probe_peer.gd, which
## proves the OLD staggered-connect spawn path (host enters the arena FIRST,
## client connects later so peer_connected drives its spawn). This probe
## proves the NEW Waiting Room -> Start Match path instead:
##
##   host + client are ALREADY connected (as in the Waiting Room), and only
##   THEN do BOTH enter TestArena. Every client peer_connected has already
##   fired before any PlayerSpawner existed and will NOT re-fire, so the ONLY
##   thing that can spawn a client own Player is the host-side readiness
##   BARRIER: the host spawns NOTHING (not even its own Player) until every
##   connected peer has announced its arena spawner exists (_rpc_arena_ready),
##   then spawns everyone at once. Without it, the host's early own-Player spawn
##   poisons the per-peer node-path cache toward the not-yet-arrived client, so
##   the client own later spawn is dropped permanently -> the client lands with
##   no Player -> S1.
##
## PRODUCTION (host-FIRST) ORDERING -- the ordering that was FAILING and that
## an earlier version of this probe got BACKWARDS: ui/WaitingRoom.gd
## _rpc_start_match() runs on the host synchronously via call_local, so the
## host deferred change_scene_to_file() is queued a frame (or more) BEFORE any
## client -- the HOST enters TestArena FIRST, the clients after. This probe
## reproduces exactly that: the host enters the arena on a SHORT delay after
## peer_connected, the client on a LONG delay after connection_succeeded. The
## host therefore holds the barrier until the client arrives and sends its
## ready-RPC, then spawns host + client together so both replicate cleanly.
## Against the pre-barrier code this same ordering lets the host spawn its own
## Player while the client is still absent -> the path cache is poisoned -> the
## client own spawn is dropped -> the client times out with
## spawn_check_passed=false (probe FAILs without the fix, PASSes with it --
## verified both directions).
##
## What it asserts (see tests/net/run_spawn_probe_together.sh for the driver):
##   1. After BOTH enter the arena, the CLIENT has its OWN named Player
##      (str(own_id), per the PlayerSpawner naming contract) under
##      TestArena/Players -- the barrier spawned it and it replicated.
##   2. That Player multiplayer authority is the client itself
##      (is_multiplayer_authority() == true) -- authority contract intact.
##   3. The HOST own Player (named "1") ALSO replicated to the client -- proves
##      the whole barrier group (not just the client) reached this peer.
##   4. The client Player replicated position is neither (0,0,0) nor the host
##      slot-0 position -- host-seeded spawn state arrived and ordering (host
##      slot 0, client slot 1) did not stack anyone at the origin.
##   5. No "ERROR" markers in either log.
##
## Run directly with:
##   godot --headless --path <repo> -s res://tests/net/spawn_probe_together_peer.gd -- \
##     --role=host|client [--port=7779] [--timeout=25]
##
## Non-GUT (SceneTree -s script, same pattern as spawn_probe_peer.gd) --
## GUT -gdir=res://tests -ginclude_subdirs ignores it.

const DEFAULT_PORT := 7779
const DEFAULT_ADDRESS := "127.0.0.1"
const DEFAULT_TIMEOUT_SEC := 25.0
const TEST_ARENA_SCENE := "res://world/TestArena.tscn"
const CLIENT_START_DELAY_SEC := 0.5
# Host enters the arena almost immediately after the peer connects; the client
# waits much longer, so the host PlayerSpawner is up (and host slot 0 already
# taken) before the client arrives -- exactly the host-FIRST production
# ordering the readiness handshake must survive.
const HOST_ARENA_DELAY_SEC := 0.1
const CLIENT_ARENA_DELAY_SEC := 2.5
const SPAWN_CHECK_POLL_SEC := 0.5
const HOST_HOLD_SEC := 12.0

const SpawnPointUtilScript := preload("res://networking/SpawnPointUtil.gd")

var _net: Node
var _role := ""
var _own_id := 0
var _done := false
var _arena: Node
var _entered_arena := false
var _spawn_check_passed := false


func _initialize() -> void:
	var args := _parse_args()
	_role = String(args.get("role", ""))

	if _role != "host" and _role != "client":
		print("[TOGETHER] ERROR invalid or missing --role= (expected host|client)")
		quit(1)
		return

	var port: int = int(args.get("port", DEFAULT_PORT))
	var timeout_sec: float = float(args.get("timeout", DEFAULT_TIMEOUT_SEC))

	await process_frame

	_net = _get_network_manager()
	_start_timeout(timeout_sec)

	if _role == "host":
		_net.peer_connected.connect(_on_host_peer_connected)
		_net.peer_disconnected.connect(_on_host_peer_disconnected)
		_start_host(port)
	else:
		_net.connection_succeeded.connect(_on_client_connected)
		_net.connection_failed.connect(_on_client_failed)
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
		print("[TOGETHER][host] ERROR host() failed with code %d" % err)
		_finish(1)
		return
	print("[TOGETHER][host] listening on port %d, waiting for client (Waiting Room)..." % port)


func _start_client_delayed(address: String, port: int) -> void:
	_after(CLIENT_START_DELAY_SEC, func() -> void:
		var err: int = _net.join(address, port)
		if err != OK:
			print("[TOGETHER][client] ERROR join() failed with code %d" % err)
			_finish(1)
			return
		print("[TOGETHER][client] connecting to %s:%d ..." % [address, port])
	)


func _on_host_peer_connected(id: int) -> void:
	print("[TOGETHER][host] peer %d connected in Waiting Room; entering arena FIRST (host-first prod ordering)..." % id)
	if _entered_arena:
		return
	# Cache our id while the peer is still connected (get_unique_id() errors
	# after a disconnect, which happens when we quit at the end of HOST_HOLD).
	_own_id = _net.multiplayer.get_unique_id()
	_after(HOST_ARENA_DELAY_SEC, func() -> void:
		_enter_arena()
		_after(HOST_HOLD_SEC, func() -> void: _finish(0))
	)


func _on_host_peer_disconnected(_id: int) -> void:
	_finish(0)


func _on_client_connected() -> void:
	print("[TOGETHER][client] CONNECTED (Waiting Room); entering arena LATER (after host)...")
	# Cache our id now, while connected -- polling later must not call
	# get_unique_id() once the host has gone away.
	_own_id = _net.multiplayer.get_unique_id()
	_after(CLIENT_ARENA_DELAY_SEC, _enter_arena)


func _on_client_failed() -> void:
	print("[TOGETHER][client] CONNECTION_FAILED")
	_finish(1)


func _enter_arena() -> void:
	if _entered_arena:
		return
	_entered_arena = true
	var scene: PackedScene = load(TEST_ARENA_SCENE)
	_arena = scene.instantiate()
	root.add_child(_arena)
	current_scene = _arena
	print("[TOGETHER][%s] entered arena" % _role)

	if _role == "client":
		_start_spawn_poll()


func _start_spawn_poll() -> void:
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


func _check_client_spawn() -> void:
	var own_id: int = _own_id
	var players_root: Node = root.get_node_or_null("TestArena/Players")
	if players_root == null:
		return

	var own_player: Node3D = players_root.get_node_or_null(str(own_id)) as Node3D
	if own_player == null:
		print("[TOGETHER][client] own Player (name=%d) not present yet, waiting for handshake spawn to replicate..." % own_id)
		return

	if not own_player.is_multiplayer_authority():
		print("[TOGETHER][client] FAIL own Player exists but authority is not this client")
		_finish(1)
		return

	# nit5: the HOST own Player (named "1") must ALSO have replicated to this
	# client -- proves the whole barrier group reached us, not just our own
	# instance. Spawned in the same barrier batch, so poll until it lands.
	var host_player: Node3D = players_root.get_node_or_null("1") as Node3D
	if host_player == null:
		print("[TOGETHER][client] host Player (name=1) not present yet, waiting for barrier group to replicate...")
		return

	var pos: Vector3 = own_player.position
	var slot0: Vector3 = SpawnPointUtilScript.spawn_point(0)
	print("[TOGETHER][client] own_id=%d own_position=%s host_slot0=%s" % [own_id, pos, slot0])

	var pos_xz := Vector2(pos.x, pos.z)
	var slot0_xz := Vector2(slot0.x, slot0.z)
	const XZ_TOLERANCE := 0.5

	if pos_xz.distance_to(Vector2.ZERO) < XZ_TOLERANCE:
		print("[TOGETHER][client] still at origin (XZ), waiting for spawn state to land...")
		return
	if pos_xz.distance_to(slot0_xz) < XZ_TOLERANCE:
		print("[TOGETHER][client] FAIL own position stacked on host slot-0 (XZ)")
		_finish(1)
		return

	print("[TOGETHER][client] SPAWN_TOGETHER_PASS (own Player barrier-spawned, host Player replicated, client authority, no stack, no origin)")
	_spawn_check_passed = true
	_finish(0)


func _after(delay_sec: float, cb: Callable) -> void:
	var t := Timer.new()
	t.wait_time = delay_sec
	t.one_shot = true
	root.add_child(t)
	t.timeout.connect(func() -> void:
		cb.call()
		t.queue_free()
	)
	t.start()


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
	print("[TOGETHER][%s] TIMEOUT (spawn_check_passed=%s)" % [_role, _spawn_check_passed])
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
