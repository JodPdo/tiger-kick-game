class_name TigerAbility
extends Ability
## TigerAbility -- base class for every Tiger-role ability (TK-P2-16 Step 3
## scaffold, gameplay-engineer). See
## Tiger_Kick_Project_Docs/02_Technical/Ability_System_Design.md §3/§6.
##
## Marker/extension point only -- no shared tiger-specific behavior exists
## yet. Concrete tiger abilities (design doc §6 catalog: Crouch, Lean,
## Pounce, Peek -- Sprint stays a MovementComponent primitive, NOT an
## ability, per design doc §3 "Sprint, Jump -- ไม่ใช่ ability") extend THIS
## instead of Ability directly. AbilityCatalog.abilities_for_role(&"tiger")
## is the single place that registers which TigerAbility subclasses exist
## (currently none -- see that file).
