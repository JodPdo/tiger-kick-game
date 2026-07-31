class_name KickTuning
extends Resource
## KickTuning (TK-P3-01, tools-devops) -- the actual, externally-editable
## home for every KickAbility (characters/abilities/KickAbility.gd) balance
## value. See Tiger_Kick_Project_Docs/01_Design/Game_Balance.md §4 (Kick
## range, Kick Stagger) and this repo's own
## Tiger_Kick_Project_Docs/02_Technical/Ability_System_Design.md §2 ("ค่าจูน
## เป็น @export วันนี้ -> อัปเกรดเป็น .tres ใน TK-P3-01 ได้โดยไม่แตะโครง" --
## "tunables are @export today -> upgrade to .tres in TK-P3-01, without
## touching the [component] structure") and Ability.gd's own `cooldown_sec`
## doc ("a later card (TK-P3-01) may upgrade this to a shared .tres resource
## without changing this contract") -- both anticipated exactly this file.
##
## WHY A RESOURCE, NOT JUST MORE @export (TK-P3-01 scoping note -- see this
## card's own backlog entry for the full investigation): every ability node
## in this codebase (Kick/Pounce/Tag) is constructed at RUNTIME via
## `Script.new()` (characters/abilities/AbilityController._instantiate_ability(),
## fed by AbilityCatalog's plain-Script catalog entries) -- confirmed by
## reading, not assumed. Unlike managers/GameManager.gd, managers/
## RoundManager.gd, managers/CountdownManager.gd, and characters/components/
## MovementComponent.gd/TagDetectorComponent.gd (all real, SAVED nodes inside
## world/TestArena.tscn or characters/Player.tscn, so a producer can already
## open that scene, select the node, and edit its @export Inspector
## properties -- Godot persists the override straight into the .tscn, no
## code touch, no rebuild), an ability node instantiated via `Script.new()`
## has NO saved scene instance anywhere to hold an Inspector override --
## its @export default is, in practice, indistinguishable from a hardcoded
## constant: the ONLY way to change it before this card was to open the
## .gd file and edit the literal. A `.tres` Resource asset sidesteps this
## entirely: it can be opened directly by double-clicking it in the
## FileSystem dock (Godot shows the same Inspector UI a scene-node override
## would) with ZERO dependency on any node ever being placed in a saved
## scene. This is the one genuine gap this card exists to close -- see this
## card's own backlog `fix_result` for the full per-file audit (every other
## design tunable in this codebase was ALREADY @export on a real saved scene
## node before this card started).
##
## CONTRACT PRESERVED (per the doc quotes above: "without changing this
## contract" / "โดยไม่แตะโครง"): KickAbility.gd keeps its own
## `kick_range_m`/`cooldown_sec`/`stagger_duration_sec`/
## `stagger_knockback_speed_mps` @export vars EXACTLY as before -- every
## existing caller (host_validate(), can_activate(), tests/test_kick_rules.gd)
## keeps reading those same members, unchanged. `_init()` now additionally
## copies this resource's fields onto them once, at construction time, so
## THIS file -- not the class-level literal default sitting next to each
## @export var -- is the actual value producer/designer edits going forward.
## The class-level literals are kept (a) so a bare `KickAbility.new()` never
## has a moment where these fields are unset/zero even before `_init()` runs
## (defense-in-depth, not load-bearing), and (b) because GDScript requires a
## concrete default expression on every @export var declaration -- they are
## intentionally kept numerically IDENTICAL to this resource's own defaults
## below so there is only ever one real number to know, even though there
## are two places it is written.
##
## Values below are the EXACT current placeholders, moved verbatim from
## KickAbility.gd -- this card is a refactor (value storage), not a balance
## change (CLAUDE.md change-control rule); no number here differs from what
## shipped before this card.

## Kick range, meters. Game_Balance.md §4: "Kick range | 1.5 m | เสนอ (จูน
## P3; host validate ระยะ kicker<->tiger)".
@export var kick_range_m: float = 1.5

## Minimum seconds between Kick activations. Game_Balance.md §4:
## "Cooldowns (Kick/Pounce) | TBD | จูน P3" -- 0.6s placeholder, unlocked.
@export var cooldown_sec: float = 0.6

## Kick Stagger duration, seconds. Game_Balance.md §4: "Kick Stagger | เสือเซ
## ~0.3s + ดันถอยเล็กน้อย (ห้าม stun เต็ม)" -- the one semi-locked number for
## this mechanic.
@export var stagger_duration_sec: float = 0.3

## Kick Stagger knockback speed, m/s, at the instant of impact (decays
## linearly to 0 over stagger_duration_sec -- see
## characters/components/StaggerRules.gd). NOT specified anywhere in the
## docs (Game_Balance.md §4 only locks "ดันถอยเล็กน้อย" -- "push back
## slightly" -- with no m/s figure); genuine placeholder pending designer
## lock, see KickAbility.gd's own doc for the "why 4.0" reasoning.
@export var stagger_knockback_speed_mps: float = 4.0
