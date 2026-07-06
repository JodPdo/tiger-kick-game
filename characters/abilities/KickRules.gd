class_name KickRules
## Pure, node-independent decision logic for Kick (TK-P2-01, gameplay-engineer).
## See Tiger_Kick_Project_Docs/02_Technical/Ability_System_Design.md §3
## ("testability" note: host_validate must be a thin shell around a pure
## static helper, same pattern as managers/TigerSelector.gd and
## networking/SpawnPointUtil.gd) and §7 Step 4.
##
## WHY THIS EXISTS (testability): KickAbility.host_validate() runs on the
## host, reads live CharacterBody3D.global_position off sibling Player nodes,
## and needs a scene tree + multiplayer context to exercise directly. The
## actual RANGE/TARGET-SELECTION decision has none of those dependencies, so
## it lives here as plain static functions GUT can call with hand-built
## Vector3s/Dictionaries -- no live peers, no scene tree, no Player.tscn.
##
## NOTE (scope, per the card): there is no Tiger/role state machine wired up
## yet (TK-P2-04/09 land later), so Kick currently targets the NEAREST OTHER
## player, full stop -- it does not know or care who "the Tiger" is. Once
## Player.role is real and populated, KickAbility.host_validate() should
## filter `candidates` down to players whose role == &"tiger" BEFORE calling
## nearest_target() below (a one-line change at the call site, not here --
## this file stays role-agnostic on purpose, same "decision logic has no
## opinion about callers" spirit as TigerSelector).

## True when `a` and `b` are within `range_m` of each other (inclusive).
## Pure Vector3 distance check -- no assumption about which is the kicker.
static func is_in_range(a: Vector3, b: Vector3, range_m: float) -> bool:
	return a.distance_to(b) <= range_m


## Pure cooldown decision (design doc §3 testability note names this exact
## pattern: "CooldownLedger.can_fire()"). True when enough time has passed
## since `last_fire_ms` to fire again. `last_fire_ms < 0` means "never fired
## yet" -- always allowed. Both KickAbility.can_activate() (owner-predicted,
## called with its own `_owner_last_fire_ms` ledger) and
## KickAbility.host_validate() (authoritative, called with its own
## `_host_last_fire_ms` ledger) share this ONE decision function so the two
## checks can never silently drift apart (e.g. one rounding differently) --
## only the ledger/clock source they are called with differs.
static func can_fire(last_fire_ms: int, cooldown_sec: float, now_ms: int) -> bool:
	if last_fire_ms < 0:
		return true
	return (now_ms - last_fire_ms) >= int(cooldown_sec * 1000.0)


## Picks the CLOSEST candidate to `self_position` that is within `range_m`,
## out of `candidates` (Array of {"id": Variant, "position": Vector3}).
## Returns that candidate's Dictionary unchanged (so the caller keeps
## whatever extra fields it put in, e.g. "id") or an EMPTY Dictionary ({})
## when nothing qualifies -- fail-safe, never null, mirrors
## AbilityCatalog.abilities_for_role()'s "empty Array not null" contract for
## the same reason (callers can uniformly check `.is_empty()`).
##
## Ties (two candidates at the exact same distance) resolve to whichever
## appears FIRST in `candidates` (strict `<` below, not `<=`) -- deterministic
## given a deterministic candidate order, no randomness here.
static func nearest_target(self_position: Vector3, candidates: Array, range_m: float) -> Dictionary:
	var best: Dictionary = {}
	var best_dist: float = INF
	for candidate in candidates:
		var pos: Vector3 = candidate.get("position")
		var dist: float = self_position.distance_to(pos)
		if dist <= range_m and dist < best_dist:
			best_dist = dist
			best = candidate
	return best
