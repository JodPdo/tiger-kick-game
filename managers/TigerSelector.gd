class_name TigerSelector
## Pure, node-independent helper for choosing the first Tiger and assigning roles.
##
## WHY THIS EXISTS (testability):
## The real selection runs host-authoritative inside GameManager/RoundManager
## and touches `multiplayer.get_peers()` / RPC, which is hard to unit-test.
## So the *decision logic* is extracted here as static, dependency-injected,
## node-independent functions. The RandomNumberGenerator is passed in, so tests
## are deterministic and no live peers are needed.
##
## Part of TK-P2-09 (สุ่มเสือตัวแรก, host-authoritative). GameManager should:
##   1) build the candidate id list (all peers + host id 1),
##   2) call pick_first_tiger() ON THE HOST ONLY,
##   3) broadcast the chosen id via @rpc(authority, call_local, reliable),
##   4) call build_role_map() on every peer to apply roles.
## Clients must NEVER run pick_first_tiger() themselves (would desync -> S1).
##
## Reference: Character/TDD Round Flow (Random Tiger), CLAUDE.md server authority.

const ROLE_TIGER: String = "tiger"
const ROLE_OUTER: String = "outer"
const NO_ID: int = -1


## Pick exactly one peer id from `ids` to become the first Tiger.
## `rng` is injected so callers/tests control the seed (host owns the RNG).
## `avoid` = previous Tiger's id for anti-repeat; when there are >= 2 distinct
## candidates the result will not equal `avoid`. If avoiding is impossible
## (empty pool after removal, or single candidate), `avoid` is ignored.
## Returns NO_ID (-1) when `ids` is empty.
static func pick_first_tiger(ids: Array, rng: RandomNumberGenerator, avoid: int = NO_ID) -> int:
	if ids.is_empty():
		return NO_ID

	var pool: Array = ids.duplicate()
	if avoid != NO_ID and pool.size() > 1:
		pool.erase(avoid)
	if pool.is_empty():
		# avoid was the only candidate -> fall back to original pool
		pool = ids.duplicate()

	return pool[rng.randi() % pool.size()]


## Build the role map for a round: {peer_id: ROLE_TIGER|ROLE_OUTER}.
## Exactly one id (`tiger_id`) becomes the Tiger; everyone else is Outer.
## If `tiger_id` is not in `ids`, NO id becomes Tiger (caller passed a stale id).
static func build_role_map(ids: Array, tiger_id: int) -> Dictionary:
	var roles: Dictionary = {}
	for id in ids:
		roles[id] = ROLE_TIGER if id == tiger_id else ROLE_OUTER
	return roles


## Count how many Tigers exist in a role map. Used for validation/asserts:
## a valid round must always have exactly 1.
static func count_tigers(roles: Dictionary) -> int:
	var n: int = 0
	for id in roles:
		if roles[id] == ROLE_TIGER:
			n += 1
	return n
