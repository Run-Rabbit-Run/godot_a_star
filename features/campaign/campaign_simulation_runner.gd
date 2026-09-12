class_name CampaignSimulationRunner
extends RefCounted


func run(
	snapshot: ContentSnapshot,
	campaign_id: StringName,
	fallback_ai_profile: AIProfileDefinition,
	seed: int = 1,
	max_commands_per_battle: int = 1000,
	max_rounds_per_battle: int = 100
) -> CampaignSimulationResult:
	var campaign := CampaignSession.create(snapshot, campaign_id)
	var results: Array[SimulationRunResult] = []
	var visited: Array[StringName] = []

	if campaign == null:
		return CampaignSimulationResult.new(
			false,
			"Campaign could not be created: %s." % campaign_id,
			results,
			visited
		)

	var scenario_limit := campaign.definition.scenario_ids.size() + 1

	while not campaign.is_completed:
		if visited.size() >= scenario_limit:
			return CampaignSimulationResult.new(
				false,
				"Campaign scenario transition limit was reached.",
				results,
				visited
			)

		var scenario := campaign.get_current_scenario()

		if scenario == null:
			return CampaignSimulationResult.new(
				false,
				"Current campaign scenario is missing.",
				results,
				visited
			)

		visited.append(scenario.id)
		var request := SimulationRequest.new(
			BattleStartRequest.new(scenario.battle_id, snapshot, seed),
			fallback_ai_profile,
			max_commands_per_battle,
			max_rounds_per_battle
		)
		var run_result := SimulationRunner.new().run(request)
		results.append(run_result)

		if not run_result.is_completed() or run_result.battle_result == null:
			return CampaignSimulationResult.new(
				false,
				"Scenario %s did not complete: %s."
				% [scenario.id, run_result.stop_reason],
				results,
				visited
			)

		var advance := campaign.complete_battle(run_result.battle_result)

		if not advance.accepted:
			return CampaignSimulationResult.new(
				false,
				advance.rejection_reason,
				results,
				visited
			)

		seed += 1

	return CampaignSimulationResult.new(true, "", results, visited)