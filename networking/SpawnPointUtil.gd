class_name SpawnPointUtil
## Pure, node-independent helpers for TK-P1-04 (MultiplayerSpawner: spawn a
## Player per peer id).
##
## WHY THIS EXISTS (testability): PlayerSpawner.gd itself extends
## MultiplayerSpawner and needs a live SceneTree + multiplayer peer to run,
## which is hard to unit-test (same rationale as managers/TigerSelector.gd).
## The two small decisions that DON'T need a live tree -- "where do I place
## the Nth spawned player" and "does this spawned node's name match the
## local peer id" -- are extracted here as static functions so GUT can cover
## them directly (tests/test_spawn_point_util.gd).
##
## Reference: Tiger_Kick_Project_Docs/02_Technical/TDD.pdf §9 Network Flow,
## §11 Game Balance (Players 4-8).

const DEFAULT_SPAWN_RADIUS: float = 4.0
const DEFAULT_SPAWN_HEIGHT: float = 1.0
## Balance doc caps lobbies at 8 players (TDD §11); spreading spawn points
## around a fixed number of slots keeps them evenly spaced regardless of
## join order, rather than deforming the circle as peers connect.
const MAX_SPAWN_SLOTS: int = 8


## Returns a deterministic spawn position for the `index`-th player spawned
## this round (0-based, e.g. join order), spread evenly around a circle of
## `radius` on the XZ plane at height `height`. No gameplay meaning yet --
## this only guarantees spawned players don't stack on top of each other.
static func spawn_point(index: int, radius: float = DEFAULT_SPAWN_RADIUS, height: float = DEFAULT_SPAWN_HEIGHT) -> Vector3:
	var slot: int = index % MAX_SPAWN_SLOTS
	var angle: float = slot * TAU / float(MAX_SPAWN_SLOTS)
	return Vector3(cos(angle) * radius, height, sin(angle) * radius)


## True when `node_name` (a spawned Player node's `.name`, expected to be
## set to `str(peer_id)` by PlayerSpawner) identifies the same peer as
## `local_unique_id` (typically `multiplayer.get_unique_id()`). Used to
## decide which spawned Player's Camera3D should become `current` -- exactly
## one, the local peer's own player (see PlayerSpawner._on_spawned).
static func is_local_peer_name(node_name: String, local_unique_id: int) -> bool:
	if not node_name.is_valid_int():
		return false
	return node_name.to_int() == local_unique_id
