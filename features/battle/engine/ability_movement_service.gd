class_name AbilityMovementService
extends RefCounted


## Relocate all participants first so exchange and line evacuation never create two occupants.
static func relocate(state: BattleState, destinations: Dictionary[StringName, Vector2i], events: Array[BattleEvent]) -> String:
	var ids := IdOrder.sorted(destinations.keys())
	for id: StringName in ids:
		var unit := state.unit_states[id]
		var path: Array[Vector2i] = [unit.hex, destinations[id]]
		unit.hex = destinations[id]
		events.append(UnitMovedEvent.new(id, path, 0))
	for id: StringName in ids:
		var error := enter(state, state.unit_states[id], events)
		if not error.is_empty():
			return error
	return ""


## The caller emits movement first. Terrain acts before the readied strike, as with a move.
static func enter(state: BattleState, unit: UnitState, events: Array[BattleEvent]) -> String:
	var guards := InterceptionService.guards_at(state, unit, unit.hex)
	HexStateService.expose(unit, state.hex_grid, events)
	return InterceptionService.react(state, unit, guards, events)


static func occupant_at(state: BattleState, hex: Vector2i) -> UnitState:
	for unit: UnitState in state.unit_states.values():
		if unit.hex == hex and not unit.health.is_defeated():
			return unit
	return null


static func may_displace(unit: UnitState) -> bool:
	return not unit.health.is_defeated() and not unit.holds_hex and not unit.push_immune
