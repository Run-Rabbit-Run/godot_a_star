class_name FissureService
extends RefCounted

const LENGTH := 3


static func line(origin: Vector2i, center: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var direction := center - origin
	if HexGrid.DIRECTIONS.has(direction):
		for step in range(1, LENGTH + 1):
			cells.append(origin + direction * step)
	return cells


## Match every occupant before moving anyone. The line is short, so backtracking checks
## at most the neighboring cells of three occupants in a stable order.
static func plan(state: BattleState, cells: Array[Vector2i]) -> Dictionary:
	if cells.size() != LENGTH:
		return {}
	var options: Dictionary[StringName, Array] = {}
	for hex: Vector2i in cells:
		if not state.hex_grid.is_traversable(hex):
			return {}
		var unit := AbilityMovementService.occupant_at(state, hex)
		if unit == null:
			continue
		if not AbilityMovementService.may_displace(unit):
			return {}
		var choices: Array[Vector2i] = []
		for step: Vector2i in HexGrid.DIRECTIONS:
			var destination := hex + step
			if not cells.has(destination) and state.hex_grid.is_traversable(destination) and AbilityMovementService.occupant_at(state, destination) == null:
				choices.append(destination)
		choices.sort()
		options[unit.unit_id] = choices
	var destinations: Dictionary[StringName, Vector2i] = {}
	if not _assign(IdOrder.sorted(options.keys()), options, destinations, 0):
		return {}
	return {"destinations": destinations}


static func _assign(ids: Array[StringName], options: Dictionary[StringName, Array], destinations: Dictionary[StringName, Vector2i], index: int) -> bool:
	if index == ids.size():
		return true
	var id := ids[index]
	for hex: Vector2i in options[id]:
		if destinations.values().has(hex):
			continue
		destinations[id] = hex
		if _assign(ids, options, destinations, index + 1):
			return true
		destinations.erase(id)
	return false


static func create(state: BattleState, actor: UnitState, cells: Array[Vector2i], events: Array[BattleEvent]) -> String:
	if state.active_fissures.has(actor.unit_id):
		return "The unit already has an active fissure."
	var placement := plan(state, cells)
	if placement.is_empty():
		return "Cannot clear all fissure cells."
	var error := AbilityMovementService.relocate(state, placement.destinations, events)
	if not error.is_empty():
		return error
	var application := _change_traversal(state, cells, false)
	if not application.accepted:
		return application.rejection_reason
	state.active_fissures[actor.unit_id] = cells.duplicate()
	events.append_array(application.events)
	return ""


static func expire(state: BattleState, faction: BattleFaction.Value, events: Array[BattleEvent]) -> String:
	var by_owner := IdOrder.sorted(state.active_fissures.keys())
	for id: StringName in by_owner:
		if state.unit_states[id].faction != faction:
			continue
		var cells: Array[Vector2i] = state.active_fissures[id]
		state.active_fissures.erase(id)
		var application := _change_traversal(state, cells, true)
		if not application.accepted:
			return application.rejection_reason
		events.append_array(application.events)
	return ""


static func covers(state: BattleState, hex: Vector2i) -> bool:
	for cells: Array in state.active_fissures.values():
		if cells.has(hex):
			return true
	return false


static func _change_traversal(state: BattleState, cells: Array[Vector2i], traversable: bool) -> MapMutationApplicationResult:
	var mutations: Array[MapMutation] = []
	for hex: Vector2i in cells:
		mutations.append(MapMutation.set_traversal(hex, traversable, state.hex_grid.get_configured_movement_cost(hex)))
	return MapMutationService.apply(state, mutations)
