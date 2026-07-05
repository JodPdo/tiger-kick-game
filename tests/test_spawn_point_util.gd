extends GutTest
## Unit tests for networking/SpawnPointUtil.gd (TK-P1-04).
##
## Only the node-independent decisions used by PlayerSpawner.gd are covered
## here (spawn position spread + "is this spawned node mine" name matching).
## Live spawning/replication across peers is verified manually with 2+
## instances (see TK-P1-04 handoff note / net_smoke harness).

const SpawnPointUtilScript := preload("res://networking/SpawnPointUtil.gd")


func test_spawn_point_index_zero_is_on_positive_x_axis() -> void:
	var p: Vector3 = SpawnPointUtilScript.spawn_point(0, 4.0, 1.0)
	assert_almost_eq(p.x, 4.0, 0.001, "index 0 should sit at angle 0 (+X)")
	assert_almost_eq(p.z, 0.0, 0.001, "index 0 should have z == 0")
	assert_eq(p.y, 1.0, "spawn height should match the requested height")


func test_spawn_point_quarter_turn() -> void:
	# 2 of 8 slots = a quarter turn (TAU / 4).
	var p: Vector3 = SpawnPointUtilScript.spawn_point(2, 4.0, 1.0)
	assert_almost_eq(p.x, 0.0, 0.001, "index 2 (quarter turn) should have x == 0")
	assert_almost_eq(p.z, 4.0, 0.001, "index 2 (quarter turn) should have z == radius")


func test_spawn_point_wraps_after_max_slots() -> void:
	var p_wrapped: Vector3 = SpawnPointUtilScript.spawn_point(SpawnPointUtilScript.MAX_SPAWN_SLOTS)
	var p_zero: Vector3 = SpawnPointUtilScript.spawn_point(0)
	assert_almost_eq(p_wrapped.x, p_zero.x, 0.001, "spawn slots should wrap around after MAX_SPAWN_SLOTS")
	assert_almost_eq(p_wrapped.z, p_zero.z, 0.001, "spawn slots should wrap around after MAX_SPAWN_SLOTS")


func test_spawn_point_distinct_players_do_not_stack() -> void:
	var positions: Array = []
	for i in range(SpawnPointUtilScript.MAX_SPAWN_SLOTS):
		positions.append(SpawnPointUtilScript.spawn_point(i))
	for i in range(positions.size()):
		for j in range(i + 1, positions.size()):
			assert_gt(positions[i].distance_to(positions[j]), 0.5,
				"spawn points %d and %d should not overlap" % [i, j])


func test_is_local_peer_name_matches_own_id() -> void:
	assert_true(SpawnPointUtilScript.is_local_peer_name("1", 1), "node name '1' should match local id 1")
	assert_true(SpawnPointUtilScript.is_local_peer_name("42", 42), "node name '42' should match local id 42")


func test_is_local_peer_name_rejects_other_ids() -> void:
	assert_false(SpawnPointUtilScript.is_local_peer_name("2", 1), "node name '2' should not match local id 1")


func test_is_local_peer_name_rejects_non_numeric_names() -> void:
	assert_false(SpawnPointUtilScript.is_local_peer_name("Players", 1), "non-numeric node names must never match")
	assert_false(SpawnPointUtilScript.is_local_peer_name("", 1), "empty node name must never match")
