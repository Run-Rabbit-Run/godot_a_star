class_name CampaignSimulationResult
extends RefCounted


var completed: bool
var error_message: String
var battle_results: Array[SimulationRunResult] = []
var visited_scenario_ids: Array[StringName] = []


func _init(
	p_completed: bool,
	p_error_message: String,
	p_battle_results: Array[SimulationRunResult],
	p_visited_scenario_ids: Array[StringName]
) -> void:
	completed = p_completed
	error_message = p_error_message
	battle_results.assign(p_battle_results)
	visited_scenario_ids.assign(p_visited_scenario_ids)