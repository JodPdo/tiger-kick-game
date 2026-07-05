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

var _players_root: Node3D
var _spawn_count: int = 0


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
