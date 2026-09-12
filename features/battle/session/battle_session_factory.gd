class_name BattleSessionFactory
extends RefCounted


static func create(request: BattleStartRequest) -> BattleSessionCreationResult:
	var setup_result := BattleSetupFactory.create(request)

	if not setup_result.is_successful:
		return BattleSessionCreationResult.failure(
			setup_result.error_message
		)

	var setup := setup_result.setup

	for side: BattleSideData in setup.sides:
		if (
			side.control_source == BattleControlSource.Value.AI
			and not AICommandSource.supports(side.ai_profile_definition)
		):
			return BattleSessionCreationResult.failure(
				"Unsupported AI profile for side %s." % side.side_id
			)

	for spawn: UnitSpawnData in setup.unit_spawns:
		if (
			spawn.control_source == BattleControlSource.Value.AI
			and not AICommandSource.supports(spawn.ai_profile_definition)
		):
			return BattleSessionCreationResult.failure(
				"Unsupported AI profile for unit %s." % spawn.unit_id
			)

	var unit_states: Dictionary[StringName, UnitState] = {}
	var occupied_hexes: Dictionary[Vector2i, bool] = {}
	var turn_order: Array[StringName] = []

	for spawn: UnitSpawnData in setup.unit_spawns:
		var state := UnitStateFactory.create(spawn)

		if state == null:
			return BattleSessionCreationResult.failure(
				"UnitState could not be created: %s." % spawn.unit_id
			)

		if unit_states.has(state.unit_id):
			return BattleSessionCreationResult.failure(
				"Duplicate runtime unit id: %s." % state.unit_id
			)

		if occupied_hexes.has(state.hex):
			return BattleSessionCreationResult.failure(
				"Runtime unit hex is occupied: %s." % state.hex
			)

		unit_states[state.unit_id] = state
		occupied_hexes[state.hex] = true
		turn_order.append(state.unit_id)

	var primary_objective := BattleObjectiveFactory.create(
		setup.primary_objective_definition
	)

	if primary_objective == null:
		return BattleSessionCreationResult.failure(
			"BattleObjective could not be created."
		)

	var objective_system := ObjectiveSystem.new(
		primary_objective,
		setup.protected_faction
	)
	var state := BattleState.new(
		setup.battle_id,
		setup.hex_grid,
		unit_states,
		turn_order,
		objective_system,
		setup.deterministic_seed,
		request.content_snapshot.mod_api
	)
	var engine := BattleEngine.new(state)
	var session := BattleSession.new(setup, state, engine)

	return BattleSessionCreationResult.success(session)
