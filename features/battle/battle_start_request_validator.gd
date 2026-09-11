class_name BattleStartRequestValidator
extends RefCounted


static func validate(
	request: BattleStartRequest
) -> BattleStartRequestValidationResult:
	if request == null:
		return BattleStartRequestValidationResult.failure(
			"BattleStartRequest must not be null."
		)

	if request.battle_id.is_empty():
		return BattleStartRequestValidationResult.failure(
			"BattleStartRequest battle_id must not be empty."
		)

	if request.content_snapshot == null:
		return BattleStartRequestValidationResult.failure(
			"BattleStartRequest requires a ContentSnapshot."
		)

	if not request.content_snapshot.is_valid:
		return BattleStartRequestValidationResult.failure(
			request.content_snapshot.error_message
		)

	if request.deterministic_seed < 0:
		return BattleStartRequestValidationResult.failure(
			"BattleStartRequest seed must not be negative."
		)

	return BattleStartRequestValidationResult.success()
