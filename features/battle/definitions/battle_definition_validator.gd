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
	if definition.protected_faction not in [BattleFaction.Value.PLAYER, BattleFaction.Value.ENEMY]:
		return BattleDefinitionValidationResult.failure("Unsupported protected faction.")

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
	if definition.primary_objective.target_faction not in [BattleFaction.Value.PLAYER, BattleFaction.Value.ENEMY]:
		return BattleDefinitionValidationResult.failure("Unsupported objective faction.")

	var objective_error := _validate_objective(definition)
	if not objective_error.is_empty():
		return BattleDefinitionValidationResult.failure(objective_error)

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


## Type, rounds, round limit and marked placements of the primary objective, or "".
static func _validate_objective(definition: BattleDefinition) -> String:
	var objective := definition.primary_objective
	if objective.type not in BattleObjectiveType.Value.values():
		return "Battle objective type is not supported."
	if objective.round_limit < 1 or objective.round_limit > BattleObjectiveDefinition.MAX_ROUND_LIMIT:
		return "Battle round limit must be between 1 and %d." % BattleObjectiveDefinition.MAX_ROUND_LIMIT
	if objective.type == BattleObjectiveType.Value.SURVIVE_ROUNDS and (objective.rounds < 1 or objective.rounds > objective.round_limit):
		return "Rounds to survive must be between 1 and the round limit."
	if objective.type == BattleObjectiveType.Value.ELIMINATE_TARGETS and objective.target_placement_ids.is_empty():
		return "The commander objective needs at least one commander."
	var factions: Dictionary[StringName, int] = {}
	for side: BattleSideDefinition in definition.sides:
		factions[side.side_id] = side.faction
	var placement_factions: Dictionary[StringName, int] = {}
	for placement: UnitPlacementDefinition in definition.unit_placements:
		placement_factions[placement.placement_id] = factions.get(placement.side_id, -1)
	if objective.type == BattleObjectiveType.Value.ELIMINATE_TARGETS:
		for placement_id: StringName in objective.target_placement_ids:
			if placement_factions.get(placement_id, -1) != objective.target_faction:
				return "Commander %s must be a placement of the target faction." % placement_id
	for placement_id: StringName in objective.protected_placement_ids:
		if placement_factions.get(placement_id, -1) != definition.protected_faction:
			return "Protected unit %s must be a placement of the protected faction." % placement_id
	return ""
