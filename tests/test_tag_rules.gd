extends GutTest
## Unit tests for characters/components/TagRules.gd (TK-P2-02) and the
## exported default on characters/components/TagDetectorComponent.gd.
##
## Only node-independent logic is covered here (design doc §3 testability
## note, same rationale tests/test_kick_rules.gd documents for KickRules):
## TagRules is a pure static helper (same pattern as managers/TigerSelector.gd
## / networking/SpawnPointUtil.gd / characters/abilities/KickRules.gd).
## TagDetectorComponent itself is an Area3D and needs a live scene
## tree/physics server + a second networked peer to prove real overlap
## detection and the host-only emit gate -- that residual glue gap is called
## out explicitly in this card's HANDOFF note (manual 2-instance check), same
## shape as TK-P2-19 for Kick's own RPC wire-routing gap. A bare
## TagDetectorComponent.new() (never added to a tree, so its @onready `_body`/
## `_collision_shape` stay unresolved) is still safe to touch for its plain
## @export default, same pattern test_kick_rules.gd uses for KickAbility's
## bare-instance export checks.

const TagRulesScript := preload("res://characters/components/TagRules.gd")
const TagDetectorComponentScript := preload("res://characters/components/TagDetectorComponent.gd")


# --- TagRules.is_in_range (pure) --------------------------------------------

func test_is_in_range_true_at_exactly_the_boundary() -> void:
	# Inclusive boundary (<=), per TagRules.gd's own doc comment.
	assert_true(TagRulesScript.is_in_range(Vector3.ZERO, Vector3(2.0, 0, 0), 2.0))


func test_is_in_range_true_when_closer_than_range() -> void:
	assert_true(TagRulesScript.is_in_range(Vector3.ZERO, Vector3(1.0, 0, 0), 2.0))


func test_is_in_range_false_when_farther_than_range() -> void:
	assert_false(TagRulesScript.is_in_range(Vector3.ZERO, Vector3(2.01, 0, 0), 2.0))


# --- TagRules.exclude_self (pure) -------------------------------------------

func test_exclude_self_removes_only_the_matching_id() -> void:
	var all_players: Array = [
		{"id": 1, "position": Vector3.ZERO},
		{"id": 2, "position": Vector3(1, 0, 0)},
		{"id": 3, "position": Vector3(2, 0, 0)},
	]
	var result: Array = TagRulesScript.exclude_self(2, all_players)
	assert_eq(result.size(), 2, "exactly one entry (id 2) should be removed")
	for entry in result:
		assert_ne(entry.get("id"), 2, "self id must never appear in the result")


func test_exclude_self_is_a_no_op_when_self_id_is_not_present() -> void:
	var all_players: Array = [
		{"id": 1, "position": Vector3.ZERO},
		{"id": 2, "position": Vector3(1, 0, 0)},
	]
	var result: Array = TagRulesScript.exclude_self(99, all_players)
	assert_eq(result.size(), 2, "no matching id -- nothing should be removed")


func test_exclude_self_on_empty_list_returns_empty() -> void:
	var result: Array = TagRulesScript.exclude_self(1, [])
	assert_true(result.is_empty())


# --- TagRules.candidates_in_range (pure, ALL qualifying candidates) --------

func test_candidates_in_range_returns_empty_for_no_candidates() -> void:
	var result: Array = TagRulesScript.candidates_in_range(Vector3.ZERO, [], 2.0)
	assert_true(result.is_empty())


func test_candidates_in_range_excludes_out_of_range_candidates() -> void:
	var candidates: Array = [
		{"id": 2, "position": Vector3(5.0, 0, 0)}, # way out of range
	]
	var result: Array = TagRulesScript.candidates_in_range(Vector3.ZERO, candidates, 2.0)
	assert_true(result.is_empty(), "an out-of-range-only candidate list must return an empty Array, never null/crash")


func test_candidates_in_range_returns_every_qualifying_candidate_not_just_one() -> void:
	var candidates: Array = [
		{"id": 2, "position": Vector3(1.0, 0, 0)},  # in range
		{"id": 3, "position": Vector3(1.9, 0, 0)},  # in range
		{"id": 4, "position": Vector3(5.0, 0, 0)},  # out of range
	]
	var result: Array = TagRulesScript.candidates_in_range(Vector3.ZERO, candidates, 2.0)
	assert_eq(result.size(), 2, "a Tag detector must report EVERY nearby player, not just the nearest")
	var ids: Array = []
	for entry in result:
		ids.append(entry.get("id"))
	assert_true(ids.has(2))
	assert_true(ids.has(3))
	assert_false(ids.has(4))


func test_candidates_in_range_boundary_is_inclusive() -> void:
	var candidates: Array = [
		{"id": 2, "position": Vector3(2.0, 0, 0)}, # exactly at range_m
	]
	var result: Array = TagRulesScript.candidates_in_range(Vector3.ZERO, candidates, 2.0)
	assert_eq(result.size(), 1, "a candidate exactly at range_m must still count (inclusive boundary)")


# --- TagRules.nearest_candidate (pure, pick exactly ONE) --------------------

func test_nearest_candidate_picks_the_closest_candidate_in_range() -> void:
	var candidates: Array = [
		{"id": "2", "position": Vector3(1.9, 0, 0)},
		{"id": "3", "position": Vector3(0.5, 0, 0)},
	]
	var result: Dictionary = TagRulesScript.nearest_candidate(Vector3.ZERO, candidates, 2.0)
	assert_eq(result.get("id"), "3", "the CLOSER in-range candidate should win, not the first in the array")


func test_nearest_candidate_returns_empty_dictionary_for_no_candidates() -> void:
	var result: Dictionary = TagRulesScript.nearest_candidate(Vector3.ZERO, [], 2.0)
	assert_true(result.is_empty())


func test_nearest_candidate_ignores_out_of_range_candidates() -> void:
	var candidates: Array = [
		{"id": "2", "position": Vector3(9.0, 0, 0)},
	]
	var result: Dictionary = TagRulesScript.nearest_candidate(Vector3.ZERO, candidates, 2.0)
	assert_true(result.is_empty())


func test_nearest_candidate_tie_resolves_to_first_in_array() -> void:
	var candidates: Array = [
		{"id": "2", "position": Vector3(1.0, 0, 0)},
		{"id": "3", "position": Vector3(0.0, 1.0, 0)}, # exact same distance (1.0) from origin
	]
	var result: Dictionary = TagRulesScript.nearest_candidate(Vector3.ZERO, candidates, 2.0)
	assert_eq(result.get("id"), "2", "an exact distance tie should resolve to whichever candidate appears first")


# --- End-to-end pure pipeline: exclude_self -> candidates_in_range ----------

func test_full_pipeline_self_excluded_then_filtered_by_range() -> void:
	var all_players: Array = [
		{"id": 1, "position": Vector3.ZERO},        # self (tagger) -- must never appear
		{"id": 2, "position": Vector3(1.0, 0, 0)},  # in range
		{"id": 3, "position": Vector3(9.0, 0, 0)},  # out of range
	]
	var candidates: Array = TagRulesScript.exclude_self(1, all_players)
	var result: Array = TagRulesScript.candidates_in_range(Vector3.ZERO, candidates, 2.0)
	assert_eq(result.size(), 1)
	assert_eq(result[0].get("id"), 2)


# --- TagDetectorComponent exported default (bare instance, no scene tree) --

var _detector: Area3D


func after_each() -> void:
	if is_instance_valid(_detector):
		_detector.free()
		_detector = null


func test_tag_detector_component_default_range() -> void:
	_detector = TagDetectorComponentScript.new()
	assert_eq(_detector.tag_range_m, 2.0, "documented placeholder default (see class doc -- no locked Game_Balance.md value yet)")


func test_tag_detector_component_is_an_area3d() -> void:
	_detector = TagDetectorComponentScript.new()
	assert_true(_detector is Area3D, "the card asks for an Area3D-based detector")
