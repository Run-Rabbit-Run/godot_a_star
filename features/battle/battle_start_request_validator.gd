class_name BattleStartRequestValidator
extends RefCounted


static func validate(
	request: BattleStartRequest
) -> BattleStartRequestValidationResult:
	if request == null:
		return BattleStartRequestValidationResult.failure(
			"BattleStartRequest must not be null."
		)

	if request.battle_definition == null:
		return BattleStartRequestValidationResult.failure(
			"BattleStartRequest requires a BattleDefinition."
		)

	if request.battle_definition.map_definition == null:
		return BattleStartRequestValidationResult.failure(
			"BattleDefinition requires a BattleMapDefinition."
		)

	if request.deterministic_seed < 0:
		return BattleStartRequestValidationResult.failure(
			"BattleStartRequest seed must not be negative."
		)

	return BattleStartRequestValidationResult.success()