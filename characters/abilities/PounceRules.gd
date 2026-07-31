class_name PounceRules
## Pure, node-independent decision logic for Pounce (TK-P2-18, gameplay-
## engineer). See Tiger_Kick_Project_Docs/02_Technical/Ability_System_Design.md
## §3 ("testability" note, same pattern as characters/abilities/KickRules.gd /
## characters/abilities/TagAbilityRules.gd / managers/TigerSelector.gd) and §6
## (TigerAbility catalog: Crouch, Lean, Pounce, Peek).
##
## can_fire() below is the exact same time-math KickRules.can_fire()/
## TagAbilityRules.can_fire() already implement -- deliberately DUPLICATED
## here rather than shared, same "abilities stay free to diverge later"
## reasoning TagAbilityRules.gd's own doc already states (this is now a THIRD
## independent copy -- see that file's doc for the still-open "should this
## become a shared CooldownLedger" architecture question; not decided
## unilaterally here either, same as there).
##
## Unlike KickRules/TagRules, Pounce has NO target/range-selection logic at
## all -- Pounce is a movement burst, not a target-selecting ability (see
## characters/abilities/PounceAbility.gd's own class doc for the full scope
## boundary: Pounce moves the Tiger, it does not itself catch/tag anyone).
## This file is therefore just the cooldown ledger, nothing more.

## Pure cooldown decision. True when enough time has passed since
## `last_fire_ms` to fire again. `last_fire_ms < 0` means "never fired yet" --
## always allowed. Called with TWO independent ledgers by PounceAbility, same
## split KickAbility/TagAbility already document: `can_activate()`
## (owner-predicted, its own `_owner_last_fire_ms` ledger) and
## `host_validate()` (authoritative, its own `_host_last_fire_ms` ledger) must
## never be conflated, or an owner-side misprediction could desync the real
## cooldown.
static func can_fire(last_fire_ms: int, cooldown_sec: float, now_ms: int) -> bool:
	if last_fire_ms < 0:
		return true
	return (now_ms - last_fire_ms) >= int(cooldown_sec * 1000.0)
