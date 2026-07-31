extends SceneTree
## tests/net/spawn_probe_slowjoin_peer.gd
##
## Headless 2-instance regression probe for the TK-P2-30 grace-EXTENSION fix in
## networking/PlayerSpawner.gd (+ networking/ArenaBarrierRules.gd). Sibling of
## spawn_probe_together_peer.gd (the TK-P2-13 barrier happy-path probe); this one
## targets the specific S2 bug TK-P2-30 fixed: a slow/backgrounded-but-HEALTHY
## client that only reaches arena readiness AFTER the initial 8s grace window
## used to get force-disconnected by the barrier grace timer, even though it was
## alive and merely throttled (an occluded window's frame loop -- which drives
## both scene-load completion and the multiplayer poll/flush that sends the queued
## reliable _rpc_arena_ready packet -- is throttled hard by the OS compositor +
## vsync). With the fix, because that client is still connected at the ENet layer
## when the grace elapses, the host EXTENDS the grace instead of killing it, and
## the client spawns cleanly once it finally announces readiness.
##
## ORDERING (production host-FIRST, like the together probe, but the client
## arrives DELIBERATELY LATE): host + client connect in a "Waiting Room", the host
## enters TestArena first (arming the readiness barrier + its grace timer), and
## the client stays connected but does NOT enter the arena / send _rpc_arena_ready
## until CLIENT_ARENA_DELAY_SEC -- set PAST the real 8s ARENA_READY_GRACE_SEC so
## the host's first grace timeout fires while the client is still (legitimately)
## absent. The client is still connected at that moment, so the fix must EXTEND
## rather than force-disconnect; the client then enters, sends ready, and the
## barrier releases and spawns everyone. Against the pre-TK-P2-30 code this same
## ordering makes the host force-disconnect the client at the 8s grace -> the
## client never spawns / gets server_disconnected -> probe FAILs (verified both
## directions).
##
## What it asserts (see tests/net/run_spawn_probe_slowjoin.sh for the driver):
##   1. The client is NOT force-disconnected during the wait (server_disconnected
##      never fires on it -> FAIL fast if the old kill path ran).
##   2. After it finally enters, the CLIENT has its OWN named Player
##      (str(own_id), per the PlayerSpawner naming contract) under
##      TestArena/Players -- the extended barrier spawned it and it replicated.
##   3. That Player multiplayer authority is the client itself
##      (is_multiplayer_authority() == true) -- authority contract intact.
##   4. The HOST own Player (named "1") ALSO replicated to the client -- proves
##      the whole barrier group (not just the client) reached this peer.
##   5. The client Player replicated position is neither (0,0,0) nor the host
##      slot-0 position -- host-seeded spawn state arrived and ordering did not
##      stack anyone at the origin.
##   6. (driver-side) the host log shows the grace was EXTENDED and did NOT log a
##      force-disconnect of this client.
##
## Run directly with:
##   godot --headless --path <repo> -s res://tests/net/spawn_probe_slowjoin_peer.gd -- \
##     --role=host|client [--port=7781] [--timeout=45]
##
## Non-GUT (SceneTree -s script, same pattern as spawn_probe_peer.gd) --
## GUT -gdir=res://tests -ginclude_subdirs ignores it.

const DEFAULT_PORT := 7781
const DEFAULT_ADDRESS := "127.0.0.1"
const DEFAULT_TIMEOUT_SEC := 45.0
const TEST_ARENA_SCENE := "res://world/TestArena.tscn"
const CLIENT_START_DELAY_SEC := 0.5
# Host enters the arena almost immediately after the peer connects (arming the
# barrier + grace timer); the client stays connected but enters DELIBERATELY LATE
# -- past the real 8s ARENA_READY_GRACE_SEC -- so the host's first grace timeout
# fires while this still-connected client is legitimately absent, exercising the
# EXTEND path. CLIENT_ARENA_DELAY_SEC is kept well under the 32s hard cap
# (8s * (1 + 3 extensions)) so the barrier still releases within this session.
const HOST_ARENA_DELAY_SEC := 0.1
const CLIENT_ARENA_DELAY_SEC := 11.0
const SPAWN_CHECK_POLL_SEC := 0.5
const HOST_HOLD_SEC := 24.0

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
		print("[SLOWJOIN] ERROR invalid or missing --role= (expected host|client)")
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
		# If the OLD force-disconnect path runs, the host drops us at the 8s grace
		# and this fires -- FAIL fast rather than waiting out the whole timeout.
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
		print("[SLOWJOIN][host] ERROR host() failed with code %d" % err)
		_finish(1)
		return
	print("[SLOWJOIN][host] listening on port %d, waiting for client (Waiting Room)..." % port)


func _start_client_delayed(address: String, port: int) -> void:
	_after(CLIENT_START_DELAY_SEC, func() -> void:
		var err: int = _net.join(address, port)
		if err != OK:
			print("[SLOWJOIN][client] ERROR join() failed with code %d" % err)
			_finish(1)
			return
		print("[SLOWJOIN][client] connecting to %s:%d ..." % [address, port])
	)


func _on_host_peer_connected(id: int) -> void:
	print("[SLOWJOIN][host] peer %d connected in Waiting Room; entering arena FIRST, arming barrier + grace..." % id)
	if _entered_arena:
		return
	# Cache our id while the peer is still connected (get_unique_id() errors
	# after a disconnect, which happens when we quit at the end of HOST_HOLD).
	_own_id = _net.multiplayer.get_unique_id()
	_after(HOST_ARENA_DELAY_SEC, func() -> void:
		_enter_arena()
		_after(HOST_HOLD_SEC, func() -> void: _finish(0))
	)


func _on_host_peer_disconnected(id: int) -> void:
	# In the OLD (buggy) behavior the host force-disconnects this client at the 8s
	# grace; surface it loudly so the driver flags the regression even if timing
	# races the client-side detection.
	print("[SLOWJOIN][host] peer %d disconnected (if this is the slow client, the grace-extension fix did NOT hold)" % id)
	_finish(0)


func _on_client_connected() -> void:
	print("[SLOWJOIN][client] CONNECTED (Waiting Room); staying connected but entering arena LATE (%.1fs, past the 8s grace)..." % CLIENT_ARENA_DELAY_SEC)
	# Cache our id now, while connected -- polling later must not call
	# get_unique_id() once the host has gone away.
	_own_id = _net.multiplayer.get_unique_id()
	_after(CLIENT_ARENA_DELAY_SEC, _enter_arena)


func _on_client_failed() -> void:
	print("[SLOWJOIN][client] CONNECTION_FAILED")
	_finish(1)


func _on_client_server_disconnected() -> void:
	if _spawn_check_passed or _done:
		return
	print("[SLOWJOIN][client] FAIL force-disconnected by host before spawning (grace-extension fix did not hold -- this is exactly the TK-P2-30 bug)")
	_finish(1)


func _enter_arena() -> void:
	if _entered_arena:
		return
	_entered_arena = true
	var scene: PackedScene = load(TEST_ARENA_SCENE)
	_arena = scene.instantiate()
	root.add_child(_arena)
	current_scene = _arena
	print("[SLOWJOIN][%s] entered arena" % _role)

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
		print("[SLOWJOIN][client] own Player (name=%d) not present yet, waiting for the extended-barrier spawn to replicate..." % own_id)
		return

	if not own_player.is_multiplayer_authority():
		print("[SLOWJOIN][client] FAIL own Player exists but authority is not this client")
		_finish(1)
		return

	# nit5: the HOST own Player (named "1") must ALSO have replicated to this
	# client -- proves the whole barrier group reached us, not just our own
	# instance. Spawned in the same barrier batch, so poll until it lands.
	var host_player: Node3D = players_root.get_node_or_null("1") as Node3D
	if host_player == null:
		print("[SLOWJOIN][client] host Player (name=1) not present yet, waiting for barrier group to replicate...")
		return

	var pos: Vector3 = own_player.position
	var slot0: Vector3 = SpawnPointUtilScript.spawn_point(0)
	print("[SLOWJOIN][client] own_id=%d own_position=%s host_slot0=%s" % [own_id, pos, slot0])

	var pos_xz := Vector2(pos.x, pos.z)
	var slot0_xz := Vector2(slot0.x, slot0.z)
	const XZ_TOLERANCE := 0.5

	if pos_xz.distance_to(Vector2.ZERO) < XZ_TOLERANCE:
		print("[SLOWJOIN][client] still at origin (XZ), waiting for spawn state to land...")
		return
	if pos_xz.distance_to(slot0_xz) < XZ_TOLERANCE:
		print("[SLOWJOIN][client] FAIL own position stacked on host slot-0 (XZ)")
		_finish(1)
		return

	print("[SLOWJOIN][client] SLOWJOIN_PASS (late client survived the grace, barrier extended + spawned it cleanly, host Player replicated, client authority, no stack, no origin)")
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
	print("[SLOWJOIN][%s] TIMEOUT (spawn_check_passed=%s)" % [_role, _spawn_check_passed])
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
