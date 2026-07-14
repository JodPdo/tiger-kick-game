class_name TagSequenceRules
## Pure, node-independent decision logic for the Tag SEQUENCE (TK-P2-03,
## gameplay-engineer) -- the 7-step grab->throw->transform->swap->exit->
## Playing flow GameManager.gd orchestrates. See
## Tiger_Kick_Project_Docs/02_Technical/Ability_System_Design.md §3
## ("testability" note -- decision logic must be a pure static helper, same
## pattern as managers/TigerSelector.gd / characters/abilities/KickRules.gd /
## characters/components/TagRules.gd) and §8 (GameManager ownership).
##
## WHY THIS EXISTS: GameManager.gd's start_tag_sequence()/_run_sequence() need
## a live scene tree, `multiplayer.is_server()`, Timers, and an @rpc to
## actually RUN the sequence -- none of that is needed to test the three
## decisions below, so they live here as plain static functions GUT can call
## with hand-built values, no scene tree, no live peers.
##
## SCOPE (per the card's scope note): this file covers ONLY the Tag
## Sequence's own decisions -- re-trigger guard, role-swap sanity, and the
## step-6 placeholder exit-position math (Safe Circle, TK-P2-06, does not
## exist yet -- see compute_exit_position()'s own doc). It does NOT decide
## who gets tagged (that is TagRules.nearest_candidate(), TK-P2-02, consumed
## by TagAbility.host_validate()) and does NOT implement any part of the
## full WaitingRoom->Countdown->Playing->MatchEnd match state machine
## (TK-P2-15, a separate still-todo card).

## MANDATORY re-trigger guard (per TK-P2-02's human-test finding: boundary
## jitter re-fired tag_target_in_range/left_range repeatedly within the same
## second while a player stood right at the ~2m range edge). A cooldown
## ledger ALONE is not enough here -- the lock must hold for the sequence's
## FULL duration (several seconds of stub timers, real animation later),
## not just one cooldown window -- so this is a SEPARATE guard from
## TagAbilityRules.can_fire(), checked first by TagAbility.host_validate()
## via GameManager.is_sequence_active().
static func can_start_sequence(is_active: bool) -> bool:
	return not is_active


## Sanity-checks a role-swap pair before GameManager broadcasts
## apply_role_switch (design doc §5 step 1): both ids must be valid
## (non-negative) peer ids, and the old Tiger must not equal the new Tiger --
## a Tag that somehow "targets" the Tiger itself (should already be
## impossible upstream, TagRules/TagDetectorComponent self-exclude) must
## never be allowed to reach an actual role broadcast.
static func is_valid_role_swap(old_tiger_id: int, new_tiger_id: int) -> bool:
	return old_tiger_id >= 0 and new_tiger_id >= 0 and old_tiger_id != new_tiger_id


## Step 6 PLACEHOLDER exit-position math (per the card: Safe Circle,
## TK-P2-06, does not exist yet -- this is explicitly NOT a real
## boundary-aware exit, just a "push the old tiger away from the arena
## center" stand-in GameManager uses so step 6 does something reasonable
## without blocking on TK-P2-06). Pushes `current_position` radially OUTWARD
## from the arena center (world origin, matching world/TestArena.tscn's own
## SafeCircleMarker, which is centered at the origin) to `exit_radius_m`,
## preserving Y (no vertical teleport) and using the CURRENT horizontal
## direction from center as the exit direction -- i.e. "walk further out the
## way you were already facing/standing", not toward any specific gate.
## Falls back to `default_direction` (horizontal component only) if
## `current_position` is (numerically) exactly at the center, where a
## "current direction from center" is undefined; falls back again to
## Vector3.FORWARD if `default_direction` is ALSO degenerate (e.g. straight
## up/down), so this function always returns a well-defined result.
static func compute_exit_position(
	current_position: Vector3,
	exit_radius_m: float,
	default_direction: Vector3 = Vector3.FORWARD
) -> Vector3:
	var horizontal: Vector3 = Vector3(current_position.x, 0.0, current_position.z)
	var direction: Vector3
	if horizontal.length() > 0.001:
		direction = horizontal.normalized()
	else:
		var fallback: Vector3 = Vector3(default_direction.x, 0.0, default_direction.z)
		direction = fallback.normalized() if fallback.length() > 0.001 else Vector3.FORWARD

	return Vector3(direction.x * exit_radius_m, current_position.y, direction.z * exit_radius_m)
