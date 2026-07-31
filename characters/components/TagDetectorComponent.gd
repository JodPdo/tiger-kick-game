extends Area3D
## TagDetectorComponent (TK-P2-02, gameplay-engineer) -- "Area3D around the
## tiger, detects players who come near" (card title, translated). Part of
## the Player component tree (see
## Tiger_Kick_Project_Docs/02_Technical/Ability_System_Design.md section 2):
##   Player -> MovementComponent - CameraComponent - AbilityController -> [abilities]
##          -> TagDetector (Area3D, THIS component)
##
## PLACEMENT DECISION (per the card: "decide the correct home for the
## DETECTION layer"): this is NOT an Ability. Section 3's Resolution table
## lists "Tag" as HOST_AUTHORITATIVE, but that describes a future TAG ACTION
## (grab/catch, which decides the game) -- this card is explicitly scoped to
## DETECTION only ("Do NOT build the Tag Sequence... Do not build the actual
## tag action/cooldown beyond what detection needs", per the card). A sensor
## that only reports proximity has nothing that needs AbilityController's
## RPC surface (no player input triggers it, no cooldown, no win/lose
## result) -- it is a passive, continuous, ROLE-AGNOSTIC observation, same
## shape as MovementComponent/CameraComponent: a plain child Node (here, an
## Area3D is literally the node the card asks for) sibling of the other
## components, not nested under AbilityController. Section 8's ownership
## table still holds: GameManager (TK-P2-03, later) will own the 7-step Tag
## Sequence and is the intended CONSUMER of this component's signals/query
## below; this component owns detection only.
##
## SCOPE (mirrors characters/components/TagRules.gd's own note verbatim --
## read that file's header too): no Tiger/role state machine exists yet
## (TK-P2-04/09), so EVERY Player gets one of these, and it reports EVERY
## other overlapping Player, full stop -- there is no "am I the Tiger" check
## anywhere in this file. The future "only the Tiger's detector counts /
## only report non-Tigers" role-filter is a one-line change at the FUTURE
## caller (GameManager reading role == tiger before trusting a given
## Player's detector, or filtering candidates to role == outer), not here --
## this component stays role-agnostic on purpose, same "decision logic has
## no opinion about callers" spirit as TigerSelector/KickRules.
##
## HOST-AUTHORITATIVE CONTRACT (the load-bearing part of this card): Area3D
## physics overlap is LOCAL to each peer's own physics world -- there is no
## network-level Area3D sync. Every peer's own copy of every Player's
## TagDetector runs (cheap, harmless: it only ever tracks physics overlap
## against replicated positions already flowing over channel A, no new
## traffic). But per CLAUDE.md ("state that decides the game is
## host-authoritative") and design doc section 3 ("cheating this and winning
## the game = HOST"), a client's own local overlap result must NEVER be
## trusted as "who is actually in tag range" for a real game decision -- only
## the HOST's own reading of ITS OWN Player instances' detectors is
## authoritative, the exact same caveat KickAbility.host_validate() already
## lives with (host sees a client slightly behind that client's own screen,
## design doc section 4 note). Enforced here by GATING EMISSION, not
## detection: tag_target_in_range / tag_target_left_range below only ever
## fire when multiplayer.is_server() is true (fail-closed, same shape as
## KickAbility.host_validate()'s own assert(multiplayer.is_server())) -- a
## non-host peer's detector still tracks membership internally
## (get_candidates_in_range() below still works everywhere, e.g. for a
## future local-only prediction/UI cue), it just never emits the signal a
## future GameManager could mistake for authoritative. GameManager (TK-P2-03)
## is expected to read this ONLY from the Player tree it reaches on the
## HOST's own machine (its own local scene tree, same as every other
## host-authoritative read in this codebase) -- there is deliberately no RPC
## here at all; this card only makes the HOST's own local reading
## trustworthy, it does not transport that reading anywhere.
##
## HAND-OFF CONTRACT for TK-P2-03 (Tag Sequence / GameManager, the intended
## consumer): two ways to consume this, pick whichever fits that card's flow
## better --
##   1) EVENT-DRIVEN: connect to tag_target_in_range(tagger_id: int,
##      target_id: int) / tag_target_left_range(tagger_id: int, target_id:
##      int) on the HOST's own copy of a Player's TagDetector (only fires
##      host-side, see above). ids are peer ids (int), same convention as
##      KickAbility's ctx.get("sender_id")/result dict.
##   2) POLL: call get_candidates_in_range() -> Array (shape identical to
##      KickRules' candidate Dictionaries: {"id": int, "position": Vector3})
##      at the moment the Tag Sequence needs to decide who to grab, then feed
##      it straight into TagRules.nearest_candidate(tiger.global_position,
##      candidates, tag_range_m) (or TagRules.candidates_in_range() for the
##      full list) -- this works identically on host regardless of
##      is_server(), the CALLER is what must only ever act on it host-side.
##
## RESIDUAL GLUE GAP (flagged for QA per the card, same shape as TK-P2-19
## which followed up on Kick's own RPC wire-routing gap): GUT can fully cover
## TagRules.gd's pure decision logic with no scene tree at all, but "does a
## real Area3D overlap actually fire body_entered/body_exited across two
## networked peers, and does the host-only emit gate actually hold" is
## scene-tree/multiplayer wiring GUT cannot exercise -- this needs a manual
## 2-instance check (see this card's HANDOFF note).

## Tag range, meters. UNLIKE Kick range (Game_Balance.md "Kick range | 1.5 m"),
## there is NO locked/proposed Tag range value in Game_Balance.md yet -- this
## is a placeholder pending designer input (Phase 3 tune, same "expose
## design-owned tunables, never hard-code" rule CLAUDE.md sets for every
## other balance value in this codebase, e.g. KickAbility.kick_range_m /
## MovementComponent.jump_speed's own placeholder notes). Picked slightly
## larger than Kick range (1.5 m) as a placeholder on the reasoning that the
## Tiger must be able to grab someone who just kicked and is now fleeing --
## NOT a designer ruling, flag this explicitly for designer to add a real
## entry to Game_Balance.md.
@export var tag_range_m: float = 2.0

## Cached parent Player body -- this component is a direct child of Player
## (Player -> TagDetector, see the class doc tree above), same @onready-cache
## pattern as MovementComponent/CameraComponent/KickAbility's own _body.
@onready var _body: CharacterBody3D = get_parent() as CharacterBody3D

## The physics shape actually driving overlap detection -- kept as a typed
## ref so _ready() can sync its radius to tag_range_m (below), same "tunable
## drives the real shape, never hard-coded in the .tscn alone" spirit as
## every other @export in this codebase.
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D

## HOST-ONLY (see the class doc's "HOST-AUTHORITATIVE CONTRACT" above):
## fires ONLY when multiplayer.is_server() is true. tagger_id/target_id are
## peer ids (int), derived from Player node names (the existing node.name ==
## str(peer_id) naming contract, TK-BUG-P1-01).
signal tag_target_in_range(tagger_id: int, target_id: int)
signal tag_target_left_range(tagger_id: int, target_id: int)

## Syncs the physics shape to the exported tunable (in case a scene override
## changes tag_range_m from the .tscn's own shipped default -- same "tunable
## is the source of truth" reasoning KickAbility's kick_range_m already
## documents) and wires the two Area3D signals Godot gives us for free. Runs
## on EVERY peer (see class doc) -- detection itself is universal, only
## EMISSION is host-gated (in the two handlers below).
func _ready() -> void:
	if _collision_shape and _collision_shape.shape is SphereShape3D:
		(_collision_shape.shape as SphereShape3D).radius = tag_range_m
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## Godot's own overlap tracking is the source of truth for "who is in range
## right now" -- rather than hand-rolling a duplicate Dictionary that could
## drift out of sync with the physics server (e.g. a body freed mid-overlap
## without a matching exit signal), this reads get_overlapping_bodies() fresh
## every call, filtered to CharacterBody3D (excludes the Floor's
## CSGBox3D-generated StaticBody3D and any other non-Player body -- same "if
## child is CharacterBody3D" filter KickAbility.host_validate() already
## applies) and self-excluded (mirrors TagRules.exclude_self(), applied here
## structurally instead: Area3D physics never reports a body overlapping
## itself, but _body is this Player's OWN CharacterBody3D and must still be
## excluded defensively in case a future collision-shape change ever nests
## the shapes such that self-overlap became representable).
## Shape matches TagRules' candidate Dictionaries ({"id": int, "position":
## Vector3}) exactly, so a caller can feed this straight into
## TagRules.candidates_in_range()/nearest_candidate() (see class doc hand-off
## contract) without any reshaping.
func get_candidates_in_range() -> Array:
	var out: Array = []
	for body in get_overlapping_bodies():
		if body == _body or not (body is CharacterBody3D):
			continue
		if not body.name.is_valid_int():
			continue # non-Player CharacterBody3D (shouldn't exist today, defensive)
		out.append({"id": body.name.to_int(), "position": body.global_position})
	return out

## HOST-ONLY emission (see class doc's "HOST-AUTHORITATIVE CONTRACT"): a
## non-host peer's Area3D still fires this Godot-native signal locally (that
## is inherent to how Area3D physics works, cannot be suppressed without
## disabling detection entirely), so the is_server() gate below is what
## actually keeps tag_target_in_range meaning "the host says so" -- the same
## "gate emission, not the physics" shape as KickAbility.host_validate()
## gates DECISION, not input.
func _on_body_entered(body: Node3D) -> void:
	if body == _body or not (body is CharacterBody3D) or not body.name.is_valid_int():
		return
	if not multiplayer.is_server():
		return
	tag_target_in_range.emit(_body.name.to_int(), body.name.to_int())


## Mirror of _on_body_entered() above -- see its doc for the full rationale.
func _on_body_exited(body: Node3D) -> void:
	if body == _body or not (body is CharacterBody3D) or not body.name.is_valid_int():
		return
	if not multiplayer.is_server():
		return
	tag_target_left_range.emit(_body.name.to_int(), body.name.to_int())
