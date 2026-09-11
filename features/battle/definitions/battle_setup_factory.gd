class_name BattleSetupFactory
extends RefCounted


static func create(request: BattleStartRequest) -> BattleSetupCreationResult:
	var request_validation := BattleStartRequestValidator.validate(request)

	if not request_validation.is_valid:
		return BattleSetupCreationResult.failure(
			request_validation.error_message
		)

	var snapshot := request.content_snapshot
	var definition := snapshot.get_battle_definition(request.battle_id)

	if definition == null:
		return BattleSetupCreationResult.failure(
			"BattleDefinition could not be resolved: %s." % request.battle_id
		)

	var map_definition := snapshot.get_map_definition(definition.map_id)

	if map_definition == null:
		return BattleSetupCreationResult.failure(
			"BattleMapDefinition could not be resolved: %s."
			% definition.map_id
		)

	var hex_grid := BattleMapFactory.create_hex_grid(map_definition)

	if hex_grid == null:
		return BattleSetupCreationResult.failure(
			"Battle map could not be created from its definition."
		)

	var definition_validation := BattleDefinitionValidator.validate(
		definition,
		hex_grid,
		snapshot.get_unit_definition_ids(),
		snapshot.get_ai_profile_definition_ids()
	)

	if not definition_validation.is_valid:
		return BattleSetupCreationResult.failure(
			definition_validation.error_message
		)

	var sides_by_id: Dictionary[StringName, BattleSideDefinition] = {}
	var resolved_sides: Array[BattleSideData] = []

	for side: BattleSideDefinition in definition.sides:
		sides_by_id[side.side_id] = side
		var ai_profile := snapshot.get_ai_profile_definition(
			side.ai_profile_id
		)

		if ai_profile != null and ai_profile.policy_id.is_empty():
			return BattleSetupCreationResult.failure(
				"AIProfileDefinition policy_id must not be empty: %s."
				% ai_profile.id
			)

		resolved_sides.append(
			BattleSideData.new(
				side.side_id,
				side.faction,
				side.control_source,
				ai_profile
			)
		)

	var unit_spawns: Array[UnitSpawnData] = []

	for placement: UnitPlacementDefinition in definition.unit_placements:
		var unit_definition := snapshot.get_unit_definition(
			placement.definition_id
		)

		if unit_definition == null:
			return BattleSetupCreationResult.failure(
				"UnitDefinition could not be resolved: %s."
				% placement.definition_id
			)

		var unit_validation_error := _validate_unit_definition(
			unit_definition
		)

		if not unit_validation_error.is_empty():
			return BattleSetupCreationResult.failure(
				unit_validation_error
			)

		var side := sides_by_id[placement.side_id]
		var ai_profile_id := side.ai_profile_id

		if not placement.ai_profile_override_id.is_empty():
			ai_profile_id = placement.ai_profile_override_id

		var ai_profile := snapshot.get_ai_profile_definition(ai_profile_id)

		if side.control_source == BattleControlSource.Value.AI and ai_profile == null:
			return BattleSetupCreationResult.failure(
				"AIProfileDefinition could not be resolved: %s." % ai_profile_id
			)

		var unit_id := StringName(
			"%s:%s" % [definition.id, placement.placement_id]
		)
		unit_spawns.append(
			UnitSpawnData.new(
				unit_id,
				placement.placement_id,
				placement.definition_id,
				unit_definition,
				placement.side_id,
				side.faction,
				side.control_source,
				ai_profile_id,
				ai_profile,
				placement.start_hex,
				placement.modifiers
			)
		)

	return BattleSetupCreationResult.success(
		BattleSetup.new(
			definition.id,
			hex_grid,
			resolved_sides,
			unit_spawns,
			definition.primary_objective,
			definition.protected_faction,
			request.deterministic_seed
		)
	)


static func _validate_unit_definition(definition: UnitDefinition) -> String:
	if definition.id.is_empty():
		return "UnitDefinition id must not be empty."

	if definition.display_name.is_empty():
		return "UnitDefinition display name must not be empty: %s." % definition.id

	if definition.base_stats == null:
		return "UnitDefinition base stats are not assigned: %s." % definition.id

	return ""
