class_name BattleAuthoringValidator
extends RefCounted


static func validate(
	definition: BattleDefinition,
	hex_grid: HexGrid,
	available_unit_definition_ids: Dictionary[StringName, bool] = {},
	available_ai_profile_definition_ids: Dictionary[StringName, bool] = {}
) -> BattleAuthoringValidationResult:
	var result := BattleAuthoringValidationResult.new()

	if definition == null:
		result.add_error("BattleDefinition is not assigned.")
		return result

	if hex_grid == null:
		result.add_error("HexGrid is required to validate battle authoring data.")
		return result

	var sides_by_id: Dictionary[StringName, BattleSideDefinition] = {}
	_validate_sides(
		definition,
		sides_by_id,
		available_ai_profile_definition_ids,
		result
	)
	_validate_placements(
		definition,
		hex_grid,
		sides_by_id,
		available_unit_definition_ids,
		available_ai_profile_definition_ids,
		result
	)

	return result


static func _validate_sides(
	definition: BattleDefinition,
	sides_by_id: Dictionary[StringName, BattleSideDefinition],
	available_ai_profile_definition_ids: Dictionary[StringName, bool],
	result: BattleAuthoringValidationResult
) -> void:
	if definition.sides.is_empty():
		result.add_error("BattleDefinition must contain at least one side.")
		return

	for side: BattleSideDefinition in definition.sides:
		if side == null:
			result.add_error("BattleDefinition contains a null side.")
			continue

		if side.side_id.is_empty():
			result.add_error("Battle side id must not be empty.")
			continue

		if sides_by_id.has(side.side_id):
			result.add_error("Duplicate battle side id: %s." % side.side_id)
			continue

		if (
			not side.ai_profile_id.is_empty()
			and not available_ai_profile_definition_ids.has(side.ai_profile_id)
		):
			result.add_error(
				"AIProfileDefinition does not exist for side %s: %s."
				% [side.side_id, side.ai_profile_id]
			)

		if (
			side.control_source != BattleControlSource.Value.PLAYER
			and side.control_source != BattleControlSource.Value.AI
		):
			result.add_error(
				"Battle side has an unsupported control source: %s."
				% side.side_id
			)

		if (
			side.control_source == BattleControlSource.Value.AI
			and side.ai_profile_id.is_empty()
		):
			result.add_error(
				"AI-controlled side requires an AI profile: %s."
				% side.side_id
			)

		if (
			side.control_source == BattleControlSource.Value.PLAYER
			and not side.ai_profile_id.is_empty()
		):
			result.add_warning(
				"Player-controlled side AI profile is currently unused: %s."
				% side.side_id
			)

		sides_by_id[side.side_id] = side


static func _validate_placements(
	definition: BattleDefinition,
	hex_grid: HexGrid,
	sides_by_id: Dictionary[StringName, BattleSideDefinition],
	available_unit_definition_ids: Dictionary[StringName, bool],
	available_ai_profile_definition_ids: Dictionary[StringName, bool],
	result: BattleAuthoringValidationResult
) -> void:
	if definition.unit_placements.is_empty():
		result.add_error("BattleDefinition must contain at least one unit placement.")
		return

	var placement_ids: Dictionary[StringName, bool] = {}
	var occupied_hexes: Dictionary[Vector2i, StringName] = {}
	var factions_with_placements: Dictionary[int, bool] = {}

	for placement: UnitPlacementDefinition in definition.unit_placements:
		if placement == null:
			result.add_error("BattleDefinition contains a null unit placement.")
			continue

		if placement.placement_id.is_empty():
			result.add_error("Unit placement id must not be empty.")
		elif placement_ids.has(placement.placement_id):
			result.add_error(
				"Duplicate unit placement id: %s." % placement.placement_id
			)
		else:
			placement_ids[placement.placement_id] = true

		if placement.definition_id.is_empty():
			result.add_error(
				"Unit placement definition id must not be empty: %s."
				% placement.placement_id
			)
		elif not available_unit_definition_ids.has(placement.definition_id):
			result.add_error(
				"UnitDefinition does not exist for placement %s: %s."
				% [placement.placement_id, placement.definition_id]
			)

		var side := sides_by_id.get(placement.side_id) as BattleSideDefinition

		if placement.side_id.is_empty():
			result.add_error(
				"Unit placement side id must not be empty: %s."
				% placement.placement_id
			)
		elif side == null:
			result.add_error(
				"Battle side does not exist for placement %s: %s."
				% [placement.placement_id, placement.side_id]
			)
		else:
			factions_with_placements[side.faction] = true

			if (
				not placement.ai_profile_override_id.is_empty()
				and side.control_source != BattleControlSource.Value.AI
			):
				result.add_error(
					"AI profile override requires an AI-controlled side: %s."
					% placement.placement_id
				)

		if (
			not placement.ai_profile_override_id.is_empty()
			and not available_ai_profile_definition_ids.has(
				placement.ai_profile_override_id
			)
		):
			result.add_error(
				"AIProfileDefinition does not exist for placement %s: %s."
				% [
					placement.placement_id,
					placement.ai_profile_override_id,
				]
			)

		if not hex_grid.has_cell(placement.start_hex):
			result.add_error(
				"Unit placement hex does not exist for %s: %s."
				% [placement.placement_id, placement.start_hex]
			)
		elif occupied_hexes.has(placement.start_hex):
			result.add_error(
				"Unit placements %s and %s occupy the same hex: %s."
				% [
					occupied_hexes[placement.start_hex],
					placement.placement_id,
					placement.start_hex,
				]
			)
		else:
			occupied_hexes[placement.start_hex] = placement.placement_id

	if not factions_with_placements.has(definition.protected_faction):
		result.add_error(
			"BattleDefinition has no placement for the protected faction."
		)

	if (
		definition.primary_objective != null
		and not factions_with_placements.has(
			definition.primary_objective.target_faction
		)
	):
		result.add_error(
			"BattleDefinition has no placement for the objective target faction."
		)
