class_name StaggerRules
## Pure, node-independent decision logic for Kick Stagger (TK-P2-17,
## gameplay-engineer). See Tiger_Kick_Project_Docs/01_Design/Game_Balance.md
## §4 ("Kick Stagger | เสือเซ ~0.3s + ดันถอยเล็กน้อย (ห้าม stun เต็ม)") and
## Tiger_Kick_Project_Docs/02_Technical/Ability_System_Design.md §3
## (testability note -- same "pure static helper, thin caller" split every
## other host_validate()/effect-decision file in this codebase uses: see
## characters/abilities/KickRules.gd, characters/abilities/PounceRules.gd,
## managers/SafeCircleRules.gd).
##
## WHY THIS EXISTS (testability): the two decisions Kick Stagger needs --
## "which direction is away from the kicker" and "how strong is the knockback
## right now, this far into the stagger window" -- have no scene-tree/live-
## clock dependency of their own. They live here as plain static functions
## GUT can call with hand-built Vector3s/ints, the same way
## PounceRules.can_fire() is a pure cooldown decision KickAbility/PounceAbility
## thin-shell around. The STATEFUL half (owning a start-time ledger, applying
## the result to actual velocity) stays on
## characters/components/MovementComponent.gd's start_stagger()/
## resolve_stagger_knockback() -- same split PounceRules (pure) vs.
## MovementComponent's start_pounce_burst()/resolve_horizontal_velocity()
## (stateful) already establishes for Pounce.
##
## "STAGGER, NOT STUN" (the hard requirement this whole card exists to
## satisfy, Game_Balance.md §4's own "ห้าม stun เต็ม"): decayed_speed() below
## is a straight LINEAR ramp-down to zero, not a flat "full knockback speed
## for the whole duration then instantly released" step function. Combined
## with MovementComponent.resolve_horizontal_velocity() ADDING (not
## overriding) this knockback on top of whatever the Tiger's own WASD input
## already produces (see that method's own doc for the full reasoning), the
## Tiger keeps full input agency for the ENTIRE stagger window -- turning,
## looking around, and fighting the knockback with WASD all still work from
## frame one. This is the deliberate design choice that keeps this a
## "stagger" (impaired, still playable) rather than a "stun" (input frozen) --
## see MovementComponent.gd's start_stagger()/resolve_stagger_knockback() doc
## for how the two pieces (pure decay here, additive-not-overriding blend
## there) combine to satisfy the card's hard requirement.

## Flat (Y=0), normalized direction pointing FROM `kicker_position` TOWARD
## `target_position` -- i.e. "away from the kicker", the direction Kick
## Stagger's knockback should push the target. Degenerate case (the two
## positions coincide on the XZ plane, distance ~0) returns Vector3.ZERO
## rather than dividing by zero in normalized() -- same "safe zero-length
## guard" shape characters/components/MovementComponent.gd's own
## start_pounce_burst() already uses for its own direction parameter. In real
## play this is effectively unreachable (KickAbility.host_validate() only
## ever confirms a kick when kicker and target are at least a hair apart --
## you cannot occupy the same position as the player you just kicked), so
## this guard exists purely as defense-in-depth against a degenerate call,
## the same "caller bug should never crash a pure function" spirit
## start_pounce_burst()'s own doc documents.
static func direction_away_from(kicker_position: Vector3, target_position: Vector3) -> Vector3:
	var flat: Vector3 = Vector3(
		target_position.x - kicker_position.x, 0.0, target_position.z - kicker_position.z
	)
	if flat.length() > 0.0001:
		return flat.normalized()
	return Vector3.ZERO


## Pure linear decay: the knockback's CURRENT speed, `elapsed_ms` into a
## stagger that started at `initial_speed` and fully decays to 0 by
## `duration_ms`. Returns `initial_speed` unchanged at elapsed_ms <= 0 (the
## instant of impact), 0.0 once elapsed_ms >= duration_ms (the stagger has
## fully run its course), and a straight linear ramp between those two points
## otherwise -- see the class doc above for why LINEAR (not a flat
## full-speed-then-cutoff step) is the deliberate "stagger, not stun" choice.
## Guards `duration_ms <= 0` (a degenerate/misconfigured tunable) by returning
## 0.0 rather than dividing by zero, mirroring
## characters/components/MovementComponent.gd's own
## speed_profile_multiplier() guard-then-safe-default shape for a
## degenerate divisor.
static func decayed_speed(elapsed_ms: int, duration_ms: int, initial_speed: float) -> float:
	if duration_ms <= 0 or elapsed_ms >= duration_ms:
		return 0.0
	if elapsed_ms <= 0:
		return initial_speed
	var remaining_fraction: float = 1.0 - (float(elapsed_ms) / float(duration_ms))
	return initial_speed * remaining_fraction
