class_name ObstacleService
extends RefCounted
## Damage to obstacles. A destroyed flask bursts at once (ObstacleBreakService), before the
## action that broke it continues.


## Returns "" or why the burst of a destroyed flask could not change the map; the caller
## decides whether that rejects its transaction or stops the battle.
static func damage(state: BattleState, hex: Vector2i, amount: int, events: Array[BattleEvent]) -> String:
	var obstacle := state.hex_grid.get_obstacle(hex)
	if obstacle == null:
		return ""
	var damage := state.hex_grid.damage_obstacle(hex, amount)
	if damage == 0:
		return ""
	state.map_revision += 1
	state.state_revision += 1
	for cell: Vector2i in obstacle.hexes:
		var event := MapMutationEvent.new(MapMutationKind.Value.SET_TRAVERSAL, cell, state.hex_grid.get_terrain_id(cell), state.hex_grid.is_traversable(cell), state.hex_grid.get_configured_movement_cost(cell))
		event.obstacle_changed = true
		event.obstacle = state.hex_grid.get_obstacle(cell)
		event.obstacle_damage = damage
		events.append(event)
	if state.hex_grid.has_obstacle(hex) or not obstacle.is_flask():
		return ""
	obstacle.current_hp = 0
	return ObstacleBreakService.burst(state, obstacle, events)
