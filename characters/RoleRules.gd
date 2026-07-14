class_name RoleRules
## Pure, node-independent decision logic for the Player Role state machine
## (TK-P2-04, gameplay-engineer). PlayerRoot (characters/Player.gd) holds the
## single `role: StringName` property (design doc §2 table); this file is the
## one place that knows which StringName VALUES are legal roles, following
## the same "pure static helper, thin caller" split every other
## host_validate()/state-transition file in this codebase uses (see
## managers/TagSequenceRules.gd, managers/TigerSelector.gd,
## characters/abilities/KickRules.gd).
##
## WHY THIS EXISTS (card note / gap found during investigation): before this
## card, Player.set_role(new_role) accepted ANY StringName with no validation
## at all -- a role state machine should own its own valid-transition guard
## rather than trusting every caller (GameManager today, possibly other
## callers later) to only ever pass &"outer"/&"tiger". This does not replace
## managers/TagSequenceRules.is_valid_role_swap() (that guard is about a
## SPECIFIC swap -- old_tiger_id != new_tiger_id, both ids >= 0 -- it lives on
## GameManager because only GameManager has peer ids to check); this guard is
## about the ROLE VALUE ITSELF being one PlayerRoot recognizes at all, and
## belongs next to Player.gd/role since that is where `role` actually lives.
##
## SCOPE: exactly two roles exist per the GDD/design doc (Outer, Tiger) --
## no "spectator"/"unassigned" role exists in Phase 2. If a future card adds
## one, it is added HERE first (single source of truth for "what is a legal
## role"), not by loosening Player.set_role()'s guard ad hoc.

const OUTER: StringName = &"outer"
const TIGER: StringName = &"tiger"

## Ordered for stable, deterministic log/error messages (%s % VALID_ROLES).
const VALID_ROLES: Array[StringName] = [OUTER, TIGER]


## True iff `role` is one of the two legal PlayerRoot role values.
static func is_valid_role(role: StringName) -> bool:
	return role == OUTER or role == TIGER
