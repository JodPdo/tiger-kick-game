extends Node
## NetworkManager (autoload singleton)
##
## Owns the ENetMultiplayerPeer for both host and client roles.
## Server-authoritative: the host is the single source of truth for any
## game-deciding state (who is the Tiger, tag/kick results, etc.). This
## script only manages connection lifecycle (host/join/disconnect) and
## re-emits Godot's multiplayer signals under a stable, documented API so
## other systems (MainMenu, GameManager) never touch `multiplayer` directly.
##
## Reference: Tiger_Kick_Project_Docs/02_Technical/TDD.pdf
##   §5 Autoloads  -- NetworkManager owns ENetMultiplayerPeer, host/join,
##                     peer_connected/disconnected.
##   §9 Network Flow & RPC -- server-authoritative model.
##
## All lifecycle events are logged with the "[NET]" prefix so QA / other
## agents can grep for connection confirmation (see TK-P0-06).

const DEFAULT_PORT: int = 7777
const DEFAULT_ADDRESS: String = "127.0.0.1"
const MAX_CLIENTS: int = 8 # 4-8 players per GDD/TDD §11 Game Balance

const _MIN_PORT: int = 1
const _MAX_PORT: int = 65535

signal server_started                 # emitted on host() success
signal connection_succeeded           # client connected to server
signal connection_failed              # client failed to connect
signal peer_connected(id: int)        # a peer joined (host & clients)
signal peer_disconnected(id: int)     # a peer left (host & clients)
signal server_disconnected            # TK-BUG-P1-02: fires on a CLIENT when
                                       # its connection to the host is lost
                                       # (host quit / crashed / kicked). Local
                                       # state is already torn down by the
                                       # time this fires (see
                                       # _on_server_disconnected below) --
                                       # listeners just need to react (e.g.
                                       # TestArena.gd returns to MainMenu).
                                       # Never fires on the host itself.

var _peer: ENetMultiplayerPeer = null

## TEST-HARNESS-ONLY opt-in (TK-P3-10), default OFF -- NOTHING in the shipped
## game ever sets this. When true AND this instance is the server, the arena's
## networking/PlayerSpawner.gd skips spawning a Player for the HOST's OWN peer
## id (see DedicatedHostRules + that file's _do_initial_barrier_spawn()), so the
## host runs as a TRUE dedicated server body: it never appears under Players/,
## is therefore never in managers/GameManager._current_player_ids()'s candidate
## pool (never pickable as first Tiger via characters... TigerSelector), and has
## no Players/<host_id> node to target, so it can never be Tagged/Kicked. This
## exists purely so the headless bot harness (tests/net/bot_outer_peer.gd,
## --role=host) cannot have its own idle, AI-less body picked/tagged into Tiger
## and softlock a match until RoundManager's round timeout (the live bug this
## card was filed for). Every OTHER connected peer (bots, and a real human client
## if one joins) still spawns and plays completely normally; the readiness-
## barrier / grace-timer machinery for those peers is untouched.
##
## WHY IT LIVES HERE (NetworkManager autoload) rather than on PlayerSpawner --
## same "record the autoload-vs-scene-local choice, don't resolve it silently"
## discipline as TK-P2-15:
##   1. The harness (TK-P3-11) sets this at HOST time -- right after host()
##      succeeds, BEFORE entering the Waiting Room -- when NO PlayerSpawner node
##      exists yet (it lives inside world/TestArena.tscn, not loaded until Start
##      Match). A scene-local PlayerSpawner property simply cannot be set then.
##   2. PlayerSpawner is scene-local and is recreated FRESH on every TestArena
##      entry (WaitingRoom -> Arena -> WaitingRoom -> 2nd Arena, per TK-P3-09's
##      re-arm). A scene-local flag would be lost on each scene switch and have
##      to be re-applied every match, with no natural harness hook to do so.
##      This autoload survives the WaitingRoom<->Arena boundary, so the flag is
##      set ONCE for the whole session and every fresh PlayerSpawner reads it.
## It is host-authoritative session config, never replicated: only the host's
## own PlayerSpawner reads it, and only to decide whether to spawn the host's own
## body -- it changes no client-side behavior and no game-deciding state.
var dedicated_host_no_self_spawn: bool = false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## Creates an ENetMultiplayerPeer server and starts listening for connections.
## Returns OK on success, or an Error code (e.g. ERR_INVALID_PARAMETER,
## ERR_ALREADY_IN_USE, ERR_CANT_CREATE) on failure. Never crashes on bad input.
func host(port: int = DEFAULT_PORT) -> Error:
	if _peer != null:
		push_warning("[NET] host() rejected: a peer is already active (call disconnect_from_game() first)")
		print("[NET] host() rejected: a peer is already active")
		return ERR_ALREADY_IN_USE
	if not _is_valid_port(port):
		push_warning("[NET] host() rejected: invalid port %s" % [port])
		print("[NET] host() rejected: invalid port %s" % [port])
		return ERR_INVALID_PARAMETER

	var enet_peer := ENetMultiplayerPeer.new()
	var err: Error = enet_peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		print("[NET] host() failed to create server on port %d (error code %d)" % [port, err])
		return err

	_peer = enet_peer
	multiplayer.multiplayer_peer = _peer

	print("[NET] server started on port %d (max clients: %d)" % [port, MAX_CLIENTS])
	server_started.emit()
	return OK


## Creates an ENetMultiplayerPeer client and starts connecting to address:port.
## Returns OK if the connection attempt was successfully started, or an Error
## code on invalid input / failure to create the client peer. Success or
## failure of the connection itself arrives asynchronously via the
## `connection_succeeded` / `connection_failed` signals.
func join(address: String = DEFAULT_ADDRESS, port: int = DEFAULT_PORT) -> Error:
	if _peer != null:
		push_warning("[NET] join() rejected: a peer is already active (call disconnect_from_game() first)")
		print("[NET] join() rejected: a peer is already active")
		return ERR_ALREADY_IN_USE
	if address.is_empty():
		push_warning("[NET] join() rejected: empty address")
		print("[NET] join() rejected: empty address")
		return ERR_INVALID_PARAMETER
	if not _is_valid_port(port):
		push_warning("[NET] join() rejected: invalid port %s" % [port])
		print("[NET] join() rejected: invalid port %s" % [port])
		return ERR_INVALID_PARAMETER

	var enet_peer := ENetMultiplayerPeer.new()
	var err: Error = enet_peer.create_client(address, port)
	if err != OK:
		print("[NET] join() failed to create client for %s:%d (error code %d)" % [address, port, err])
		return err

	_peer = enet_peer
	multiplayer.multiplayer_peer = _peer

	print("[NET] connecting to %s:%d ..." % [address, port])
	return OK


## Tears down the current peer (host or client) and returns to offline state.
## Safe to call even if there is no active peer.
func disconnect_from_game() -> void:
	if _peer == null:
		return

	print("[NET] disconnecting from game")
	multiplayer.multiplayer_peer = null
	_peer.close()
	_peer = null


## Host-only: force-disconnect a single connected peer. Used by
## networking/PlayerSpawner.gd's readiness-barrier grace release (TK-P2-13): a
## peer that never reaches the arena within the grace window is dropped rather
## than left in a silently path-cache-poisoned, Player-less limbo. Thin wrapper
## so callers never touch `multiplayer.multiplayer_peer` directly (see class
## doc). `force = true` tears the ENet connection down immediately instead of
## waiting for a graceful handshake. No-op if there is no active peer. The
## normal peer_disconnected signal fires for `id` as usual.
func disconnect_peer(id: int) -> void:
	if _peer == null:
		return
	print("[NET] force-disconnecting peer %d" % id)
	_peer.disconnect_peer(id, true)


func _is_valid_port(port: int) -> bool:
	return port >= _MIN_PORT and port <= _MAX_PORT


## Read-only helper (TK-P2-12): true if this instance is the host/server of
## the current session. Thin wrapper around multiplayer.is_server() so other
## systems (WaitingRoom, GameManager) never need to touch `multiplayer`
## directly (see class doc above). Guards on `_peer != null` because
## multiplayer.is_server() defaults to true when there is no active peer at
## all (SceneTree's default MultiplayerAPI treats unique_id 1 == server as
## the offline default) -- without that guard an offline instance would
## wrongly report itself as host.
func is_host() -> bool:
	return _peer != null and multiplayer.is_server()


## Read-only helper (TK-P2-12): ids of peers currently connected to
## `multiplayer`, per SceneMultiplayer.get_peers() -- does NOT include this
## instance's own id. On the HOST this is every connected client (the host
## itself is always id 1 and must be added by the caller, see
## managers/RosterHelper.build_roster()). On a CLIENT this is only ever
## [1] (the host) -- clients cannot see each other directly, which is
## exactly why the roster must be host-authoritative (see RosterHelper doc).
func get_connected_peer_ids() -> Array:
	return multiplayer.get_peers()


func _on_peer_connected(id: int) -> void:
	print("[NET] peer joined: %d" % id)
	peer_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	print("[NET] peer left: %d" % id)
	peer_disconnected.emit(id)


func _on_connected_to_server() -> void:
	print("[NET] connection succeeded (client connected to host)")
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	print("[NET] connection failed")
	multiplayer.multiplayer_peer = null
	_peer = null
	connection_failed.emit()


func _on_server_disconnected() -> void:
	print("[NET] server disconnected, returning to offline state")
	multiplayer.multiplayer_peer = null
	_peer = null
	server_disconnected.emit()
