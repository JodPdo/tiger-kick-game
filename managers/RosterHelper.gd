class_name RosterHelper
## Pure, node-independent helper for building the Waiting Room roster
## (TK-P2-12). No Node / multiplayer / RPC access here -- everything is a
## static function over plain values so GUT can test it directly
## (tests/test_roster_helper.gd) and so WaitingRoom.gd has exactly one place
## that decides "what does the roster look like", whether that data arrived
## locally (host) or via RPC (client).
##
## WHY THIS EXISTS (server-authority + no-desync, see CLAUDE.md):
## In Godot ENet client/server, a client's multiplayer.get_peers() only ever
## returns the server (id 1) -- clients cannot derive the full player list
## themselves. Only the HOST sees peer_connected/peer_disconnected for every
## real client, so the host is the single source of truth: it builds the
## roster with build_roster() below and broadcasts it (see WaitingRoom.gd
## _broadcast_roster()). Clients must NEVER invent roster entries locally --
## they only ever display whatever roster the host most recently sent.
##
## Reference: CLAUDE.md server authority; _backlog.json TK-P2-12 DoD
## (ทุกเครื่องเห็นรายชื่อตรงกัน เข้า/ออกอัปเดตทันที).

## Builds an ordered, de-duplicated roster from a host id + a list of
## connected peer ids (as seen by the host via
## NetworkManager.get_connected_peer_ids(), i.e. multiplayer.get_peers(),
## which does NOT include the host's own id -- callers pass that separately
## as `host_id`). Also safe to call with `connected_peer_ids` that already
## contains `host_id` (e.g. a roster re-applied from an RPC payload on a
## client) -- duplicates collapse to one entry.
##
## Returns an Array of Dictionaries sorted by ascending id, each shaped as
## { "id": int, "is_host": bool }. Exactly one entry has is_host == true
## (the host_id entry), unless host_id itself is not a valid peer id (never
## happens in practice -- the host is always id 1 -- but this function does
## not special-case that; it simply includes whatever host_id it is given).
static func build_roster(host_id: int, connected_peer_ids: Array) -> Array:
	var seen: Dictionary = {} # id -> true; dedups host_id vs connected_peer_ids
	seen[host_id] = true
	for peer_id in connected_peer_ids:
		seen[peer_id] = true

	var ids: Array = seen.keys()
	ids.sort()

	var roster: Array = []
	for id in ids:
		roster.append({"id": id, "is_host": id == host_id})
	return roster


## Extracts just the ids from a roster (in the same order), packed for RPC
## transport (see WaitingRoom.gd _broadcast_roster() / _rpc_receive_roster()).
static func roster_ids(roster: Array) -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	for entry in roster:
		ids.append(entry.id)
	return ids


## Counts how many entries in a roster are marked as host. A valid roster
## must always have exactly 1 -- used for validation/asserts, mirroring
## TigerSelector.count_tigers().
static func count_hosts(roster: Array) -> int:
	var n: int = 0
	for entry in roster:
		if entry.is_host:
			n += 1
	return n


## Pure guard for TK-P2-13 (Host Start Match): whether the "Start Match"
## action is currently allowed, given who is asking and how many players are
## in the current roster. Node-independent (no Node/multiplayer/RPC access)
## so GUT can test the boundary conditions directly (tests/test_roster_helper.gd).
##
## This is DEFENSE IN DEPTH, not the only gate: the actual guarantee that a
## client can never start a match comes from the
## @rpc("authority", "call_local", "reliable") annotation on
## WaitingRoom._rpc_start_match() -- the engine itself refuses to run that
## RPC's body on any machine when the sender isn't the node's multiplayer
## authority (the host), so a client cannot trigger it even by spoofing a
## call. This function exists so the human-facing "why can't I start" (too
## few players) is decided by the exact same rule GUT verifies in isolation,
## rather than a second, potentially-drifting inline check in WaitingRoom.gd.
##
## `min_players` is passed in (not hardcoded here) because it is a Phase-3
## design/balance tune (see WaitingRoom.MIN_PLAYERS_TO_START) -- this helper
## only owns the comparison, not the value.
static func can_start_match(is_host: bool, player_count: int, min_players: int) -> bool:
	if not is_host:
		return false
	return player_count >= min_players


## Formats one roster row for display, e.g. "Player 3 (Host)" or
## "Player 5 (You)" or "Player 2 (Host) (You)". Pure string formatting, no
## Node/multiplayer access -- `is_you` is passed in by the caller (which
## knows its own multiplayer.get_unique_id()) so this stays testable.
static func format_roster_entry(peer_id: int, is_host: bool, is_you: bool = false) -> String:
	var label: String = "Player %d" % peer_id
	if is_host:
		label += " (Host)"
	if is_you:
		label += " (You)"
	return label
