extends SceneTree
## tests/net/net_smoke_peer.gd
##
## Headless network smoke-test entrypoint for TK-P0-06 (Phase 0 Exit Gate:
## "two instances connect + log confirms peer joined").
##
## Run directly (never via the normal game) with:
##   godot --headless --path <repo> -s res://tests/net/net_smoke_peer.gd -- \
##     --role=host|client [--port=7777] [--address=127.0.0.1] [--timeout=10]
## See tests/net/run_net_smoke.sh, which launches one process per role, both
## bound to localhost.
##
## Drives NetworkManager.host() / NetworkManager.join() over ENet and prints
## a unique "[SMOKE]"-prefixed marker on success/failure/timeout so the
## driver script can grep both this marker and NetworkManager's own
## "[NET]"-prefixed log lines for the Exit Gate evidence.
##
## Standalone entrypoint only -- this script is not referenced by
## run/main_scene and is not loaded by anything else in the project.
##
## Autoload note: NetworkManager is registered as an autoload in
## project.godot. Autoloads ARE instantiated under `-s` script mode (Godot
## attaches them under the SceneTree root as part of project init, before
## the main-loop script runs -- verified against this project's Godot 4.7
## build). We look it up at /root/NetworkManager first; if for any reason it
## is not present (e.g. this script is ever run outside this project's
## autoload config), we fall back to instancing NetworkManager.gd manually
## and adding it under root so its _ready() signal wiring still runs.

const DEFAULT_PORT := 7777
const DEFAULT_ADDRESS := "127.0.0.1"
const DEFAULT_TIMEOUT_SEC := 10.0
const CLIENT_START_DELAY_SEC := 0.5
# ENet's own connection-succeeded signal fires as soon as the *local* side of
# the handshake completes; the server still needs to receive/process a final
# handshake packet before it fires its own `peer_connected`. Quitting (and
# tearing down the ENet socket) the instant our own success signal fires can
# race that in-flight packet on a freshly-launched process. This fixed grace
# period gives both sides time to fully settle before either process exits.
const SUCCESS_GRACE_PERIOD_SEC := 1.5

var _net: Node
var _role := ""
var _done := false
var _succeeded := false


func _initialize() -> void:
	var args := _parse_args()
	_role = String(args.get("role", ""))

	if _role != "host" and _role != "client":
		print("[SMOKE] ERROR invalid or missing --role= (expected host|client)")
		quit(1)
		return

	var port: int = int(args.get("port", DEFAULT_PORT))
	var address: String = String(args.get("address", DEFAULT_ADDRESS))
	var timeout_sec: float = float(args.get("timeout", DEFAULT_TIMEOUT_SEC))

	# `_initialize()` runs before `root` is fully attached to the tree (Timer
	# nodes added here fail with "not inside the scene tree", and the
	# NetworkManager autoload's `multiplayer` proxy isn't resolvable yet
	# either). Deferring the real setup to the first idle frame via
	# `await process_frame` sidesteps that startup-ordering gotcha.
	await process_frame

	_net = _get_network_manager()

	_start_timeout(timeout_sec)

	if _role == "host":
		_net.peer_connected.connect(_on_host_peer_connected)
		_start_host(port)
	else:
		_net.connection_succeeded.connect(_on_client_connected)
		_net.connection_failed.connect(_on_client_failed)
		_start_client_delayed(address, port)


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
		print("[SMOKE][host] ERROR host() failed with code %d" % err)
		_finish(1)
		return
	print("[SMOKE][host] listening on port %d, waiting for peer..." % port)


func _start_client_delayed(address: String, port: int) -> void:
	# Small fixed head start so the client's create_client() call isn't
	# racing the host's create_server() call across two freshly-launched
	# processes. ENet itself handles the actual connection handshake once
	# both peers are up -- this is a bounded, deterministic delay, not a
	# flaky sleep-and-hope retry.
	var delay_timer := Timer.new()
	delay_timer.wait_time = CLIENT_START_DELAY_SEC
	delay_timer.one_shot = true
	root.add_child(delay_timer)
	delay_timer.timeout.connect(func() -> void:
		var err: int = _net.join(address, port)
		if err != OK:
			print("[SMOKE][client] ERROR join() failed with code %d" % err)
			_finish(1)
			return
		print("[SMOKE][client] connecting to %s:%d ..." % [address, port])
	)
	delay_timer.start()


func _start_timeout(timeout_sec: float) -> void:
	var timeout_timer := Timer.new()
	timeout_timer.wait_time = timeout_sec
	timeout_timer.one_shot = true
	root.add_child(timeout_timer)
	timeout_timer.timeout.connect(_on_timeout)
	timeout_timer.start()


func _on_host_peer_connected(id: int) -> void:
	if _done or _succeeded:
		return
	_succeeded = true
	print("[SMOKE][host] PEER_JOINED id=%d" % id)
	_finish_after_grace(0)


func _on_client_connected() -> void:
	if _done or _succeeded:
		return
	_succeeded = true
	print("[SMOKE][client] CONNECTED")
	_finish_after_grace(0)


func _on_client_failed() -> void:
	if _done or _succeeded:
		return
	print("[SMOKE][client] CONNECTION_FAILED")
	_finish(1)


func _on_timeout() -> void:
	if _done or _succeeded:
		return
	print("[SMOKE][%s] TIMEOUT" % _role)
	_finish(1)


func _finish_after_grace(code: int) -> void:
	var grace_timer := Timer.new()
	grace_timer.wait_time = SUCCESS_GRACE_PERIOD_SEC
	grace_timer.one_shot = true
	root.add_child(grace_timer)
	grace_timer.timeout.connect(func() -> void:
		_finish(code)
	)
	grace_timer.start()


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
