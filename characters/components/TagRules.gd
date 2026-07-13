class_name TagRules
## Pure, node-independent decision logic for Tag DETECTION (TK-P2-02,
## gameplay-engineer). See
## Tiger_Kick_Project_Docs/02_Technical/Ability_System_Design.md §3
## ("testability" note: the real decision must be a pure static helper, same
## pattern as managers/TigerSelector.gd / networking/SpawnPointUtil.gd /
## characters/abilities/KickRules.gd) and §7 Step 4's precedent (Kick).
##
## WHY THIS EXISTS (testability, same rationale as KickRules.gd's own doc):
## TagDetectorComponent.gd is an Area3D -- it needs a live scene tree +
## physics server to produce real overlap results, and (per the card) only
## the HOST's own reading of it is authoritative. None of the actual
## RANGE/CANDIDATE-LIST decision needs any of that, so it lives here as
## plain static functions GUT can call with hand-built Vector3s/Dictionaries
## -- no live peers, no scene tree, no Area3D.
##
## SCOPE (per the card, mirrors KickRules.gd's own scope note verbatim): no
## Tiger/role state machine is wired up yet (TK-P2-04/09 land later), so this
## file is ROLE-AGNOSTIC ON PURPOSE -- it reports "which OTHER players are
## near me", full stop, same as Kick currently targets the nearest OTHER
## player with no "is this the Tiger" opinion. Once Player.role is real,
## the FUTURE caller (TK-P2-03's GameManager, or a TagAbility built on top of
## this file) should filter candidates down to role == &"outer" (from the
## Tiger's own detector) BEFORE calling nearest_candidate() below -- a
## one-line change at that call site, not here.
##
## NOT BUILT HERE (explicitly out of scope per the card): the Tag Sequence
## itself (grab/throw/transform/role-swap, TK-P2-03), any cooldown/action gate
## for actually tagging someone (TK-P2-03/TK-P2-08), and knockback/stagger
## (that is Kick's TK-P2-17, and has no Tag equivalent yet either).

## True when `a` and `b` are within `range_m` of each other (inclusive).
## Pure Vector3 distance check -- identical shape to KickRules.is_in_range(),
## deliberately duplicated rather than shared so Kick/Tag stay free to diverge
## later (e.g. Tag range vs Kick range tune independently, per Game_Balance.md).
static func is_in_range(a: Vector3, b: Vector3, range_m: float) -> bool:
	return a.distance_to(b) <= range_m


## Builds the raw candidate list a detector should consider: every entry of
## `all_players` (Array of {"id": Variant, "position": Vector3}) EXCEPT the
## one whose "id" equals `self_id` -- the pure-logic equivalent of
## TagDetectorComponent/KickAbility's scene-tree "if child == _body: continue"
## self-skip, extracted here so self-exclusion is independently GUT-testable
## with no live Player nodes at all. Order-preserving (stable filter, no
## reordering) so a deterministic input order stays deterministic through this
## step.
static func exclude_self(self_id, all_players: Array) -> Array:
	var out: Array = []
	for player in all_players:
		if player.get("id") == self_id:
			continue
		out.append(player)
	return out


## Filters `candidates` (Array of {"id": Variant, "position": Vector3}, already
## self-excluded by the caller -- see exclude_self() above) down to the ones
## within `range_m` of `self_position`. Returns ALL qualifying candidates (not
## just the nearest one, unlike KickRules.nearest_target()) because a Tiger's
## Tag detector must be able to report MULTIPLE nearby players at once (e.g.
## for a future GameManager to pick from, or a UI cue) -- see
## nearest_candidate() below for the "pick exactly one" step. Order-preserving
## (same relative order as `candidates`) -- never null, an empty Array for "no
## one in range", mirroring KickRules.nearest_target()'s "empty Dictionary, not
## null" fail-safe contract for the same reason (callers can uniformly check
## `.is_empty()`).
static func candidates_in_range(self_position: Vector3, candidates: Array, range_m: float) -> Array:
	var out: Array = []
	for candidate in candidates:
		var pos: Vector3 = candidate.get("position")
		if is_in_range(self_position, pos, range_m):
			out.append(candidate)
	return out


## Picks the CLOSEST candidate to `self_position` that is within `range_m`,
## out of `candidates` -- same exact shape/contract as
## KickRules.nearest_target() (empty Dictionary when nothing qualifies, ties
## resolve to whichever candidate appears FIRST in `candidates`, deterministic
## given a deterministic candidate order). Kept as a SEPARATE function from
## candidates_in_range() above (rather than "just take index 0 of that
## result") so a caller that only wants "the one nearest target" never has to
## know/rely on candidates_in_range()'s ordering guarantees -- this function
## makes its own tie-break contract explicit and independently testable.
static func nearest_candidate(self_position: Vector3, candidates: Array, range_m: float) -> Dictionary:
	var best: Dictionary = {}
	var best_dist: float = INF
	for candidate in candidates:
		var pos: Vector3 = candidate.get("position")
		var dist: float = self_position.distance_to(pos)
		if dist <= range_m and dist < best_dist:
			best_dist = dist
			best = candidate
	return best
