class_name TagTuning
extends Resource
## TagTuning (TK-P3-01, tools-devops) -- the actual, externally-editable home
## for every TagAbility (characters/abilities/TagAbility.gd) balance value.
## Same "Resource, not just @export" reasoning as
## characters/abilities/tuning/KickTuning.gd's own class doc -- read that
## file first, this one only documents what is TagAbility-specific.
##
## NOT the same tunable instance as characters/components/
## TagDetectorComponent.gd's own `tag_range_m` @export (that file is a real,
## saved Player.tscn node -- already Inspector-tunable there, deliberately
## left untouched by this card, see this card's own backlog `fix_result` for
## why) -- TagDetectorComponent's sensor range and TagAbility's own grab
## range are independent values that happen to share a default today (both
## 2.0m, per TagAbility.gd's own doc), each retunable separately once a
## designer actually locks them.
##
## CONTRACT PRESERVED: TagAbility.gd keeps its own `tag_range_m`/
## `cooldown_sec` @export vars exactly as before -- `_init()` now copies
## this resource's fields onto them once, at construction. Values below are
## the EXACT current placeholders, moved verbatim from TagAbility.gd -- a
## refactor, not a balance change.

## Tag (grab) range, meters. No locked Game_Balance.md entry yet -- matches
## TagDetectorComponent.tag_range_m's own placeholder default (2.0m) so the
## Tiger's grab range agrees with the sensor that feeds its candidate list.
@export var tag_range_m: float = 2.0

## Minimum seconds between Tag activations. No locked Game_Balance.md entry
## yet -- same placeholder/rationale as KickAbility's own cooldown_sec.
@export var cooldown_sec: float = 0.6
