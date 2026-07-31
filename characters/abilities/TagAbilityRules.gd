class_name TagAbilityRules
## Pure, node-independent decision logic for the Tag ACTION (TagAbility,
## TK-P2-03, gameplay-engineer). See
## Tiger_Kick_Project_Docs/02_Technical/Ability_System_Design.md §3
## ("testability" note, same pattern as managers/TigerSelector.gd /
## characters/abilities/KickRules.gd) and §7 Step 4's precedent (Kick).
##
## NOT to be confused with characters/components/TagRules.gd (TK-P2-02,
## closed) -- that file is Tag DETECTION logic (candidate list / range /
## nearest-picking), consumed here unchanged by TagAbility.host_validate().
## This file only adds the one piece of decision logic Tag DETECTION never
## needed: the Tag ACTION's own cooldown ledger.
##
## can_fire() below is the exact same time-math
## characters/abilities/KickRules.can_fire() already implements --
## deliberately DUPLICATED here rather than shared, same "Kick/Tag stay free
## to diverge later" reasoning characters/components/TagRules.gd's own doc
## already states for is_in_range() vs KickRules.is_in_range(). Design doc
## §3's testability note names this exact shape generically
## ("CooldownLedger.can_fire()") as a hint that it COULD be extracted and
## shared one day -- but with only two independent copies so far (Kick,
## Tag), that coupling is not yet worth it; a third ability needing the
## identical formula would be the point to actually build a shared
## CooldownLedger. Flagging this explicitly as a design/architecture
## question, not deciding it unilaterally here.

## Pure cooldown decision. True when enough time has passed since
## `last_fire_ms` to fire again. `last_fire_ms < 0` means "never fired yet"
## -- always allowed. Called with TWO independent ledgers by TagAbility, same
## split KickAbility already documents: `can_activate()` (owner-predicted,
## `_owner_last_fire_ms`) and `host_validate()` (authoritative,
## `_host_last_fire_ms`) must never be conflated, or an owner-side
## misprediction could desync the real cooldown.
static func can_fire(last_fire_ms: int, cooldown_sec: float, now_ms: int) -> bool:
	if last_fire_ms < 0:
		return true
	return (now_ms - last_fire_ms) >= int(cooldown_sec * 1000.0)
