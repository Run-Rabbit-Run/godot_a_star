class_name MovementImpactForecast
extends RefCounted

## Pure forecast on detached state using the same terrain and status rules as execution.
static func evaluate(unit: UnitSnapshot, grid: HexGrid, path: Array[Vector2i]) -> Dictionary:
	var simulated := UnitState.new(unit.unit_id, unit.definition_id, unit.faction, unit.hex, TurnState.new(unit.turn.movement_max), HealthState.new(unit.health.maximum), unit.basic_attack_damage, unit.basic_attack_range)
	simulated.health.current = unit.health.current
	simulated.turn.movement_remaining = unit.turn.movement_remaining
	simulated.statuses.assign(unit.statuses)
	simulated.status_immunities.assign(unit.status_immunities)
	var events: Array[BattleEvent] = []
	var reached := true
	for index in range(1, path.size()):
		var hex := path[index]
		var cost := grid.get_movement_cost(hex)
		if cost < 1 or not simulated.turn.spend_movement(cost):
			reached = false
			break
		simulated.hex = hex
		HexStateService.expose(simulated, grid, events)
		if simulated.health.is_defeated() or simulated.statuses.get(&"core:paralysis", 0) > 0:
			reached = index == path.size() - 1
			break
	UnitStatusService.end_turn(simulated, events)
	HexStateService.expose(simulated, grid, events)
	return {"reached": reached, "damage": unit.health.current - simulated.health.current, "lethal": simulated.health.is_defeated()}
