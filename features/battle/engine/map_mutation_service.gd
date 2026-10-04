class_name MapMutationService
extends RefCounted


static func apply(
	state: BattleState,
	mutations: Array[MapMutation]
) -> MapMutationApplicationResult:
	if state == null or state.hex_grid == null:
		return MapMutationApplicationResult.rejected(
			"BattleState requires a HexGrid."
		)

	if mutations.is_empty():
		return MapMutationApplicationResult.rejected(
			"Map mutation batch must not be empty."
		)

	var candidate := state.hex_grid.duplicate_grid()
	var events: Array[BattleEvent] = []
	var explosions: Array[Dictionary] = []

	for mutation: MapMutation in mutations:
		if mutation == null:
			return MapMutationApplicationResult.rejected(
				"Map mutation must not be null."
			)

		var error := _validate_mutation(state, candidate, mutation)

		if not error.is_empty():
			return MapMutationApplicationResult.rejected(error)

		if mutation.kind == MapMutationKind.Value.APPLY_HEX_STATE:
			HexStateService.apply_to_grid(candidate, mutation.hex, mutation.hex_state_id, events, explosions)
			continue

		var event := _apply_to_candidate(candidate, mutation)

		if event == null:
			return MapMutationApplicationResult.rejected(
				"Map mutation could not be applied."
			)

		events.append(event)

	if not state.hex_grid.replace_with(candidate):
		return MapMutationApplicationResult.rejected(
			"Validated map candidate could not be committed."
		)

	state.map_revision += 1
	state.state_revision += 1
	for explosion: Dictionary in explosions:
		for unit: UnitState in state.unit_states.values():
			if unit.hex == explosion.hex:
				UnitStatusService.damage(unit, 3, &"physical", events, &"", explosion.state_id)
	var changed: Dictionary[Vector2i, bool] = {}
	for event: BattleEvent in events.duplicate():
		if event is MapMutationEvent and event.kind == MapMutationKind.Value.APPLY_HEX_STATE:
			changed[event.hex] = true
	for unit: UnitState in state.unit_states.values():
		if changed.has(unit.hex):
			HexStateService.expose(unit, state.hex_grid, events)
	return MapMutationApplicationResult.success(events)


static func _validate_mutation(
	state: BattleState,
	candidate: HexGrid,
	mutation: MapMutation
) -> String:
	match mutation.kind:
		MapMutationKind.Value.APPLY_HEX_STATE:
			if not candidate.has_cell(mutation.hex):
				return "Hex state target does not exist: %s." % mutation.hex
			if not mutation.hex_state_id.is_empty() and not HexStateCatalog.has_state(mutation.hex_state_id):
				return "Unknown hex state: %s." % mutation.hex_state_id
		MapMutationKind.Value.ADD_HEX:
			if candidate.has_cell(mutation.hex):
				return "AddHex target already exists: %s." % mutation.hex
			if mutation.terrain_id.is_empty():
				return "AddHex terrain id must not be empty."
			if mutation.movement_cost < 1:
				return "AddHex movement cost must be at least 1."

		MapMutationKind.Value.REMOVE_HEX:
			if not candidate.has_cell(mutation.hex):
				return "RemoveHex target does not exist: %s." % mutation.hex
			if _is_occupied(state, mutation.hex):
				return "RemoveHex target is occupied: %s." % mutation.hex

		MapMutationKind.Value.CHANGE_TERRAIN:
			if not candidate.has_cell(mutation.hex):
				return "ChangeTerrain target does not exist: %s." % mutation.hex
			if mutation.terrain_id.is_empty():
				return "ChangeTerrain terrain id must not be empty."

		MapMutationKind.Value.SET_TRAVERSAL:
			if not candidate.has_cell(mutation.hex):
				return "SetTraversal target does not exist: %s." % mutation.hex
			if mutation.movement_cost < 1:
				return "SetTraversal movement cost must be at least 1."
			var state_id := candidate.get_hex_state_id(mutation.hex)
			if not state_id.is_empty() and mutation.movement_cost != HexStateCatalog.get_movement_cost(state_id):
				return "SetTraversal cost conflicts with hex state at %s." % mutation.hex
			if not mutation.traversable and _is_occupied(state, mutation.hex):
				return "An occupied hex cannot become non-traversable: %s." % mutation.hex

		_:
			return "Unsupported map mutation kind."

	return ""


static func _apply_to_candidate(
	candidate: HexGrid,
	mutation: MapMutation
) -> MapMutationEvent:
	match mutation.kind:
		MapMutationKind.Value.ADD_HEX:
			if not candidate.add_cell(
				mutation.hex,
				mutation.terrain_id,
				mutation.movement_cost,
				mutation.traversable
			):
				return null

		MapMutationKind.Value.REMOVE_HEX:
			var removed_terrain_id := candidate.get_terrain_id(mutation.hex)
			var removed_traversable := candidate.is_traversable(mutation.hex)
			var removed_cost := candidate.get_configured_movement_cost(
				mutation.hex
			)

			if not candidate.remove_cell(mutation.hex):
				return null

			return MapMutationEvent.new(
				mutation.kind,
				mutation.hex,
				removed_terrain_id,
				removed_traversable,
				removed_cost
			)

		MapMutationKind.Value.CHANGE_TERRAIN:
			if not candidate.change_terrain(
				mutation.hex,
				mutation.terrain_id
			):
				return null

		MapMutationKind.Value.SET_TRAVERSAL:
			if not candidate.set_traversal(
				mutation.hex,
				mutation.traversable,
				mutation.movement_cost
			):
				return null

		_:
			return null

	return MapMutationEvent.new(
		mutation.kind,
		mutation.hex,
		candidate.get_terrain_id(mutation.hex),
		candidate.is_traversable(mutation.hex),
		candidate.get_configured_movement_cost(mutation.hex)
	)


static func _is_occupied(state: BattleState, hex: Vector2i) -> bool:
	for unit: UnitState in state.unit_states.values():
		if not unit.health.is_defeated() and unit.hex == hex:
			return true

	return false
