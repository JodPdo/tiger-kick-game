extends SceneTree
## tests/net/tag_detect_probe_peer.gd
##
## TK-P2-24 headless 2-instance probe for the Tag detection GLUE (TK-P2-02)
## that GUT cannot cover -- see characters/components/TagDetectorComponent.gd
## class doc's own "RESIDUAL GLUE GAP" note and this card. TagRules.gd's pure
## decision logic is fully GUT-covered (17 asserts); this probe exercises the
## three behaviors that only exist with a live scene tree + two real
## networked peers:
##   (a) a real Area3D body_entered/body_exited fires across two peers against
##       REPLICATED positions (not just local single-peer physics);
##   (b) the HOST-ONLY-EMIT gate holds: tag_target_in_range/
##       tag_target_left_range fire on the HOST process only, never on the
##       CLIENT, for the SAME overlap -- proven, not assumed: the client
##       independently confirms via get_candidates_in_range() (gate-free) that
##       its own local physics DID detect the overlap, while its signal
##       listener never fires;
##   (c) the despawn/ghost edge: a peer that is in range disconnects -> the
##       host's get_candidates_in_range() afterward contains NO stale entry
##       for the gone peer and produces no engine error reading a freed body.
##
## Sibling of tests/net/spawn_probe_together_peer.gd -- reuses its exact
## host-first barrier-flow structure (both peers already connected in a
## "Waiting Room", then enter res://world/TestArena.tscn together, host
## first) to get host + client each spawned with their own authoritative
## Player under TestArena/Players, host slot 0 / client slot 1 (per
## networking/SpawnPointUtil.gd -- about 3.06 m apart on the spawn circle,
## already OUT of tag_range_m's 2.0 m default, so nothing is in range until
## this probe moves them).
##
## IN-RANGE MECHANISM (headless has no input, so movement cannot come from
## Input actions -- see this card's "How the probe must work"): the HOST is
## the multiplayer authority of its OWN Player (Player._enter_tree(), node
## name == str(peer_id)) -- MovementComponent's _physics_process() already
## returns immediately for any non-authority Player (TK-P1-06 invariant), so
## directly writing `host_player.position` on the HOST process is the
## authority-safe way to move it: no cross-authority write, no RPC, nothing a
## production system would reject. The client's Player position is already
## visible locally on the host (replicated via MultiplayerSynchronizer,
## channel A, same as any other peer's ordinary movement) -- once both
## Players are confirmed present, the HOST teleports its OWN Player to
## `client_player.position + Vector3(TAG_OFFSET_M, 0, 0)`, a fixed offset
## chosen to land well within tag_range_m (2.0 m) while still being larger
## than the sum of both CharacterBody3D capsule radii (0.4 m each, see
## characters/Player.tscn) so the two capsules do not directly overlap/shove
## each other via move_and_slide.
##
## FALSIFIABILITY (per the card -- the TK-P2-13 lesson was that a probe
## hard-coding the friendly path proves nothing):
##   (a) shrinking TAG_OFFSET_M's effective distance past tag_range_m (or
##       breaking replication) makes this probe time out -- TAG_IN_RANGE_
##       HOST_PASS never prints. Demonstrated during development: bumping
##       TAG_OFFSET_M to 5.0 (outside range) reproducibly timed the probe out
##       (TAGPROBE FAIL, no TAG_IN_RANGE_HOST_PASS); reverted to the in-range
##       value below. See this card's HANDOFF note.
##   (b) deleting TagDetectorComponent's `if not multiplayer.is_server():
##       return` gate in _on_body_entered/_on_body_exited makes the CLIENT
##       process's own detector emit tag_target_in_range locally, so this
##       probe's client-side listener fires -- FAIL (TAGPROBE_CLIENT_EMIT_
##       FAIL). Demonstrated during development: with the gate temporarily
##       stubbed out, the client DID emit and this probe FAILed; reverted.
##       See this card's HANDOFF note for the exact diff tested.
##   (c) removing PlayerSpawner._on_peer_disconnected()'s existing
##       queue_free() cleanup of the departed peer's Player node would leave
##       the host's get_candidates_in_range() returning a stale entry for the
##       gone peer indefinitely -- FAIL (TAGPROBE_DESPAWN_STALE_FAIL). NOT
##       executed live against PlayerSpawner.gd (network-engineer-owned
##       production file, out of tools-devops edit scope per CLAUDE.md/this
##       agent's role) -- argued here rather than demonstrated; see HANDOFF
##       note.
##
## Run directly with:
##   godot --headless --path <repo> -s res://tests/net/tag_detect_probe_peer.gd -- \
##     --role=host|client [--port=7780] [--timeout=35]
##
## Non-GUT (SceneTree -s script, same pattern as the other tests/net/*_peer.gd
## probes) -- GUT -gdir=res://tests -ginclude_subdirs ignores it.

const DEFAULT_PORT := 7780
const DEFAULT_ADDRESS := "127.0.0.1"
const DEFAULT_TIMEOUT_SEC := 35.0
const TEST_ARENA_SCENE := "res://world/TestArena.tscn"
const CLIENT_START_DELAY_SEC := 0.5
# Same host-first ordering as spawn_probe_together_peer.gd (see that file's
# own doc for why): the host enters the arena almost immediately after the
# peer connects; the client waits much longer, so the host PlayerSpawner (and
# host slot 0) is up before the client arrives -- production ordering.
const HOST_ARENA_DELAY_SEC := 0.1
const CLIENT_ARENA_DELAY_SEC := 2.5
const PLAYERS_POLL_SEC := 0.3
# Offset applied to the client's replicated position to place the host's own
# Player within tag range: must be < tag_range_m (2.0, TagDetectorComponent's
# default) and > the sum of both CharacterBody3D capsule radii (0.4 + 0.4,
# Player.tscn) so move_and_slide() does not fight a direct capsule overlap.
const TAG_OFFSET_M := 1.0
const IN_RANGE_CHECK_TIMEOUT_SEC := 10.0
# How long the client keeps polling with NO emitted signal, after its own
# gate-free get_candidates_in_range() first confirms local overlap, before
# declaring the host-only-emit gate held. Not a race with the host: the
# client's own local physics detects the SAME overlap independently of
# anything the host does after teleporting.
const CLIENT_NO_EMIT_GRACE_SEC := 1.5
const DESPAWN_POLL_SEC := 0.3
const DESPAWN_CHECK_TIMEOUT_SEC := 8.0
const HOST_FINAL_HOLD_SEC := 1.0

const SpawnPointUtilScript := preload("res://networking/SpawnPointUtil.gd")

var _net: Node
var _role := ""
var _own_id := 0
var _done := false
var _arena: Node
var _entered_arena := false
var _players_root: Node

# -- host-only state ----------------------------------------------------------
var _host_player: Node3D
var _client_player: Node3D
var _client_id := 0
var _host_tag_detector: Area3D
var _host_saw_in_range := false
var _host_players_poll: Timer
var _host_in_range_deadline: Timer
var _host_despawn_poll: Timer
var _host_despawn_deadline: Timer
var _despawn_check_started := false

# -- client-only state ---------------------------------------------------------
var _client_tag_detector: Area3D
var _client_saw_local_overlap := false
var _client_no_emit_since := 0.0
var _client_poll: Timer


func _initialize() -> void:
	var args := _parse_args()
	_role = String(args.get("role", ""))

	if _role != "host" and _role != "client":
		print("[TAGPROBE] ERROR invalid or missing --role= (expected host|client)")
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
		print("[TAGPROBE][host] ERROR host() failed with code %d" % err)
		_finish(1)
		return
	print("[TAGPROBE][host] listening on port %d, waiting for client (Waiting Room)..." % port)


func _start_client_delayed(address: String, port: int) -> void:
	_after(CLIENT_START_DELAY_SEC, func() -> void:
		var err: int = _net.join(address, port)
		if err != OK:
			print("[TAGPROBE][client] ERROR join() failed with code %d" % err)
			_finish(1)
			return
		print("[TAGPROBE][client] connecting to %s:%d ..." % [address, port])
	)


func _on_host_peer_connected(id: int) -> void:
	print("[TAGPROBE][host] peer %d connected in Waiting Room; entering arena FIRST (host-first prod ordering)..." % id)
	if _entered_arena:
		return
	_own_id = _net.multiplayer.get_unique_id()
	_after(HOST_ARENA_DELAY_SEC, func() -> void:
		_enter_arena()
	)


## The despawn/ghost edge (c): fires when the client's peer connection drops
## (the driver kills the client process). Only meaningful once the in-range
## assertions (a)/(b) already passed -- if the client vanished before that,
## the ordering the driver promises was violated and this run proves nothing,
## so that is treated as a hard FAIL rather than a silent skip.
func _on_host_peer_disconnected(id: int) -> void:
	if id != _client_id:
		return
	if _despawn_check_started:
		return
	_despawn_check_started = true
	if not _host_saw_in_range:
		print("[TAGPROBE][host] ERROR peer %d disconnected before TAG_IN_RANGE_HOST_PASS -- ordering invalid, cannot prove despawn edge" % id)
		_finish(1)
		return

	# Immediate, same-frame call (informational -- Godot defers queue_free()
	# to the next safe point, so the departed Player node/body may still be
	# resolvable here). The point of calling it NOW, before anything settles,
	# is to prove get_candidates_in_range() -> body.name does not throw/crash
	# on whatever transitional state exists the instant peer_disconnected
	# fires.
	var immediate: Array = _host_tag_detector.get_candidates_in_range()
	print("[TAGPROBE][host] immediate post-disconnect candidates=%s (no crash reading body.name)" % [immediate])

	print("[TAGPROBE][host] polling for despawn settle (no stale candidate for peer %d)..." % _client_id)
	_start_despawn_poll()


func _on_client_connected() -> void:
	print("[TAGPROBE][client] CONNECTED (Waiting Room); entering arena LATER (after host)...")
	_own_id = _net.multiplayer.get_unique_id()
	_after(CLIENT_ARENA_DELAY_SEC, _enter_arena)


func _on_client_failed() -> void:
	print("[TAGPROBE][client] CONNECTION_FAILED")
	_finish(1)


func _enter_arena() -> void:
	if _entered_arena:
		return
	_entered_arena = true
	var scene: PackedScene = load(TEST_ARENA_SCENE)
	_arena = scene.instantiate()
	root.add_child(_arena)
	current_scene = _arena
	_players_root = root.get_node("TestArena/Players")
	print("[TAGPROBE][%s] entered arena" % _role)

	if _role == "host":
		_start_host_players_poll()
	else:
		_start_client_players_poll()


# =============================================================================
# HOST: wait for both Players, teleport into range, assert (a)+(b) host side
# =============================================================================

func _start_host_players_poll() -> void:
	_host_players_poll = Timer.new()
	_host_players_poll.wait_time = PLAYERS_POLL_SEC
	_host_players_poll.one_shot = false
	root.add_child(_host_players_poll)
	_host_players_poll.timeout.connect(_check_host_players_ready)
	_host_players_poll.start()


func _check_host_players_ready() -> void:
	if _done:
		_host_players_poll.stop()
		return

	var own_player: Node3D = _players_root.get_node_or_null(str(_own_id)) as Node3D
	if own_player == null:
		return # own barrier-spawned Player not replicated/added yet

	var other_id: int = _host_find_other_player_id()
	if other_id == -1:
		return # client's Player not spawned/replicated to us yet

	_host_players_poll.stop()
	_host_player = own_player
	_client_id = other_id
	_client_player = _players_root.get_node(str(_client_id)) as Node3D
	_host_tag_detector = _host_player.get_node("TagDetector") as Area3D

	print("[TAGPROBE][host] both players present (host_id=%d client_id=%d) -- moving into tag range" % [_own_id, _client_id])

	_host_tag_detector.tag_target_in_range.connect(_on_host_tag_in_range)

	_teleport_host_into_range()


func _host_find_other_player_id() -> int:
	for child in _players_root.get_children():
		if child.name.is_valid_int() and child.name.to_int() != _own_id:
			return child.name.to_int()
	return -1


func _teleport_host_into_range() -> void:
	var target: Vector3 = _client_player.position + Vector3(TAG_OFFSET_M, 0.0, 0.0)
	_host_player.position = target
	print("[TAGPROBE][host] teleported own Player to %s (client at %s, offset=%.2f m, tag_range should be 2.0 m)" % [target, _client_player.position, TAG_OFFSET_M])

	_host_in_range_deadline = Timer.new()
	_host_in_range_deadline.wait_time = IN_RANGE_CHECK_TIMEOUT_SEC
	_host_in_range_deadline.one_shot = true
	root.add_child(_host_in_range_deadline)
	_host_in_range_deadline.timeout.connect(_on_host_in_range_timeout)
	_host_in_range_deadline.start()


## Asserts (a) real cross-peer Area3D overlap AND (b) the host-only-emit gate:
## this signal only exists to fire when `multiplayer.is_server() == true`
## (TagDetectorComponent._on_body_entered), and this process IS the host, so
## seeing it fire with the correct (host_id, client_id) pair proves both a
## genuine replicated-position overlap occurred AND the host side of the gate
## behaves as documented.
func _on_host_tag_in_range(tagger_id: int, target_id: int) -> void:
	if _host_saw_in_range:
		return
	if tagger_id != _own_id or target_id != _client_id:
		print("[TAGPROBE][host] ERROR tag_target_in_range fired with unexpected ids tagger=%d target=%d (expected tagger=%d target=%d)" % [tagger_id, target_id, _own_id, _client_id])
		_finish(1)
		return
	_host_saw_in_range = true
	if _host_in_range_deadline:
		_host_in_range_deadline.stop()
	print("[TAGPROBE][host] TAG_IN_RANGE_HOST_PASS host_id=%d client_id=%d" % [tagger_id, target_id])
	# Do not finish here -- stay alive so the driver can kill the client
	# process and this probe can observe the despawn edge (c), handled by
	# _on_host_peer_disconnected() above.


func _on_host_in_range_timeout() -> void:
	if _done or _host_saw_in_range:
		return
	print("[TAGPROBE][host] TIMEOUT waiting for TAG_IN_RANGE_HOST_PASS (host-side overlap never fired)")
	_finish(1)


# =============================================================================
# HOST: despawn/ghost edge (c)
# =============================================================================

func _start_despawn_poll() -> void:
	_host_despawn_deadline = Timer.new()
	_host_despawn_deadline.wait_time = DESPAWN_CHECK_TIMEOUT_SEC
	_host_despawn_deadline.one_shot = true
	root.add_child(_host_despawn_deadline)
	_host_despawn_deadline.timeout.connect(_on_despawn_timeout)
	_host_despawn_deadline.start()

	_host_despawn_poll = Timer.new()
	_host_despawn_poll.wait_time = DESPAWN_POLL_SEC
	_host_despawn_poll.one_shot = false
	root.add_child(_host_despawn_poll)
	_host_despawn_poll.timeout.connect(_check_despawn_settled)
	_host_despawn_poll.start()


func _check_despawn_settled() -> void:
	if _done:
		_host_despawn_poll.stop()
		return

	# get_candidates_in_range() is the exact production method a future
	# GameManager would poll -- calling it here, repeatedly, across the
	# despawn transition is what proves it neither returns a stale entry NOR
	# throws reading `body.name` on a body mid-teardown.
	var candidates: Array = _host_tag_detector.get_candidates_in_range()
	var stale_entry_present := false
	for c in candidates:
		if int(c.get("id", -1)) == _client_id:
			stale_entry_present = true

	var node_still_present: bool = _players_root.get_node_or_null(str(_client_id)) != null

	if stale_entry_present or node_still_present:
		print("[TAGPROBE][host] despawn not settled yet (stale_candidate=%s node_still_present=%s) -- polling..." % [stale_entry_present, node_still_present])
		return

	_host_despawn_poll.stop()
	if _host_despawn_deadline:
		_host_despawn_deadline.stop()
	print("[TAGPROBE][host] TAGPROBE_DESPAWN_PASS (no stale candidate for peer %d, node removed, no crash reading body.name)" % _client_id)
	_after(HOST_FINAL_HOLD_SEC, func() -> void: _finish(0))


func _on_despawn_timeout() -> void:
	if _done:
		return
	var candidates: Array = _host_tag_detector.get_candidates_in_range()
	print("[TAGPROBE][host] TAGPROBE_DESPAWN_STALE_FAIL timeout waiting for despawn to settle -- candidates=%s" % [candidates])
	_finish(1)


# =============================================================================
# CLIENT: wait for both Players (barrier proof, mirrors spawn_probe_together),
# then assert (b) from the client's own vantage point.
# =============================================================================

func _start_client_players_poll() -> void:
	_client_poll = Timer.new()
	_client_poll.wait_time = PLAYERS_POLL_SEC
	_client_poll.one_shot = false
	root.add_child(_client_poll)
	_client_poll.timeout.connect(_check_client_players_ready)
	_client_poll.start()


func _check_client_players_ready() -> void:
	if _done:
		_client_poll.stop()
		return

	var own_player: Node3D = _players_root.get_node_or_null(str(_own_id)) as Node3D
	if own_player == null:
		return

	var host_player: Node3D = _players_root.get_node_or_null("1") as Node3D
	if host_player == null:
		return # barrier group not fully replicated to us yet

	_client_poll.stop()
	print("[TAGPROBE][client] CLIENT_SPAWN_READY own_id=%d (host Player also replicated)" % _own_id)

	_client_tag_detector = own_player.get_node("TagDetector") as Area3D
	# CRITICAL assertion (b): if TagDetectorComponent's is_server() gate were
	# ever removed, THIS listener -- running on the CLIENT process -- would
	# fire for the same overlap the host sees. Any call here is an immediate
	# hard FAIL.
	_client_tag_detector.tag_target_in_range.connect(_on_client_tag_signal_fired)
	_client_tag_detector.tag_target_left_range.connect(_on_client_tag_signal_fired)

	_start_client_overlap_poll()


func _on_client_tag_signal_fired(tagger_id: int, target_id: int) -> void:
	print("[TAGPROBE][client] TAGPROBE_CLIENT_EMIT_FAIL tag signal fired on CLIENT process (tagger=%d target=%d) -- host-only-emit gate did NOT hold" % [tagger_id, target_id])
	_finish(1)


## Polls the GATE-FREE get_candidates_in_range() (no is_server() check inside
## it, see TagDetectorComponent.gd) to independently confirm the client's own
## local physics DID detect the overlap -- this is what makes the "the
## signal never fired" assertion above meaningful instead of trivially true
## (a listener that never fires because nothing ever happened would prove
## nothing).
func _start_client_overlap_poll() -> void:
	var t := Timer.new()
	t.wait_time = PLAYERS_POLL_SEC
	t.one_shot = false
	root.add_child(t)
	t.timeout.connect(func() -> void:
		if _done:
			t.stop()
			return
		var candidates: Array = _client_tag_detector.get_candidates_in_range()
		var overlap_now := false
		for c in candidates:
			if int(c.get("id", -1)) == 1: # host's peer id
				overlap_now = true

		if overlap_now and not _client_saw_local_overlap:
			_client_saw_local_overlap = true
			_client_no_emit_since = Time.get_ticks_msec() / 1000.0
			print("[TAGPROBE][client] LOCAL_OVERLAP_DETECTED via gate-free get_candidates_in_range() candidates=%s (signal still silent so far)" % [candidates])

		if _client_saw_local_overlap:
			var elapsed: float = (Time.get_ticks_msec() / 1000.0) - _client_no_emit_since
			if elapsed >= CLIENT_NO_EMIT_GRACE_SEC:
				t.stop()
				print("[TAGPROBE][client] TAG_IN_RANGE_CLIENT_DID_NOT_EMIT_PASS (local overlap confirmed for %.1fs, signal never fired on this process)" % elapsed)
				# Deliberately do NOT quit -- stay alive so the driver can
				# kill this process and the host can observe the despawn
				# edge (c). Bounded by --timeout as a safety net.
	)
	t.start()


# =============================================================================
# shared plumbing (mirrors spawn_probe_together_peer.gd)
# =============================================================================

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
	print("[TAGPROBE][%s] TIMEOUT (host_saw_in_range=%s client_saw_local_overlap=%s)" % [_role, _host_saw_in_range, _client_saw_local_overlap])
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
