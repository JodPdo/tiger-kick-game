class_name AbilityCatalog
## AbilityCatalog -- pure, static, node-independent registry: role -> the
## ordered list of ability scenes/scripts that role should have (TK-P2-16
## Step 3, gameplay-engineer). See
## Tiger_Kick_Project_Docs/02_Technical/Ability_System_Design.md §2/§6/§7.
##
## THE single place to touch when registering a new ability (design doc §7
## Step 4 DoD: "เพิ่ม ability = 1 ไฟล์ + 1 บรรทัด catalog" -- one new ability
## file that extends HumanAbility/TigerAbility, plus one line appended to
## the matching Array below). Order is deterministic and must stay IDENTICAL
## on every peer: AbilityController.set_role() rebuilds a Player's ability
## child nodes from this exact list on every peer independently, so any
## peer disagreeing about what a role's ability set is would desync which
## abilities exist, not just their results.
##
## SCAFFOLD (this step): every role's list is EMPTY -- no concrete ability
## exists yet (Kick lands in TK-P2-01 / design doc §7 Step 4, right after
## this card). AbilityController.set_role() already calls
## abilities_for_role() unconditionally, so registering the first ability
## later is purely additive here -- no AbilityController/Player change
## required.
##
## Pattern matches managers/TigerSelector.gd and networking/SpawnPointUtil.gd:
## a plain `class_name` with no `extends` (implicit Object), only static
## functions, fully GUT-testable with no scene tree/live peers.

const ROLE_TIGER: StringName = &"tiger"
const ROLE_OUTER: StringName = &"outer"


## Returns a NEW Array of ability entries (PackedScene or Script, per
## AbilityController._instantiate_ability()) to instantiate for `role`.
## Unknown/unassigned roles get an empty array -- fail-safe (no abilities
## rather than a crash on a typo'd role), matching the "fail closed" spirit
## of Ability's own HOST_AUTHORITATIVE default.
##
## Returns a fresh Array literal on every call (never a shared/cached
## reference) so a caller mutating the returned Array (e.g.
## AbilityController iterating + appending scratch state) can never corrupt
## what the NEXT call returns.
static func abilities_for_role(role: StringName) -> Array:
	match role:
		ROLE_TIGER:
			# TigerAbility catalog (design doc §6): Crouch, Lean, Pounce, Peek.
			# None implemented yet -- TK-P3-05 (Crouch->Lean->Peek body language)
			# and TK-P2-18 (Pounce) are the cards that will each append one entry.
			return []
		ROLE_OUTER:
			# HumanAbility catalog (design doc §6): Kick, Hide, Emote (+ Jump-Kick).
			# None implemented yet -- TK-P2-01 (Kick) is the very next card and
			# will append the first entry here.
			return []
		_:
			return []
