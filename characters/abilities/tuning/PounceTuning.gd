class_name PounceTuning
extends Resource
## PounceTuning (TK-P3-01, tools-devops) -- the actual, externally-editable
## home for every PounceAbility (characters/abilities/PounceAbility.gd)
## balance value. Same "Resource, not just @export" reasoning as
## characters/abilities/tuning/KickTuning.gd's own class doc -- read that
## file first, this one only documents what is PounceAbility-specific.
## See Tiger_Kick_Project_Docs/01_Design/Game_Balance.md §4 (Pounce burst).
##
## CONTRACT PRESERVED: PounceAbility.gd keeps its own
## `pounce_speed_mps`/`pounce_duration_sec`/`cooldown_sec` @export vars
## exactly as before -- `_init()` now copies this resource's fields onto
## them once, at construction. Values below are the EXACT current
## placeholders, moved verbatim from PounceAbility.gd -- a refactor, not a
## balance change.

## Burst speed, m/s. Game_Balance.md §4: "Pounce burst | ~8 m/s ระยะสั้น" --
## the closest-to-locked value in this file.
@export var pounce_speed_mps: float = 8.0

## Burst duration, seconds. NOT specified anywhere in the docs (Game_
## Balance.md §4 only locks the m/s figure) -- placeholder pending designer
## lock; see PounceAbility.gd's own doc for the "why 0.35" reasoning (one
## burst covers roughly 2.5-3m).
@export var pounce_duration_sec: float = 0.35

## Minimum seconds between Pounce activations. Game_Balance.md §4:
## "Cooldowns (Kick/Pounce) | TBD | จูน P3" -- deliberately longer than
## Kick/Tag's 0.6s (see PounceAbility.gd's own "hunt, not chase" reasoning:
## a short Pounce cooldown would let repeated bursts effectively let the
## Tiger chase).
@export var cooldown_sec: float = 2.0
