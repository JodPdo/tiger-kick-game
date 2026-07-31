extends Node
## RoleVisualComponent (TK-P3-13, gameplay-engineer) -- TEMPORARY, THROWAWAY
## visual role cue so the first real-people playtest (TK-P3-03) has a clean
## "who is the Tiger" signal to read player feedback against.
##
## WHY THIS EXISTS: every Player and the Tiger currently render as an
## identical bare white CapsuleMesh (characters/Player.tscn) -- real character
## art is explicitly Phase 4 scope (Character_Art_Bible.md), whose own
## section 5 "Tiger Indicator" is itself still fully unlocked/undecided. If
## TK-P3-03 ran with every player looking identical, any "I couldn't tell who
## the Tiger was" feedback would be scientifically useless -- impossible to
## separate a genuine core-loop readability problem from a mere artifact of
## zero visual distinction existing at all.
##
## HARD BOUNDARY (producer/design ruling, TK-P3-13): this is disposable test
## scaffolding, NOT a decision about Character_Art_Bible.md section 5 -- do
## not touch that document or unlock any of its fields from here, do not build
## an aura/particle/icon effect (a separate possible future direction, not
## this card), do not add a Settings toggle, do not design for permanence or a
## migration path. Phase 4 real character art will wholesale replace this
## component outright.
##
## WHAT THIS DOES: swaps the sibling MeshInstance3D's material color and
## uniform scale per role (see RoleVisualRules.gd for the actual color/scale
## table and the "reuse the Art Bible's locked height ratio" rationale).
## Purely cosmetic, client-visible local rendering only -- zero gameplay
## effect (does not touch CollisionShape3D/TagDetector, so hitboxes are
## unaffected), zero new RPC/host-authority surface: `role` itself is already
## host-authoritative and already replicates correctly (GameManager.
## apply_role_switch() -> Player.set_role(), broadcast to every peer), so this
## is pure local rendering reacting to an already-correct, already-synced
## value.
##
## SUBSCRIPTION PATTERN: same `role_changed` signal, same "self-apply current
## role once at _ready() (for a late-join/reconnect Tiger, design doc §9 open
## question), then subscribe for every subsequent swap" shape CameraComponent
## (TK-P2-05) and FootstepAudioComponent (TK-P3-12) already use for this exact
## signal. No new signal added.
##
## NOT GATED ON is_multiplayer_authority() (the one deliberate difference from
## CameraComponent's own `role_changed` reaction): CameraComponent's swap is
## owner-only because it drives that peer's OWN Camera3D/mesh-visibility,
## which only matters on the owning peer's own screen. This component's job is
## the opposite -- the DoD is "every peer visually agrees on which capsule is
## the Tiger", i.e. every peer must see the correct color/scale on EVERY OTHER
## Player's copy too, not just their own. Same reasoning
## FootstepAudioComponent's own class doc gives for why IT also runs
## ungated on every peer (every peer must hear every other Player's
## footsteps, not just their own) -- `role` arrives via a
## `call_local`/broadcast RPC (GameManager.apply_role_switch()), so
## Player.set_role() -- and therefore `role_changed` -- fires identically on
## every peer's own copy of every Player, own or remote.
##
## MATERIAL OWNERSHIP: assigns a fresh, per-instance StandardMaterial3D as
## `material_override` in _ready() rather than mutating Player.tscn's shared
## CapsuleMesh sub-resource -- Godot shares embedded sub-resources across every
## instantiated copy of a scene unless a node-local override is used, so
## mutating the mesh resource's own material in place would recolor every
## Player on screen at once instead of just this one.

@onready var _body: CharacterBody3D = get_parent() as CharacterBody3D
@onready var _mesh: MeshInstance3D = get_parent().get_node_or_null("MeshInstance3D") as MeshInstance3D

var _material: StandardMaterial3D = StandardMaterial3D.new()


func _ready() -> void:
	if _mesh:
		_mesh.material_override = _material
	_apply_role_visual(_body.role)
	_body.role_changed.connect(_apply_role_visual)


## Applies RoleVisualRules' color/scale table for `role` to the sibling
## MeshInstance3D. No-op (degrades silently) if a Player scene instance has no
## MeshInstance3D (e.g. a future stripped-down test double) -- same
## get_node_or_null degrade-silently posture FootstepAudioComponent's own
## `_footstep_player` lookup already uses.
func _apply_role_visual(role: StringName) -> void:
	if _mesh == null:
		return
	_material.albedo_color = RoleVisualRules.color_for_role(role)
	var scale_factor: float = RoleVisualRules.scale_for_role(role)
	_mesh.scale = Vector3(scale_factor, scale_factor, scale_factor)
