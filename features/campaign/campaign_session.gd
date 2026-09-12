class_name CampaignSession
extends RefCounted


var snapshot: ContentSnapshot
var definition: CampaignDefinition
var current_scenario_id: StringName
var completed_scenario_ids: Array[StringName] = []
var carried_progress: Dictionary = {}
var is_completed := false


func _init(
	p_snapshot: ContentSnapshot,
	p_definition: CampaignDefinition
) -> void:
	snapshot = p_snapshot
	definition = p_definition
	current_scenario_id = definition.entry_scenario_id


static func create(
	p_snapshot: ContentSnapshot,
	campaign_id: StringName
) -> CampaignSession:
	if p_snapshot == null or not p_snapshot.is_valid:
		return null

	var campaign := p_snapshot.get_campaign_definition(campaign_id)

	if campaign == null:
		return null

	return CampaignSession.new(p_snapshot, campaign)


func get_current_scenario() -> ScenarioDefinition:
	if is_completed:
		return null

	return snapshot.get_scenario_definition(current_scenario_id)


func get_current_battle_id() -> StringName:
	var scenario := get_current_scenario()
	return scenario.battle_id if scenario != null else StringName()


func complete_battle(result: BattleResult) -> CampaignAdvanceResult:
	if is_completed or result == null:
		return CampaignAdvanceResult.new(
			false,
			"Campaign is completed or BattleResult is missing.",
			current_scenario_id,
			StringName(),
			is_completed
		)

	var scenario := get_current_scenario()

	if scenario == null or scenario.battle_id != result.battle_id:
		return CampaignAdvanceResult.new(
			false,
			"BattleResult does not belong to the current scenario.",
			current_scenario_id,
			StringName(),
			false
		)

	var transition_outcome := ScenarioTransitionDefinition.Outcome.DEFEAT

	if result.outcome == BattleOutcome.Value.VICTORY:
		transition_outcome = ScenarioTransitionDefinition.Outcome.VICTORY

	for transition: ScenarioTransitionDefinition in scenario.transitions:
		if transition.outcome != transition_outcome:
			continue

		var previous := current_scenario_id
		completed_scenario_ids.append(previous)

		if transition.ends_campaign:
			is_completed = true
			current_scenario_id = StringName()
			return CampaignAdvanceResult.new(
				true,
				"",
				previous,
				StringName(),
				true
			)

		current_scenario_id = transition.target_scenario_id
		return CampaignAdvanceResult.new(
			true,
			"",
			previous,
			current_scenario_id,
			false
		)

	return CampaignAdvanceResult.new(
		false,
		"Current scenario has no transition for this outcome.",
		current_scenario_id,
		StringName(),
		false
	)