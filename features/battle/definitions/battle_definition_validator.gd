class_name BattleDefinitionValidator
extends RefCounted


static func validate(
	definition: BattleDefinition,
	hex_grid: HexGrid = null,
	available_unit_definition_ids: Dictionary[StringName, bool] = {},
	available_ai_profile_definition_ids: Dictionary[StringName, bool] = {}
) -> BattleDefinitionValidationResult:
	if definition == null:
		return BattleDefinitionValidationResult.failure(
			"BattleDefinition is not assigned."
		)

	if definition.id.is_empty():
		return BattleDefinitionValidationResult.failure(
			"BattleDefinition id must not be empty."
		)

	if definition.map_id.is_empty():
		return BattleDefinitionValidationResult.failure(
			"BattleDefinition map_id must not be empty."
		)

	if definition.primary_objective == null:
		return BattleDefinitionValidationResult.failure(
			"BattleDefinition primary objective is not assigned."
		)

	if definition.primary_objective.description.is_empty():
		return BattleDefinitionValidationResult.failure(
			"Battle objective description must not be empty."
		)

	if definition.primary_objective.type != BattleObjectiveType.Value.ELIMINATE_FACTION:
		return BattleDefinitionValidationResult.failure(
			"Battle objective type is not supported."
		)

	if (
		definition.protected_faction
		== definition.primary_objective.target_faction
	):
		return BattleDefinitionValidationResult.failure(
			"Protected and target factions must be different."
		)

	if hex_grid == null:
		return BattleDefinitionValidationResult.failure(
			"HexGrid is required to validate battle authoring data."
		)

	var authoring_validation := BattleAuthoringValidator.validate(
		definition,
		hex_grid,
		available_unit_definition_ids,
		available_ai_profile_definition_ids
	)

	if not authoring_validation.is_valid:
		return BattleDefinitionValidationResult.failure(
			authoring_validation.get_first_error()
		)

	return BattleDefinitionValidationResult.success()
