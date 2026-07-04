extends MultiplayerSpawner
## PlayerSpawner (TK-P1-04) -- host-authoritative Player spawning by peer id.
##
## Attached to the "PlayerSpawner" MultiplayerSpawner node in
## world/TestArena.tscn. `spawn_path` points at the sibling "Players"
## container; `_spawnable_scenes` lists res://characters/Player.tscn (see
## TestArena.tscn for both). Only the multiplayer authority of THIS node
## (the server/host, peer id 1 by default -- we never call
## set_multiplayer_authority() on it) is allowed to add_child() a Player
## under spawn_path and have it replicate; every other peer receives the
## instance automatically because Player.tscn is registered as spawnable.
##
## Server-authoritative model (CLAUDE.md / TDD §2, §9):
##   - The HOST decides who spawns and where. It spawns itself on _ready()
##     (server_started already fired in NetworkManager before MainMenu
##     switches scene to TestArena -- see ui/MainMenu.gd -- so we can't rely
##     on catching that signal here; instead we just check
##     multiplayer.is_server() once we're ready).
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
## Multiplayer authority of the spawned Player (TK-P1-05, this update): each
## spawned Player's multiplayer authority is set to the peer id it was
## spawned for (str(id) is already its node name -- see naming contract
## below), so Player.gd's is_multiplayer_authority()-gated input (TK-P1-02)
## lets each peer drive only its OWN Player; the host no longer drives
## everyone.
##
## set_multiplayer_authority() is a purely LOCAL call -- Godot does NOT
## propagate it over the network by itself, so every peer's local copy of a
## given Player node must call it independently and agree. We rely on the
## deterministic naming contract (node.name == str(peer_id), already used by
## _on_peer_disconnected/_activate_local_camera_if_own) rather than any
## extra RPC/race:
##   - Host side: _spawn_player() sets instance.set_multiplayer_authority(id)
##     BEFORE add_child(), for every Player it spawns (its own AND every
##     client's) -- this covers the host's entire local tree in one place,
##     before that instance's first _ready()/_physics_process() runs.
##   - Every other peer's side: _on_spawned() (replicated-receive only, see
##     below) parses the same id back out of node.name and calls
##     node.set_multiplayer_authority() on ITS local copy, so a client's
##     local tree ends up agreeing with the host's without needing the
##     spawner to transmit authority explicitly.
## set_multiplayer_authority(id) defaults to recursive = true, so
## Player.tscn's MultiplayerSynchronizer child (whose root_path defaults to
## "..", i.e. the Player itself) inherits the same authority automatically
## -- no separate call needed for it to replicate FROM the owning peer.
##
## Naming contract: each spawned Player's node name is set to str(peer_id)
## (e.g. "1" for the host, "2" for the first client, ...) -- this is how
## _on_spawned() and _on_peer_disconnected() identify/find a given peer's
## Player without needing extra network-authoritative state.

const PLAYER_SCENE: PackedScene = preload("res://characters/Player.tscn")

var _players_root: Node3D
var _spawn_count: int = 0


func _ready() -> void:
	_players_root = get_node(spawn_path)

	# Handles the REPLICATED side only (see class doc): fires when a Player
	# node is received over the network, never for the authority's own
	# add_child(). The host-local side is handled directly in
	# _spawn_player() -> _activate_local_camera_if_own().
	spawned.connect(_on_spawned)

	NetworkManager.peer_connected.connect(_on_peer_connected)
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)

	# The host's own NetworkManager.server_started already fired (and
	# MainMenu already switched scene) before this node's _ready() runs, so
	# we can't rely on catching that signal here -- just spawn the host's
	# own Player immediately if we ARE the server. Also covers running
	# TestArena standalone/offline (no multiplayer peer set at all), which
	# Godot also reports as is_server() == true.
	if multiplayer.is_server():
		_spawn_player(multiplayer.get_unique_id())


## Host-only: a new peer connected to NetworkManager -- spawn its Player.
## Guarded by is_server() so a client that also happens to receive this
## signal (it shouldn't, per NetworkManager's peer_connected semantics, but
## the guard costs nothing) never attempts to spawn -- only the server is
## the multiplayer authority for this node, so a client add_child() call
## here would silently fail to replicate anyway.
func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	_spawn_player(id)


## Host-only: a peer left -- remove its Player so it doesn't linger for
## everyone else (avoids desync / zombie avatars, per CLAUDE.md correctness
## priority). MultiplayerSpawner replicates the removal the same way it
## replicated the spawn.
func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	var existing: Node = _players_root.get_node_or_null(str(id))
	if existing:
		existing.queue_free()
		GameLog.info("[SPAWN] player %d despawned (peer disconnected)" % id)


func _spawn_player(id: int) -> void:
	if _players_root.has_node(str(id)):
		return # already spawned for this id -- idempotent guard

	var instance: Node3D = PLAYER_SCENE.instantiate()
	instance.name = str(id)
	# NOTE: _spawn_count is a monotonically increasing "how many players has
	# this host spawned so far this session" counter, not a live player
	# count -- it intentionally does NOT decrement in _on_peer_disconnected,
	# so a reconnecting peer gets the next slot in the sequence rather than
	# reusing a just-vacated one. SpawnPointUtil.spawn_point() wraps it via
	# `% MAX_SPAWN_SLOTS`, so this only affects which of the 8 fixed spots a
	# given (re)connect lands on, never correctness.
	instance.position = SpawnPointUtil.spawn_point(_spawn_count)
	_spawn_count += 1

	# TK-P1-05: assign this Player's multiplayer authority to the peer it was
	# spawned for, BEFORE add_child(), so the instance never spends a frame
	# defaulting to authority = 1 (the server) once it enters the tree. This
	# is the host's local copy of the node -- covers both the host's own
	# Player and every client's Player, since only the host ever runs
	# _spawn_player() (see _on_peer_connected's is_server() guard). Every
	# OTHER peer's local copy of this same node gets its authority set
	# independently in _on_spawned() below, from the same str(id) naming
	# contract -- set_multiplayer_authority() does not itself propagate over
	# the network. recursive = true (default) also covers the Player's
	# MultiplayerSynchronizer child, so it replicates FROM the owning peer.
	instance.set_multiplayer_authority(id)

	_players_root.add_child(instance)
	GameLog.info("[SPAWN] player %d spawned at %s" % [id, instance.position])

	# Host-local path (see class doc): the authority's own add_child() above
	# does NOT trigger `spawned` on itself, so activate this instance's
	# camera synchronously here if it's ours. Covers the host's own Player
	# and standalone/offline boot (single peer, is_server() == true).
	_activate_local_camera_if_own(instance)


## Replicated/client-side path (see class doc): runs on every peer whenever
## a Player node appears under spawn_path BECAUSE it was replicated in from
## the network (never fires for the authority's own add_child()). Delegates
## to the same local-camera activation used by the host-local path in
## _spawn_player() so both routes agree on "exactly one camera current".
##
## TK-P1-05: also sets THIS peer's local copy of the replicated node's
## multiplayer authority, mirroring the host-side assignment in
## _spawn_player() above. set_multiplayer_authority() never propagates over
## the network on its own, so every peer must set it independently; we
## recover the same peer id the host used from node.name (the naming
## contract: node.name == str(peer_id), guaranteed set before this node was
## ever replicated). Runs before anything else touches this node this
## frame, so it's in place before the node's first _physics_process().
func _on_spawned(node: Node) -> void:
	# TK-P1-06 (code-review nit): guard against a non-numeric node.name before
	# int()-parsing it -- `_spawn_player()` always sets it to str(peer_id),
	# but a defensive check here costs nothing and prevents int("garbage")
	# silently coercing to 0 (which would hand this node's authority to peer
	# id 0 -- not a real peer id, since Godot peer ids start at 1) if this
	# node ever arrived with an unexpected name. Same check SpawnPointUtil.
	# is_local_peer_name() already relies on for its own String.is_valid_int()
	# guard, kept in sync here for the authority-assignment path.
	if not node.name.is_valid_int():
		GameLog.error(
			"[SPAWN] replicated node with non-numeric name '%s' -- refusing to assign authority" % node.name
		)
		return
	var owner_peer_id: int = int(node.name)
	node.set_multiplayer_authority(owner_peer_id)
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
