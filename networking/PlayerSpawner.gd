extends MultiplayerSpawner
## PlayerSpawner (TK-P1-04) -- host-authoritative Player spawning by peer id.
##
## Attached to the "PlayerSpawner" MultiplayerSpawner node in
## world/TestArena.tscn. `spawn_path` points at the sibling "Players"
## container. NOTE (TK-BUG-P1-02 review nit #2): TestArena.tscn deliberately
## does NOT set `_spawnable_scenes` anymore. That list is NOT inert -- it
## arms MultiplayerSpawner's implicit auto-replicate-by-scene path, which
## replicates a matching node added under spawn_path WITHOUT any spawn_data
## payload. Since our whole TK-BUG-P1-01 fix depends on the id+position
## payload delivered by spawn_function (below), leaving Player.tscn in
## _spawnable_scenes would mean a future stray/manual add_child(Player.tscn)
## replicates with NO position data and silently reintroduces the origin-
## spawn S1 bug. With the list empty, only spawn() (which routes through our
## spawn_function) can produce a replicated Player -- any accidental
## auto-spawn path is disarmed by construction. Only the multiplayer
## authority of THIS node (the server/host, peer id 1 by default -- we never
## call set_multiplayer_authority() on it) is allowed to call spawn() and
## have it replicate; every other peer receives the instance automatically
## because they all registered the identical spawn_function callback.
##
## Server-authoritative model (CLAUDE.md / TDD §2, §9):
##   - The HOST decides who spawns and where. When peers are already connected
##     (the Waiting Room -> Start Match flow) it runs a READINESS BARRIER: it
##     spawns nobody -- not even itself -- until every connected peer's spawner
##     exists, then spawns everyone at once (host = deterministic slot 0). See
##     "Readiness barrier (TK-P2-13)" below for why the host must NOT spawn ANY
##     Player early: its first spawn poisons the per-peer node-path cache toward
##     any peer not yet in the arena, permanently dropping that peer's own later
##     spawn -> S1. (When no peer is connected -- standalone/offline, or the OLD
##     staggered-connect path -- it just spawns its own Player immediately.)
##     (server_started already fired in NetworkManager before the scene switch
##     to TestArena -- see ui/MainMenu.gd / the Start Match flow -- so we can't
##     rely on catching that signal here; instead we just check
##     multiplayer.is_server() once we're ready.)
##   - The HOST spawns one Player per NetworkManager.peer_connected(id), and
##     removes it on NetworkManager.peer_disconnected(id) (cleans up so a
##     departed peer's avatar doesn't linger -- avoids desync/zombie state).
##   - Clients never call add_child() here; they only ever receive replicated
##     instances. `MultiplayerSpawner.spawned` is a REMOTE-RECEIVE-only signal
##     (verified in Godot 4.7 headless): it fires on a peer when a node is
##     replicated IN from the network, but it does NOT fire on the authority
##     for a child the authority add_child()'d itself. So the host's own
##     Player (and any Player spawned during standalone/offline boot, where
##     the "host" is the only peer) would never get its local-camera flipped
##     if we only listened to `spawned`. We therefore handle the two cases
##     separately: `_spawn_player()` activates the local camera directly,
##     synchronously, right after its own add_child() call; `_on_spawned()`
##     (wired to the `spawned` signal) handles the replicated/client-side
##     case. Both paths funnel through `_activate_local_camera_if_own()`.
##
## Readiness barrier (TK-P2-13, network-engineer S1 fix -- SUPERSEDES two
## earlier WRONG attempts, both documented here so neither trap is re-laid):
## NetworkManager.peer_connected is a ONE-TIME signal per peer. In the OLD flow
## the host entered TestArena on server_started and clients connected LATER, so
## every client's peer_connected fired while PlayerSpawner already existed and
## _on_peer_connected() spawned each one. The Waiting Room (TK-P2-12) + Start
## Match (TK-P2-13) flow inverts this: the host AND all clients are ALREADY
## connected while sitting in the Waiting Room, and only switch into TestArena
## together when the host presses Start. By then every client's peer_connected
## has ALREADY fired -- back in the Waiting Room, before any PlayerSpawner node
## existed -- and it does NOT re-fire on the scene change.
##
## WRONG attempt #1 -- the host-side entry sweep: on its own _ready() the host
## swept NetworkManager.get_connected_peer_ids() and spawn()'d a Player for each
## already-connected peer. WRONG attempt #2 -- a naive per-peer handshake: the
## host spawned only its OWN Player on _ready(), and each client sent
## _rpc_arena_ready so the host spawned that client once its spawner existed.
## BOTH failed the SAME way under the REAL ordering, for a subtler reason than
## "the peer's spawner does not exist yet."
##
## The real mechanism (confirmed empirically via the host-first probe):
## ui/WaitingRoom.gd's _rpc_start_match() runs on the host synchronously via
## call_local, so the host's deferred change_scene_to_file() is queued a frame
## (or more) BEFORE each client's -- the HOST enters TestArena FIRST while every
## client is still tearing down WaitingRoom and instancing TestArena. The
## instant the host spawn()s ANY Player (even just its OWN), Godot's high-level
## multiplayer must tell the connected clients which spawner produced it, using
## its per-peer NODE-PATH CACHE: it sends "TestArena/PlayerSpawner = cache id N"
## to each client. A client that is not in the arena yet cannot resolve that
## path ("Node not found: TestArena/PlayerSpawner"), so cache id N is NEVER
## registered on that client -- and the host nonetheless treats the id as
## assigned. That path-cache entry is now permanently POISONED: when the client
## finally enters the arena and the host spawns THAT client's own Player
## (referencing the same cache id N), the client hits "ID N not found in cache"
## / "spawner is null" in on_spawn_receive and DROPS the spawn. The client lands
## in the arena with ZERO Players (not even the host's) and never recovers ->
## silent S1. Attempt #2 did not help because the poison is caused by the
## host's OWN early spawn, before any client-side handshake can matter.
##
## THE FIX -- a host-side readiness BARRIER (still built on the same client
## readiness RPC as ui/WaitingRoom.gd's _rpc_client_hello handshake, just with
## an all-peers barrier so the host never references the spawner path toward a
## peer that is not in the arena yet):
##   - On _ready() the HOST snapshots the connected roster into
##     _expected_ready_peers and, if it is non-empty (peers already connected --
##     the Waiting Room flow), spawns NOTHING yet, not even its own Player.
##   - Each CLIENT (non-server) sends rpc_id(1, "_rpc_arena_ready") on its own
##     _ready() -- "my PlayerSpawner node now exists at TestArena/PlayerSpawner
##     and can resolve that path." The host enters the arena FIRST, so its
##     spawner is present to receive this RPC (same host-exists-first guarantee
##     WaitingRoom's hello relies on).
##   - _rpc_arena_ready() (server-side only) records the sender ready. Once
##     EVERY expected peer is ready, _do_initial_barrier_spawn() spawns everyone
##     at once: the host FIRST (deterministic slot 0), then each ready peer in
##     ascending id order. Because every spawned-for peer's spawner now exists,
##     each path-cache negotiation succeeds and every spawn replicates cleanly
##     -- no poison, no drop.
##   - Slot determinism: the host is always spawned first (slot 0); peers take
##     the next slots in ascending-id order, reproducible per session.
##     _spawn_player() advances _spawn_count once per UNIQUE id and its
##     has_node(str(id)) guard sits BEFORE the increment, so a duplicate/late
##     ready-RPC (or an overlap with _on_peer_connected) can neither double-spawn
##     nor skew the sequence -- nobody stacks at the origin.
##   - A grace timer (_start_ready_grace_timer) rescues the match if a peer
##     never announces readiness (e.g. crashed during scene load): after
##     ARENA_READY_GRACE_SEC the host spawns itself + whoever IS ready, so one
##     hung peer cannot deadlock everyone.
##   - If _expected_ready_peers is EMPTY at _ready() -- standalone/offline boot,
##     or the OLD staggered-connect path (host enters before any client) -- the
##     host spawns its own Player immediately (no connected peer = no poison
##     risk) and _on_peer_connected()/_rpc_arena_ready() handle each later
##     arrival exactly as before, so that path is unchanged (no regression).
##   - _on_peer_connected() is deliberately left INTACT for a genuine late
##     joiner (someone connecting AFTER the match is already in the arena -- not
##     a Phase-2 flow yet, but kept correct); the has_node guard makes any
##     overlap with a client's ready-RPC safe.
##
## Multiplayer authority of the spawned Player (TK-P1-05; superseded by
## TK-BUG-P1-01, see below): each spawned Player's multiplayer authority ends
## up set to the peer id it was spawned for (str(id) is already its node
## name -- see naming contract below), so Player.gd's
## is_multiplayer_authority()-gated input (TK-P1-02) lets each peer drive
## only its OWN Player; the host no longer drives everyone.
##
## TK-BUG-P1-01 (network-engineer, S1 fix): authority assignment USED TO live
## here -- host-side in _spawn_player() (instance.set_multiplayer_authority(id)
## before add_child()) and client-side in _on_spawned() (parsed back out of
## node.name after the `spawned` signal). That was too late on the
## replicated/client side: `spawned` fires AFTER the node's own _ready(), by
## which point Godot has already started delivering this instance's
## MultiplayerSpawner spawn-state (the host-seeded initial position) and
## rejects a late authority change ("unable to process the pending spawn
## since it has no network ID"), silently discarding that spawn state --
## every client's own Player landed at (0,0,0) or stacked on the host's slot,
## plus an engine error on every join.
##
## Fix, part 1 (authority timing): authority assignment moved to
## Player._enter_tree() (see that file), which runs on EVERY peer the
## instant the node enters the tree -- before _ready() and before the
## `spawned` signal, the timing Godot's OWN error message recommends. This
## spawner no longer calls set_multiplayer_authority() anywhere;
## Player.gd's _enter_tree() is now the ONE source of truth, deriving
## authority from the same node.name == str(peer_id) naming contract this
## spawner still owns (it only needs to set instance.name, which it does as
## part of the spawn_function callback below).
##
## Fix, part 2 (initial position delivery -- REQUIRED, discovered via the
## 2-instance spawn_probe while validating part 1 alone): giving a peer
## authority over its OWN Player makes THAT peer the sync SOURCE for its
## position/rotation from then on -- MultiplayerSynchronizer replication
## only ever flows FROM the authority TO everyone else, never the reverse.
## That means the host's OWN choice of "where does this new player start"
## (SpawnPointUtil.spawn_point()) can NEVER reach the owning peer via the
## ordinary property-sync channel once that peer holds authority -- no
## matter how precisely part 1's timing is tuned, an authoritative peer's
## local value simply cannot be overwritten by an incoming replicated write
## for a property it now owns (confirmed empirically: with part 1 alone,
## the owning client's own Player stayed at its scene-default (0,0,0)
## forever, no error, no stack, just never-arriving spawn state -- a
## different flavor of the same underlying symptom).
##
## This spawner now uses MultiplayerSpawner's spawn_function (instead of
## the implicit _spawnable_scenes flow) to deliver id + position as a single
## one-time, authority-INDEPENDENT payload: spawn(data) transmits `data` to
## every peer, which each independently call _create_player_instance(data)
## to build (and pre-position) their own local copy BEFORE add_child() --
## i.e. before Player._enter_tree() ever runs, so authority is irrelevant to
## whether the correct starting position lands. Player.tscn's
## MultiplayerSynchronizer still replicates position/rotation ON_CHANGE
## going forward (ordinary ongoing movement sync, unaffected by any of
## this) but no longer marks them `spawn = true` -- that flag specifically
## opts a property into the same "pending spawn" one-time delivery machinery
## that was the source of both symptoms, and is now redundant since
## spawn_function already delivers the initial value directly.
##
## Naming contract: each spawned Player's node name is set to str(peer_id)
## (e.g. "1" for the host, "2" for the first client, ...) -- this is how
## _on_spawned() and _on_peer_disconnected() identify/find a given peer's
## Player without needing extra network-authoritative state.

const PLAYER_SCENE: PackedScene = preload("res://characters/Player.tscn")

## Host-only: how long (seconds) the host waits for EVERY already-connected
## peer to announce arena readiness before it re-evaluates the barrier. Normal
## Start-Match readiness lands in well under a second; this only elapses if a
## peer is slow/unreachable. When it elapses, the host does NOT immediately kill
## the laggards (TK-P2-30 fix): a peer that is still connected at the ENet layer
## is alive and merely slow, so the grace is EXTENDED (up to
## ARENA_READY_MAX_GRACE_EXTENSIONS times, this same interval each) rather than
## force-disconnecting a healthy-but-backgrounded client. Only a peer that is
## truly gone, or that burns the whole extension budget while still connected
## (genuinely wedged), is finally dropped -- so one hung peer still cannot hold
## the match hostage forever. See ArenaBarrierRules for the decision logic.
const ARENA_READY_GRACE_SEC: float = 8.0

## Host-only (TK-P2-30): how many times the grace window may be EXTENDED for a
## still-connected-but-not-yet-ready peer before the host gives up on it and
## falls back to the original TK-P2-13 force-disconnect-then-spawn behavior.
## Total worst-case barrier hold = ARENA_READY_GRACE_SEC * (1 + this) before a
## genuinely wedged (ENet-alive but never-ready) peer is dropped -- 8s * 4 = 32s
## here. Sized as real headroom for an unfocused/backgrounded client whose frame
## loop (and therefore its scene-load completion + reliable-RPC flush) is
## throttled hard by the OS compositor + vsync while occluded, on a slow machine
## or link -- WELL past the 8s that killed healthy clients before -- while still
## bounding the deadlock protection to a finite, defensible ceiling. This is an
## evidence-gated wait (only extended while the peer is provably still connected),
## NOT a blind bigger timeout.
const ARENA_READY_MAX_GRACE_EXTENSIONS: int = 3

var _players_root: Node3D
var _spawn_count: int = 0

## Host-only readiness-barrier state (TK-P2-13, see "Readiness barrier" in the
## class doc). Peer ids the host is waiting on: a snapshot of the connected
## roster taken the instant the host enters the arena (its _ready()).
var _expected_ready_peers: Dictionary = {}
## Peer ids that have announced arena readiness via _rpc_arena_ready. Tracked
## both before the barrier fires (to know when all expected peers are in) and
## after (so a late/extra ready-RPC is handled idempotently).
var _ready_peers: Dictionary = {}
## True once the host has done its one-time initial barrier spawn (host + every
## ready peer). After this, any further ready-RPC spawns just its own sender.
var _initial_spawn_done: bool = false
## Peer ids that connected DURING the barrier window (after the host entered the
## arena, before the barrier released). They are deliberately NOT spawned yet --
## spawning toward a peer that is not in the arena poisons the path cache (the
## whole reason the barrier exists). Recorded only so the late-joiner UX
## follow-up card has a hook; today they simply do not receive a Player until
## that card lands.
var _deferred_join_peers: Dictionary = {}

## Host-only readiness-barrier grace state (TK-P2-30). The single reused grace
## Timer (kept as a reference so we can re-arm it for an extension and stop it
## cleanly once the barrier releases -- also resolves the TK-P2-22 "stop the
## grace timer on normal release" nit) and how many extensions we have already
## granted a still-connected-but-slow peer.
var _grace_timer: Timer = null
var _grace_extensions_used: int = 0


func _ready() -> void:
	_players_root = get_node(spawn_path)

	# TK-BUG-P1-01 fix part 2 (see class doc): every peer registers the SAME
	# spawn_function so spawn(data) below can deliver id + position as a
	# single authority-independent payload, identically constructed on every
	# peer (host included) BEFORE that instance's _enter_tree()/authority
	# assignment ever runs.
	spawn_function = _create_player_instance

	# Handles the REPLICATED side only (see class doc): fires when a Player
	# node is received over the network, never for the authority's own
	# add_child(). The host-local side is handled directly in
	# _spawn_player() -> _activate_local_camera_if_own().
	spawned.connect(_on_spawned)

	NetworkManager.peer_connected.connect(_on_peer_connected)
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)

	# Readiness barrier (TK-P2-13 S1 fix -- see "Readiness barrier" in the class
	# doc). The host's own NetworkManager.server_started already fired (and the
	# scene already switched) before this node's _ready() runs, so we can't rely
	# on catching that signal here -- just check is_server() now.
	#   - HOST: snapshot the connected roster. If NO peers are connected
	#     (standalone/offline boot, or the OLD staggered-connect path where the
	#     host enters before any client), spawn its own Player immediately (no
	#     connected peer means no path-cache poison risk). If peers ARE already
	#     connected (the Waiting Room -> Start Match flow), the host spawns
	#     NOTHING yet -- not even itself -- until every connected peer's spawner
	#     exists (see class doc for why spawning early poisons the path cache).
	#   - CLIENT: announce readiness to the host ("my PlayerSpawner exists").
	if multiplayer.is_server():
		_expected_ready_peers = {}
		for peer_id in NetworkManager.get_connected_peer_ids():
			_expected_ready_peers[peer_id] = true
		if _expected_ready_peers.is_empty():
			_do_initial_barrier_spawn()
		else:
			_start_ready_grace_timer()
	else:
		rpc_id(1, "_rpc_arena_ready")


## Client -> host arena-readiness announcement (TK-P2-13 S1 fix -- see
## "Readiness barrier" in the class doc). Runs on the HOST ONLY (any_peer, no
## call_local, so a client calling rpc_id(1, ...) executes this solely on peer
## 1); is_server() guards as defense in depth. Reads the sender's peer id and
## feeds the readiness barrier:
##   - Before the barrier fires: record the sender ready; once EVERY expected
##     peer is ready, spawn everyone at once (host + all peers) -- only now that
##     all their spawners exist, so no replicated spawn is dropped.
##   - After the barrier already fired (offline path, OLD staggered path, or a
##     late joiner): spawn just this sender directly. Its spawner exists (it
##     just told us), so the spawn lands; idempotent via _spawn_player()'s
##     has_node guard against any overlap with _on_peer_connected().
@rpc("any_peer", "reliable")
func _rpc_arena_ready() -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_ready_peers[sender_id] = true
	if _initial_spawn_done:
		_spawn_player(sender_id)
		return
	if _all_expected_peers_ready():
		_do_initial_barrier_spawn()


## Host-only: have all peers the host is waiting on announced readiness?
func _all_expected_peers_ready() -> bool:
	for peer_id in _expected_ready_peers:
		if not _ready_peers.has(peer_id):
			return false
	return true


## Host-only, runs exactly once: the initial barrier spawn. Spawns the host
## itself FIRST (deterministic slot 0), then every expected peer that is ready,
## in ascending id order so slot assignment is reproducible for a given
## session. By the time this runs every spawned-for peer's PlayerSpawner is
## known to exist, so each replicated spawn lands cleanly (this is the whole
## point of the barrier -- see class doc).
##
## TK-P3-10 (TEST-HARNESS-ONLY, default OFF): when
## NetworkManager.dedicated_host_no_self_spawn is set the host SKIPS its own
## self-spawn here (via DedicatedHostRules.host_spawns_own_player) -- the peers
## below are unaffected and still spawn in the same order (the host simply never
## occupies slot 0; peers still take slots in ascending-id order from slot 0
## onward, which is harmless -- SpawnPointUtil.spawn_point() wraps _spawn_count
## and slot identity carries no game meaning). Every real shipped-game session
## leaves the flag false, so this is a strict no-op there.
func _do_initial_barrier_spawn() -> void:
	if _initial_spawn_done:
		return
	_initial_spawn_done = true

	# TK-P2-30 / TK-P2-22 nit: the barrier is releasing now, so stop the grace
	# timer -- prevents a stray timeout (or a pending extension) from firing after
	# the spawn. (_on_ready_grace_timeout()'s own `if _initial_spawn_done: return`
	# guard already neutralizes a late fire; stopping is belt-and-suspenders and
	# keeps no orphan Timer ticking.)
	if _grace_timer:
		_grace_timer.stop()

	# TK-P3-10: a dedicated host (TEST-HARNESS-ONLY opt-in, default OFF) never
	# spawns a Player for its OWN id -- so its idle, AI-less body can never be
	# picked/tagged into Tiger and softlock a match. This is the SOLE place the
	# host's own Player is ever spawned (both the Waiting-Room barrier release
	# and the offline/no-peers immediate path in _ready() funnel through here;
	# _on_peer_connected()/_rpc_arena_ready() only ever spawn OTHER peers' ids),
	# so guarding this one call fully covers the dedicated-host case. When the
	# flag is OFF (every real shipped-game session) host_spawns_own_player()
	# returns true and this is unchanged. Every OTHER peer below still spawns
	# normally in both cases -- the barrier/grace machinery is untouched.
	if DedicatedHostRules.host_spawns_own_player(
			multiplayer.is_server(), NetworkManager.dedicated_host_no_self_spawn):
		_spawn_player(multiplayer.get_unique_id())
	else:
		GameLog.info("[SPAWN] dedicated host (TK-P3-10 no-self-spawn) -- host's own Player intentionally NOT spawned; spawning connected peers only")

	var ready_expected: Array = []
	for peer_id in _expected_ready_peers:
		if _ready_peers.has(peer_id):
			ready_expected.append(peer_id)
	ready_expected.sort()
	for peer_id in ready_expected:
		_spawn_player(peer_id)


## Host-only: rescue timer so a peer that never reaches the arena (e.g. it
## crashed / hung during scene load) cannot deadlock the barrier and leave
## EVERYONE -- host included -- with no Player. If the grace window elapses
## before all expected peers are ready, _on_ready_grace_timeout() releases the
## barrier (see there for how it protects the still-unready peers).
func _start_ready_grace_timer() -> void:
	var grace := Timer.new()
	grace.name = "ArenaReadyGrace"
	grace.wait_time = ARENA_READY_GRACE_SEC
	grace.one_shot = true
	add_child(grace)
	grace.timeout.connect(_on_ready_grace_timeout)
	# TK-P2-30: keep the reference so _on_ready_grace_timeout() can re-arm this
	# same one-shot timer for a grace EXTENSION (.start() again) instead of
	# leaking a fresh "ArenaReadyGrace" node per extension, and so
	# _do_initial_barrier_spawn() can stop it once the barrier releases normally.
	_grace_timer = grace
	grace.start()


## BARRIER GRACE RELEASE (TK-P2-13 review blocker 3, revised by TK-P2-30):
## when the grace window elapses with peers still not ready, we must NOT simply
## spawn host + ready and leave the laggards behind -- an expected peer that is
## still CONNECTED but merely slow-loading is not in the arena yet, so spawning
## now would poison the path cache toward it and its own spawn would drop
## PERMANENTLY (a silent, unrecoverable S1 for that one peer). The original
## producer decision was to force-disconnect the laggards immediately, converting
## that silent desync into an explicit, recoverable disconnect.
##
## TK-P2-30 (S2 bug: a healthy but UNFOCUSED/backgrounded client got killed here)
## refines the "immediately" part. Root cause: an occluded window's frame loop is
## throttled hard by the OS compositor + vsync, and Godot drives BOTH scene-load
## completion AND the multiplayer poll/flush that actually sends the queued
## reliable _rpc_arena_ready packet from that same loop -- so a perfectly alive
## client's readiness can legitimately land well past 8s. A peer that is still
## present in NetworkManager.get_connected_peer_ids() is proven alive at the ENet
## layer (not crashed), so we EXTEND the grace (keep the whole barrier held --
## still never spawning toward an absent peer, so zero new poison risk) instead of
## killing it, for up to ARENA_READY_MAX_GRACE_EXTENSIONS intervals. Only a peer
## that is truly gone from the transport, or that burns the entire extension
## budget while still connected (genuinely wedged: ENet alive but its game thread
## never progresses), reaches the original force-disconnect-then-spawn fallback --
## so one hung peer still cannot deadlock the match forever. Decision logic is the
## pure ArenaBarrierRules.decide_grace_action(); server authority is unchanged
## (the host alone decides membership + release; it just waits longer, and only on
## live transport-level evidence the peer is alive).
func _on_ready_grace_timeout() -> void:
	if _initial_spawn_done:
		return

	var still_unready: Array = []
	for peer_id in _expected_ready_peers:
		if not _ready_peers.has(peer_id):
			still_unready.append(peer_id)

	var connected_ids: Array = NetworkManager.get_connected_peer_ids()
	var action: ArenaBarrierRules.GraceAction = ArenaBarrierRules.decide_grace_action(
		still_unready, connected_ids, _grace_extensions_used, ARENA_READY_MAX_GRACE_EXTENSIONS)

	if action == ArenaBarrierRules.GraceAction.EXTEND:
		_grace_extensions_used += 1
		GameLog.info("[SPAWN] arena-ready grace elapsed but %d unready peer(s) still connected (slow/backgrounded load, NOT crashed) -- extending grace %d/%d (+%.1fs) instead of force-disconnecting a healthy peer" % [still_unready.size(), _grace_extensions_used, ARENA_READY_MAX_GRACE_EXTENSIONS, ARENA_READY_GRACE_SEC])
		if _grace_timer:
			_grace_timer.start()
		return

	# RELEASE: give up waiting. Anyone still unready now is either already gone
	# from the transport (peer_disconnected pruning will have handled it, but we
	# defensively drop it from the barrier sets too) or has burned the whole
	# extension budget while connected (genuinely wedged) -- the original TK-P2-13
	# tradeoff applies: an explicit, recoverable force-disconnect beats a silent
	# path-cache-poison S1.
	for peer_id in still_unready:
		GameLog.info("[SPAWN] arena-ready grace fully elapsed (%d/%d extensions used) -- force-disconnecting still-unready peer %d (avoids silent path-cache-poison S1)" % [_grace_extensions_used, ARENA_READY_MAX_GRACE_EXTENSIONS, peer_id])
		_expected_ready_peers.erase(peer_id)
		NetworkManager.disconnect_peer(peer_id)

	GameLog.info("[SPAWN] arena-ready grace released -- spawning host + ready peers")
	_do_initial_barrier_spawn()


## Host-only: a new peer connected to NetworkManager -- spawn its Player.
## Guarded by is_server() so a client that also happens to receive this
## signal (it shouldn't, per NetworkManager's peer_connected semantics, but
## the guard costs nothing) never attempts to spawn -- only the server is
## the multiplayer authority for this node, so a client add_child() call
## here would silently fail to replicate anyway.
##
## BARRIER-WINDOW POISON GUARD (TK-P2-13 review blocker 1): the ENet server
## keeps listening after Start, so a peer clicking Join in the sub-second (LAN)
## to multi-second (WAN) window between the host entering the arena and the
## barrier releasing would land here while EVERY expected peer is still not in
## the arena. Spawning it immediately would (a) poison the path cache toward all
## of them (dropping their barrier spawns -> S1 for the whole lobby) and (b)
## steal _spawn_count slot 0 from the host. So during the barrier window we do
## NOT spawn -- we only record the id (its proper handling is the late-joiner UX
## follow-up card). After the barrier has released, a genuine late joiner is
## spawned as before (its own arena spawner will exist by the time it enters;
## the has_node guard keeps it idempotent).
func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	if not _initial_spawn_done:
		_deferred_join_peers[id] = true
		GameLog.info("[SPAWN] peer %d joined during barrier window -- deferring (not spawned to avoid path-cache poison)" % id)
		return
	_spawn_player(id)


## Host-only: a peer left -- remove its Player so it doesn't linger for
## everyone else (avoids desync / zombie avatars, per CLAUDE.md correctness
## priority). MultiplayerSpawner replicates the removal the same way it
## replicated the spawn.
##
## BARRIER-WINDOW PRUNE (TK-P2-13 review blocker 2): a peer that quits between
## the barrier snapshot (host _ready()) and its release (rage-quit at match
## start is common) must be removed from the sets the barrier is waiting on, or
## it holds EVERYONE at zero Players until the grace timer fires. So we erase it
## from every barrier dict and, if the barrier has not released yet, re-check:
## once the departed peer is no longer awaited the remaining players spawn
## immediately. (All expected peers gone -> empty dict -> _all_expected_peers_
## ready() true -> host-only spawn, which is correct.)
func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	_expected_ready_peers.erase(id)
	_ready_peers.erase(id)
	_deferred_join_peers.erase(id)

	var existing: Node = _players_root.get_node_or_null(str(id))
	if existing:
		existing.queue_free()
		GameLog.info("[SPAWN] player %d despawned (peer disconnected)" % id)

	if not _initial_spawn_done and _all_expected_peers_ready():
		GameLog.info("[SPAWN] peer %d left during barrier window -- releasing barrier for remaining players" % id)
		_do_initial_barrier_spawn()


func _spawn_player(id: int) -> void:
	if _players_root.has_node(str(id)):
		return # already spawned for this id -- idempotent guard

	# NOTE: _spawn_count is a monotonically increasing "how many players has
	# this host spawned so far this session" counter, not a live player
	# count -- it intentionally does NOT decrement in _on_peer_disconnected,
	# so a reconnecting peer gets the next slot in the sequence rather than
	# reusing a just-vacated one. SpawnPointUtil.spawn_point() wraps it via
	# `% MAX_SPAWN_SLOTS`, so this only affects which of the 8 fixed spots a
	# given (re)connect lands on, never correctness.
	var spawn_position: Vector3 = SpawnPointUtil.spawn_point(_spawn_count)
	_spawn_count += 1

	# TK-BUG-P1-01 fix part 2 (see class doc): spawn(data) calls
	# _create_player_instance(data) on EVERY peer (this one included) with
	# the SAME id + position, building each peer's own local copy already
	# correctly positioned before it ever enters the tree -- then adds the
	# returned node under spawn_path itself (equivalent to our old manual
	# add_child(), but authority-independent and race-free). Player._enter_tree()
	# (this call's local add_child, and every other peer's replicated one)
	# still assigns authority afterward exactly as before.
	var instance: Node = spawn({"id": id, "position": spawn_position})
	if instance == null:
		GameLog.error("[SPAWN] spawn() returned null for peer %d -- not spawned" % id)
		return

	GameLog.info("[SPAWN] player %d spawned at %s" % [id, spawn_position])

	# Host-local path (see class doc): the authority's own add_child() (done
	# by spawn() above) does NOT trigger `spawned` on itself, so activate
	# this instance's camera synchronously here if it's ours. Covers the
	# host's own Player and standalone/offline boot (single peer,
	# is_server() == true).
	_activate_local_camera_if_own(instance)


## spawn_function callback (TK-BUG-P1-01 fix part 2, see class doc): called
## identically on EVERY peer (by MultiplayerSpawner, once per spawn(data)
## call) to construct that peer's own local copy of a newly spawned Player,
## already named and positioned from `data` -- BEFORE add_child()/_enter_tree()
## ever runs, so the correct starting position is never subject to
## authority-gated replication timing. Returns the built (but not yet
## parented) node; MultiplayerSpawner itself adds it under spawn_path.
func _create_player_instance(data: Dictionary) -> Node:
	var instance: Node3D = PLAYER_SCENE.instantiate()
	instance.name = str(data.get("id"))
	instance.position = data.get("position", Vector3.ZERO)
	return instance


## Replicated/client-side path (see class doc): runs on every peer whenever
## a Player node appears under spawn_path BECAUSE it was replicated in from
## the network (never fires for the authority's own add_child()). Delegates
## to the same local-camera activation used by the host-local path in
## _spawn_player() so both routes agree on "exactly one camera current".
##
## TK-BUG-P1-01: no longer touches multiplayer authority (see class doc) --
## Player._enter_tree() already set its own authority correctly by the time
## `spawned` fires (spawned fires after _ready(), _enter_tree() runs before
## it), so re-deriving/re-setting it here would be redundant at best and,
## per the audit, was actively harmful (too late relative to pending-spawn
## state processing). This handler is ONLY local-camera activation now.
func _on_spawned(node: Node) -> void:
	_activate_local_camera_if_own(node)


## Exactly one Camera3D must end up `current` across the whole game: the
## LOCAL peer's own Player. Player.tscn's Camera3D already defaults to
## current = false (TK-P1-01) specifically to avoid the "first camera
## auto-currents" bug QA flagged -- we only flip it on for the one instance
## that matches our own multiplayer.get_unique_id(). Setting a Camera3D's
## `current` to true automatically un-currents whatever was previously
## current (including TestArena's own overview Camera3D), so no manual
## bookkeeping is needed on the TestArena side.
##
## Camera lookup contract (TK-P1-03/TK-P1-05 hand-off): TK-P1-03 replaces
## Player's placeholder Camera3D with a SpringArm3D+Camera3D rig and exposes
## it via Player.get_view_camera() -> Camera3D. We prefer that accessor when
## present so we don't care whether the rig has landed yet; only fall back
## to the old hardcoded "Camera3D" child lookup if get_view_camera() isn't
## defined (e.g. this scene version predates TK-P1-03).
func _activate_local_camera_if_own(node: Node) -> void:
	if not SpawnPointUtil.is_local_peer_name(node.name, multiplayer.get_unique_id()):
		return
	var cam: Camera3D = null
	if node.has_method("get_view_camera"):
		cam = node.get_view_camera()
	else:
		cam = node.get_node_or_null("Camera3D")
	if cam:
		cam.current = true
