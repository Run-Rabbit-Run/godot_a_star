class_name InterceptionService
extends RefCounted


static func guards_at(state: BattleState, mover: UnitState, hex: Vector2i) -> Array[StringName]:
	var guards: Array[StringName] = []
	for unit: UnitState in state.unit_states.values():
		if unit.faction != mover.faction and not unit.health.is_defeated() and unit.statuses.has(UnitStatusCatalog.INTERCEPT_READY) and not unit.statuses.has(UnitStatusCatalog.PARALYSIS) and HexGrid.get_distance(unit.hex, hex) == 1:
			guards.append(unit.unit_id)
	return IdOrder.sorted(guards) if guards.size() > 1 else guards


static func react(state: BattleState, mover: UnitState, guards: Array[StringName], events: Array[BattleEvent]) -> String:
	for id: StringName in guards:
		if mover.health.is_defeated():
			break
		var guard := state.unit_states[id]
		if guard.health.is_defeated() or guard.statuses.has(UnitStatusCatalog.PARALYSIS) or HexGrid.get_distance(guard.hex, mover.hex) != 1:
			continue
		if UnitStatusService.consume(guard, UnitStatusCatalog.INTERCEPT_READY, events) > 0:
			var error := RetaliationService.strike(state, mover, guard, &"core:intercept", events)
			if not error.is_empty():
				return error
	return ""
