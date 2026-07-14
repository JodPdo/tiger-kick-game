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
## TK-P2-01 (design doc §7 Step 4): Outer's catalog now has its first real
## entry (KickAbility) -- registering it here was purely additive, exactly as
## the original scaffold note below predicted (no AbilityController/Player
## change was required).
##
## TK-P2-03: Tiger's catalog now has its first real entry (TagAbility) -- the
## Tag ACTION (step 1 of the 7-step Tag Sequence, see
## characters/abilities/TagAbility.gd's own class doc). Same purely-additive
## registration Kick already proved out. Crouch/Lean/Pounce/Peek (TK-P2-18/
## TK-P3-05) are the cards that append the rest of Tiger's design doc §6
## catalog.
##
## Original scaffold note (TK-P2-16, kept for history): every role's list
## used to be EMPTY -- no concrete ability existed yet.
## AbilityController.set_role() already calls abilities_for_role()
## unconditionally, so registering the first ability was purely additive
## here -- no AbilityController/Player change required.
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
			# TigerAbility catalog (design doc §6): Crouch, Lean, Pounce, Peek --
			# plus the Tag ACTION (TK-P2-03), which design doc §3's Resolution
			# table lists alongside Kick/Jump-Kick/Pounce but is not part of the
			# §6 body-language/movement list. TK-P3-05 (Crouch->Lean->Peek) and
			# TK-P2-18 (Pounce) are the cards that will each append one more entry.
			return [preload("res://characters/abilities/TagAbility.gd")]
		ROLE_OUTER:
			# HumanAbility catalog (design doc §6): Kick, Hide, Emote (+ Jump-Kick).
			# TK-P2-01 (Kick) is the first entry -- Hide/Emote/Jump-Kick are still
			# unimplemented future cards.
			return [preload("res://characters/abilities/KickAbility.gd")]
		_:
			return []
