class_name SimulationRequest
extends RefCounted


var battle_start_request: BattleStartRequest
var fallback_ai_profile: AIProfileDefinition
var max_commands: int
var max_rounds: int
var cancellation_token: SimulationCancellationToken


func _init(
	p_battle_start_request: BattleStartRequest,
	p_fallback_ai_profile: AIProfileDefinition,
	p_max_commands: int = 1000,
	p_max_rounds: int = 100,
	p_cancellation_token: SimulationCancellationToken = null
) -> void:
	battle_start_request = p_battle_start_request
	fallback_ai_profile = p_fallback_ai_profile
	max_commands = p_max_commands
	max_rounds = p_max_rounds
	cancellation_token = p_cancellation_token if p_cancellation_token != null else SimulationCancellationToken.new()