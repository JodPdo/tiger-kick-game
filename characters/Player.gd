extends CharacterBody3D
## Player.gd -- reusable Player prefab (res://characters/Player.tscn).
##
## Scope of THIS card (TK-P1-01): scaffold only -- the node tree, placeholder
## visuals, and a synced transform. No movement/sprint (TK-P1-02), no real
## camera rig (TK-P1-03 replaces the placeholder Camera3D below with a
## SpringArm3D rig), no spawning (TK-P1-04) and no authority (TK-P1-05) --
## this script intentionally does not check
## `is_multiplayer_authority()` anywhere yet.
##
## Reference: Tiger_Kick_Project_Docs/02_Technical/TDD.pdf
##   §3 Folder Structure -- res://characters/ # Player, TigerController.
##   §4 Scene Tree        -- Player (n): CharacterBody3D, CameraRig,
##                            MultiplayerSynchronizer, KickHitbox (Area3D),
##                            TagArea (Area3D). KickHitbox/TagArea are
##                            deferred to TK-P2-01/TK-P2-02 -- out of scope
##                            here.
##   §8.1 Player Role State -- Idle -> Move -> Sprint/Kick/Caught -> Tiger ->
##                            Outer -> Idle. The state machine itself is
##                            future work (TK-P1-02 for Move/Sprint,
##                            TK-P2-0x for Tag Sequence/Role); this script is
##                            just the body the state machine will drive.
##
## Tunables (speed, sprint multiplier, etc.) are design-owned per TDD §11
## Game Balance and must NOT be hard-coded here -- they belong to TK-P1-02
## as @export vars / a shared Resource, not this scaffold.

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var camera: Camera3D = $Camera3D
@onready var synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer


func _ready() -> void:
	GameLog.debug("[Player] ready (name=%s)" % name)


## Movement/sprint is implemented in TK-P1-02. Left as an explicit, empty,
## documented stub (rather than omitted) so the next card has a clear,
## reviewed insertion point and CharacterBody3D's physics callback is never
## silently missing from the scene's intended contract.
func _physics_process(_delta: float) -> void:
	pass
