extends Control
## WaitingRoom.gd (TK-P2-12, gameplay-engineer)
##
## Landing screen after Host/Join succeeds (replaces the old Phase 0
## behavior of jumping straight into TestArena, see MainMenu.gd
## _switch_to_waiting_room()). Shows the connected-player roster (kept
## identical on every machine, see below) and, host-only, a Start button.
##
## ROSTER SYNC DESIGN (host-authoritative, CLAUDE.md server authority):
## In Godot ENet client/server, a client multiplayer.get_peers() call only
## ever returns the host (id 1) -- clients cannot derive the full roster
## locally. So the HOST is the single source of truth: it builds the
## roster with RosterHelper.build_roster() (host id + connected peer ids)
## and broadcasts it to everyone -- including itself -- via
## @rpc("authority", "call_local", "reliable") _rpc_receive_roster(). Using
## call_local means the host updates its own UI through the exact same
## code path as every client, so there is no divergent host-local vs
## client-RPC logic to drift out of sync.
##
## SCENE-CHANGE RACE (the part of this design that actually matters):
## change_scene_to_file() is deferred, so there is a window where the host
## has already seen peer_connected (and broadcast a roster) before the
## newly-joined client own WaitingRoom node exists to receive that RPC --
## the RPC is simply dropped, and that client would sit with a stale or
## empty roster forever. Fixed with a client-hello handshake: every
## WaitingRoom _ready() sends @rpc("any_peer", "reliable")
## _rpc_client_hello() to the host (id 1); the host re-broadcasts the
## CURRENT roster on every hello, in addition to broadcasting on every
## peer_connected and peer_disconnected. A late-arriving client is
## therefore always guaranteed a fresh roster once its own node is ready
## to receive it, regardless of how the two scene switches (host and
## client) interleave. The host own WaitingRoom node is guaranteed to
## already exist before any client is even able to connect (hosting
## starts listening synchronously; joining is what a client does
## afterwards), so the host-side target of that hello RPC is never itself
## subject to the race.
##
## NODE PATH STABILITY: change_scene_to_file() frees the previous scene
## before instancing the new one, so the WaitingRoom scene root always
## ends up at the same path (/root/WaitingRoom) on every peer that
## switches to it -- required for RPCs to resolve to the same node on
## every machine.
##
## MATCH START (TK-P2-13, gameplay-engineer): host-authoritative "everyone
## jumps into the match together" broadcast, built by MIRRORING the roster
## broadcast pattern above exactly. _on_start_pressed() is host-only in code
## (defense in depth on top of the Start button already being hidden/disabled
## for clients, see _configure_start_button()) and additionally guards a
## minimum player count (MIN_PLAYERS_TO_START, see const doc) before doing
## anything. If both checks pass, the host calls the
## @rpc("authority", "call_local", "reliable") _rpc_start_match(), which is
## what actually switches EVERY peer -- host included, via call_local -- from
## this WaitingRoom scene into res://world/TestArena.tscn. "authority" is the
## real client-can-never-start guarantee: the engine rejects this RPC's body
## from running anywhere unless the SENDER is the node's multiplayer
## authority (the host, never overridden), so a client cannot trigger a match
## start even by spoofing the call directly.
##
## PLAYERSPAWNER TIMING RISK (flagged for code-review/QA, not fixed here --
## spawn/authority wiring is network-engineer's territory per
## .claude/agents/gameplay-engineer.md §6): networking/PlayerSpawner.gd only
## ever spawns a Player for a peer in two places -- (a) its own _ready(), for
## `multiplayer.get_unique_id()` IF is_server(), and (b)
## NetworkManager.peer_connected, a ONE-TIME signal that fires exactly once,
## at the moment a given peer's ENet connection is established. Before
## TK-P2-12/13, MainMenu switched every peer into TestArena immediately on
## server_started/connection_succeeded, so PlayerSpawner's node existed
## before any *other* peer connected, and peer_connected firing later (as
## each client joined) is what spawned every non-host Player -- (a) and (b)
## together covered everyone. NOW, with the Waiting Room in between, every
## peer's peer_connected has ALREADY fired (while everyone was sitting in
## WaitingRoom, before PlayerSpawner's node even existed) by the time Start
## is pressed -- so when _rpc_start_match() below switches everyone into
## TestArena simultaneously, PlayerSpawner._ready() only self-spawns the
## HOST (path (a)); path (b) never fires again for the already-connected
## clients, since peer_connected is not re-emitted on a scene switch. Traced
## through, this means only ONE Player (the host's) would be spawned and
## replicated to everyone -- every client would land in TestArena with no
## controllable Player of their own. This is a real risk under the NEW
## Start-from-WaitingRoom timing, not a hypothetical: it needs a
## PlayerSpawner-side fix (e.g. also spawning every already-connected peer,
## not just self, on TestArena entry) before the human 2-window run can be
## expected to show "every window has exactly one controllable Player" --
## see HANDOFF.
##
## IDEMPOTENCY: _match_started (see var doc) guards _rpc_start_match() the
## same way _session_ended guards _leave()/_on_server_disconnected() below --
## change_scene_to_file() is deferred, so a double-press (or a duplicate/
## retried RPC) must not queue two scene switches.
##
## Reference: CLAUDE.md server authority; _backlog.json TK-P2-12, TK-P2-13.

const MAIN_MENU_SCENE: String = "res://ui/MainMenu.tscn"

## Match scene entered when the host starts (TK-P2-13). Runtime-only scene
## switch (change_scene_to_file), same pattern as MainMenu's
## _switch_to_waiting_room() and this file's own _return_to_main_menu().
const MATCH_SCENE: String = "res://world/TestArena.tscn"

## Minimum roster size required for the host to start a match (TK-P2-13).
## Set to 2 for Phase 2 so a single host+client pair can validate the flow;
## the GDD's real 4-8 player target is a Phase 3 design/balance tune (backlog
## explicitly calls this out as a placeholder) -- do not read this as the
## final value.
const MIN_PLAYERS_TO_START: int = 2

@onready var roster_list: ItemList = $MarginContainer/VBoxContainer/RosterList
@onready var roster_count_label: Label = $MarginContainer/VBoxContainer/RosterCountLabel
@onready var start_button: Button = $MarginContainer/VBoxContainer/ButtonRow/StartButton
@onready var leave_button: Button = $MarginContainer/VBoxContainer/ButtonRow/LeaveButton
@onready var status_label: Label = $MarginContainer/VBoxContainer/StatusLabel

## Latest roster applied locally (Array of {id:int, is_host:bool}, see
## RosterHelper.build_roster()). Always the last roster this machine
## RECEIVED (client) or BUILT-AND-SENT-TO-ITSELF (host via call_local) --
## never invented locally, per the no-desync rule in the class doc above.
var _current_roster: Array = []

## Guards against acting twice on the same session end (mirrors
## world/TestArena.gd _session_ended -- see that file for why).
var _session_ended: bool = false

## Guards against starting the match twice (TK-P2-13; see class doc
## IDEMPOTENCY). Set true the first time _rpc_start_match() runs on THIS
## machine (host included, via call_local) -- a second call (double-press or
## a duplicate/retried RPC) is a no-op.
var _match_started: bool = false


func _ready() -> void:
	status_label.text = ""
	roster_list.clear()

	start_button.pressed.connect(_on_start_pressed)
	leave_button.pressed.connect(_on_leave_pressed)

	NetworkManager.peer_connected.connect(_on_peer_connected)
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

	_configure_start_button()

	if NetworkManager.is_host():
		# Host is the source of truth -- build + broadcast (call_local also
		# updates this same node UI, see class doc).
		_broadcast_roster()
	else:
		# Client-hello handshake (see class doc SCENE-CHANGE RACE): asks
		# the host to re-send the current roster now that this node exists.
		rpc_id(1, "_rpc_client_hello")


# --- host-side: build + broadcast --------------------------------------------

func _on_peer_connected(_id: int) -> void:
	# NetworkManager.peer_connected fires on every peer (see its doc), but
	# only the HOST sees every real client connect -- guard so a client
	# does not try to re-broadcast (it has no authority to anyway; this
	# just avoids a pointless blocked RPC attempt).
	if NetworkManager.is_host():
		_broadcast_roster()


func _on_peer_disconnected(_id: int) -> void:
	if NetworkManager.is_host():
		_broadcast_roster()


## Host-only: builds the current roster from NetworkManager and sends it to
## everyone (including itself, via call_local -- see class doc).
func _broadcast_roster() -> void:
	if not NetworkManager.is_host():
		return

	var host_id: int = multiplayer.get_unique_id()
	var connected_peer_ids: Array = NetworkManager.get_connected_peer_ids()
	var roster: Array = RosterHelper.build_roster(host_id, connected_peer_ids)
	var ids: PackedInt32Array = RosterHelper.roster_ids(roster)
	rpc("_rpc_receive_roster", ids, host_id)


## Host-authoritative roster push. "authority" restricts this to the node
## multiplayer authority (default authority = peer 1 = the host, never
## overridden here), so only the real host broadcast is accepted.
## "call_local" is what makes the host update through this exact same
## function instead of a separate local code path (see class doc).
@rpc("authority", "call_local", "reliable")
func _rpc_receive_roster(ids: PackedInt32Array, host_id: int) -> void:
	var connected_peer_ids: Array = []
	for id in ids:
		connected_peer_ids.append(id)
	_current_roster = RosterHelper.build_roster(host_id, connected_peer_ids)
	_refresh_roster_ui()


## Received on the HOST ONLY (any_peer, no call_local -- a client calling
## rpc_id(1, ...) runs this solely on peer 1). Re-broadcasts the current
## roster so a client whose WaitingRoom just became ready is guaranteed a
## fresh roster even if it missed an earlier peer_connected-triggered
## broadcast (see class doc SCENE-CHANGE RACE).
@rpc("any_peer", "reliable")
func _rpc_client_hello() -> void:
	if not multiplayer.is_server():
		return
	_broadcast_roster()


# --- UI -----------------------------------------------------------------

func _refresh_roster_ui() -> void:
	var my_id: int = multiplayer.get_unique_id()
	roster_list.clear()
	for entry in _current_roster:
		var is_you: bool = entry.id == my_id
		roster_list.add_item(RosterHelper.format_roster_entry(entry.id, entry.is_host, is_you))
	roster_count_label.text = "Players: %d" % _current_roster.size()


## Only the host sees or can use the Start button (TK-P2-12 DoD: only host
## sees the Start button). Hidden (not just disabled) for clients.
func _configure_start_button() -> void:
	var is_host: bool = NetworkManager.is_host()
	start_button.visible = is_host
	start_button.disabled = not is_host


## Host-only entry point for the Start button (TK-P2-13). Defense in depth:
## the button is already hidden/disabled for clients
## (_configure_start_button()) and _rpc_start_match() below is
## "authority"-gated so a client could never make it run remotely even by
## spoofing -- but a non-host code path calling this directly must still be
## unable to start a match, so the host-role check happens here too, not
## only in the UI wiring.
func _on_start_pressed() -> void:
	if not NetworkManager.is_host():
		return
	if _match_started:
		return

	if not RosterHelper.can_start_match(true, _current_roster.size(), MIN_PLAYERS_TO_START):
		status_label.text = "Need at least %d players to start (currently %d)." \
			% [MIN_PLAYERS_TO_START, _current_roster.size()]
		return

	GameLog.info("[WaitingRoom] Start pressed by host -- broadcasting match start (%d players)" \
		% _current_roster.size())
	rpc("_rpc_start_match")


## Host-authoritative match start (TK-P2-13). Mirrors _rpc_receive_roster()'s
## "authority" + "call_local" pattern exactly (see class doc): "authority"
## restricts this RPC's sender to the node's multiplayer authority (default
## authority = peer 1 = the host, never overridden), so the engine itself
## rejects a client trying to trigger this -- a client cannot start the
## match even by spoofing the call. "call_local" runs this SAME function on
## the host too, so every peer (host included) transitions into the match
## through identical code, not a separate host-local path.
##
## Idempotency: guarded by _match_started (see var doc) so a double-press (or
## a duplicate/retried reliable RPC) cannot queue two deferred scene
## switches.
@rpc("authority", "call_local", "reliable")
func _rpc_start_match() -> void:
	if _match_started:
		return
	_match_started = true

	GameLog.info("[WaitingRoom] match starting -- switching to %s" % MATCH_SCENE)
	var err: Error = get_tree().change_scene_to_file(MATCH_SCENE)
	if err != OK:
		push_warning("[WaitingRoom] failed to switch to %s (error %d)" % [MATCH_SCENE, err])


# --- leave / disconnect -------------------------------------------------

func _on_leave_pressed() -> void:
	_leave()


func _on_server_disconnected() -> void:
	if _session_ended:
		return
	_session_ended = true
	GameLog.info("[WaitingRoom] host disconnected -- returning to MainMenu")
	_return_to_main_menu()


func _leave() -> void:
	if _session_ended:
		return
	_session_ended = true
	GameLog.info("[WaitingRoom] player chose Leave -- disconnecting")
	NetworkManager.disconnect_from_game()
	_return_to_main_menu()


func _return_to_main_menu() -> void:
	var err: Error = get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	if err != OK:
		push_warning("[WaitingRoom] failed to switch to %s (error %d)" % [MAIN_MENU_SCENE, err])
