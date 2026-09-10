class_name BattleDefinitionValidator
extends RefCounted


static func validate(
	definition: BattleDefinition,
	hex_grid: HexGrid = null
) -> BattleDefinitionValidationResult:
	if definition == null:
		return BattleDefinitionValidationResult.failure(
			"BattleDefinition is not assigned."
		)

	if definition.id.is_empty():
		return BattleDefinitionValidationResult.failure(
			"BattleDefinition id must not be empty."
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

	if definition.unit_spawns.is_empty():
		return BattleDefinitionValidationResult.failure(
			"BattleDefinition must contain at least one unit spawn."
		)

	if hex_grid == null:
		return BattleDefinitionValidationResult.failure(
			"HexGrid is required to validate unit spawns."
		)

	var unit_ids: Dictionary[StringName, bool] = {}
	var spawn_hexes: Dictionary[Vector2i, bool] = {}
	var has_protected_faction := false
	var has_target_faction := false

	for spawn: BattleUnitSpawnDefinition in definition.unit_spawns:
		if spawn == null:
			return BattleDefinitionValidationResult.failure(
				"BattleDefinition contains a null unit spawn."
			)

		if not hex_grid.has_cell(spawn.hex):
			return BattleDefinitionValidationResult.failure(
				"Unit spawn hex does not exist: %s." % spawn.hex
			)

		if spawn.unit_id.is_empty():
			return BattleDefinitionValidationResult.failure(
				"Unit spawn id must not be empty."
			)

		if unit_ids.has(spawn.unit_id):
			return BattleDefinitionValidationResult.failure(
				"Duplicate unit spawn id: %s." % spawn.unit_id
			)

		unit_ids[spawn.unit_id] = true

		if spawn_hexes.has(spawn.hex):
			return BattleDefinitionValidationResult.failure(
				"Duplicate unit spawn hex: %s." % spawn.hex
			)

		spawn_hexes[spawn.hex] = true

		if spawn.unit_definition == null:
			return BattleDefinitionValidationResult.failure(
				"Unit spawn definition is not assigned: %s." % spawn.unit_id
			)

		if spawn.unit_definition.id.is_empty():
			return BattleDefinitionValidationResult.failure(
				"UnitDefinition id must not be empty: %s." % spawn.unit_id
			)

		if spawn.unit_definition.display_name.is_empty():
			return BattleDefinitionValidationResult.failure(
				"Unit display name must not be empty: %s." % spawn.unit_id
			)

		if spawn.unit_definition.actor_scene == null:
			return BattleDefinitionValidationResult.failure(
				"Unit actor scene is not assigned: %s." % spawn.unit_id
			)

		if spawn.unit_definition.base_stats == null:
			return BattleDefinitionValidationResult.failure(
				"Unit base stats are not assigned: %s." % spawn.unit_id
			)

		if spawn.faction == definition.protected_faction:
			has_protected_faction = true

		if spawn.faction == definition.primary_objective.target_faction:
			has_target_faction = true

	if not has_protected_faction:
		return BattleDefinitionValidationResult.failure(
			"BattleDefinition has no protected-faction unit spawn."
		)

	if not has_target_faction:
		return BattleDefinitionValidationResult.failure(
			"BattleDefinition has no target-faction unit spawn."
		)

	return BattleDefinitionValidationResult.success()