extends GutTest
## Unit tests for managers/RosterHelper.gd -- Waiting Room roster logic (TK-P2-12).
##
## Only the pure decision/formatting logic is tested here (node-independent,
## no live peers/RPC/scene tree). Live "every machine sees the same roster,
## join/leave updates in real time" verification is an Integration/manual
## 2-window check (see HANDOFF), same split as test_tiger_assignment.gd.
##
## NOTE: Requires the GUT addon (TK-PX-07). Ready to run once GUT is present.

const RosterHelperScript := preload("res://managers/RosterHelper.gd")

const HOST_ID: int = 1


# --- build_roster --------------------------------------------------------

func test_build_roster_host_only() -> void:
	var roster: Array = RosterHelperScript.build_roster(HOST_ID, [])
	assert_eq(roster.size(), 1, "host-only session has exactly one roster entry")
	assert_eq(roster[0].id, HOST_ID)
	assert_true(roster[0].is_host, "the single entry must be marked as host")


func test_build_roster_includes_host_and_clients() -> void:
	var roster: Array = RosterHelperScript.build_roster(HOST_ID, [2, 3, 4])
	assert_eq(roster.size(), 4, "host + 3 clients = 4 roster entries")
	var ids: Array = []
	for entry in roster:
		ids.append(entry.id)
	assert_true(ids.has(HOST_ID))
	assert_true(ids.has(2))
	assert_true(ids.has(3))
	assert_true(ids.has(4))


func test_build_roster_exactly_one_host_entry() -> void:
	var roster: Array = RosterHelperScript.build_roster(HOST_ID, [5, 6, 7])
	assert_eq(RosterHelperScript.count_hosts(roster), 1,
		"a valid roster must always have exactly one host entry")


func test_build_roster_sorted_ascending_by_id() -> void:
	var roster: Array = RosterHelperScript.build_roster(HOST_ID, [9, 3, 6])
	var ids: Array = []
	for entry in roster:
		ids.append(entry.id)
	assert_eq(ids, [1, 3, 6, 9], "roster must be sorted ascending by peer id")


func test_build_roster_dedups_when_peer_list_already_has_host_id() ->  void:
	# Simulates re-applying a roster from an RPC payload that already
	# contains the host id (see WaitingRoom._rpc_receive_roster()).
	var roster: Array = RosterHelperScript.build_roster(HOST_ID, [HOST_ID, 2, 2, 3])
	assert_eq(roster.size(), 3, "duplicate ids must collapse to one entry each")


func test_build_roster_empty_peer_list_is_safe() -> void:
	var roster: Array = RosterHelperScript.build_roster(HOST_ID, [])
	assert_eq(roster.size(), 1, "no clients connected still yields a valid one-entry roster")


# --- join/leave real-time update simulation --------------------------------

func test_roster_grows_on_join_and_shrinks_on_leave() -> void:
	var after_join: Array = RosterHelperScript.build_roster(HOST_ID, [2])
	assert_eq(after_join.size(), 2, "roster grows by one when a peer joins")

	var after_second_join: Array = RosterHelperScript.build_roster(HOST_ID, [2, 3])
	assert_eq(after_second_join.size(), 3, "roster grows again on a second join")

	var after_leave: Array = RosterHelperScript.build_roster(HOST_ID, [3])
	assert_eq(after_leave.size(), 2, "roster shrinks when a peer leaves (id 2 gone)")
	var remaining_ids: Array = []
	for entry in after_leave:
		remaining_ids.append(entry.id)
	assert_false(remaining_ids.has(2), "the peer that left must not remain in the roster")


# --- roster_ids (RPC transport packing) -------------------------------------

func test_roster_ids_matches_roster_order() -> void:
	var roster: Array = RosterHelperScript.build_roster(HOST_ID, [4, 2])
	var ids: PackedInt32Array = RosterHelperScript.roster_ids(roster)
	assert_eq(Array(ids), [1, 2, 4], "roster_ids must mirror the sorted roster order")


# --- format_roster_entry ----------------------------------------------------

func test_format_roster_entry_plain() -> void:
	assert_eq(RosterHelperScript.format_roster_entry(3, false), "Player 3")


func test_format_roster_entry_host() -> void:
	assert_eq(RosterHelperScript.format_roster_entry(1, true), "Player 1 (Host)")


func test_format_roster_entry_you() -> void:
	assert_eq(RosterHelperScript.format_roster_entry(2, false, true), "Player 2 (You)")


func test_format_roster_entry_host_and_you() -> void:
	assert_eq(RosterHelperScript.format_roster_entry(1, true, true), "Player 1 (Host) (You)")


# --- can_start_match (TK-P2-13 Host Start Match guard) ----------------------

func test_can_start_match_host_with_enough_players() -> void:
	assert_true(RosterHelperScript.can_start_match(true, 2, 2),
		"host with exactly the minimum player count may start")


func test_can_start_match_host_with_more_than_enough_players() -> void:
	assert_true(RosterHelperScript.can_start_match(true, 8, 2),
		"host with more than the minimum player count may start")


func test_can_start_match_client_never_allowed() -> void:
	assert_false(RosterHelperScript.can_start_match(false, 8, 2),
		"a non-host is never allowed to start, regardless of player count")


func test_can_start_match_host_below_minimum() -> void:
	assert_false(RosterHelperScript.can_start_match(true, 1, 2),
		"host with fewer than the minimum player count may not start")


func test_can_start_match_boundary_one_below_minimum() -> void:
	assert_false(RosterHelperScript.can_start_match(true, 3, 4),
		"one below a higher minimum must still be rejected (boundary check)")


func test_can_start_match_boundary_exactly_at_minimum() -> void:
	assert_true(RosterHelperScript.can_start_match(true, 4, 4),
		"exactly at a higher minimum must be accepted (boundary check)")
