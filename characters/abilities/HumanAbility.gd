class_name HumanAbility
extends Ability
## HumanAbility -- base class for every Outer/human-role ability (TK-P2-16
## Step 3 scaffold, gameplay-engineer). See
## Tiger_Kick_Project_Docs/02_Technical/Ability_System_Design.md §3/§6.
##
## Marker/extension point only -- no shared human-specific behavior exists
## yet. Concrete human abilities (design doc §6 catalog: Kick = TK-P2-01,
## Hide, Emote, Jump-Kick) extend THIS instead of Ability directly, so a
## future shared human-only helper (e.g. a common windup pattern) has one
## place to land without touching Ability itself or TigerAbility's sibling
## hierarchy. AbilityCatalog.abilities_for_role(&"outer") is the single
## place that registers which HumanAbility subclasses exist (currently
## none -- see that file).
