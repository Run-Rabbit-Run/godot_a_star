class_name SimulationRunResult
extends RefCounted


var status: SimulationRunStatus.Value
var battle_result: BattleResult
var stop_reason: String
var command_count: int
var last_command_index: int
var round_number: int
var deterministic_seed: int


func _init(
	p_status: SimulationRunStatus.Value,
	p_battle_result: BattleResult,
	p_stop_reason: String,
	p_command_count: int,
	p_round_number: int,
	p_deterministic_seed: int
) -> void:
	status = p_status
	battle_result = p_battle_result
	stop_reason = p_stop_reason
	command_count = maxi(p_command_count, 0)
	last_command_index = command_count - 1
	round_number = maxi(p_round_number, 0)
	deterministic_seed = p_deterministic_seed


func is_completed() -> bool:
	return status == SimulationRunStatus.Value.COMPLETED


func to_report() -> Dictionary:
	var result_data: Dictionary = {}

	if battle_result != null:
		result_data = {
			"battle_id": String(battle_result.battle_id),
			"outcome": BattleOutcome.Value.keys()[battle_result.outcome],
			"round_number": battle_result.round_number,
			"objective": {
				"description": battle_result.objective_result.description,
				"is_completed": battle_result.objective_result.is_completed,
			},
		}

	return {
		"status": SimulationRunStatus.Value.keys()[status],
		"stop_reason": stop_reason,
		"command_count": command_count,
		"last_command_index": last_command_index,
		"round_number": round_number,
		"deterministic_seed": deterministic_seed,
		"battle_result": result_data,
	}