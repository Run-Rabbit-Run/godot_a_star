class_name ObstacleService
extends RefCounted

static func damage(state: BattleState, hex: Vector2i, amount: int, events: Array[BattleEvent]) -> int:
	var obstacle := state.hex_grid.get_obstacle(hex)
	if obstacle == null:
		return 0
	var damage := state.hex_grid.damage_obstacle(hex, amount)
	if damage == 0:
		return 0
	state.map_revision += 1
	state.state_revision += 1
	for cell: Vector2i in obstacle.hexes:
		var event := MapMutationEvent.new(MapMutationKind.Value.SET_TRAVERSAL, cell, state.hex_grid.get_terrain_id(cell), state.hex_grid.is_traversable(cell), state.hex_grid.get_configured_movement_cost(cell))
		event.obstacle_changed = true
		event.obstacle = state.hex_grid.get_obstacle(cell)
		event.obstacle_damage = damage
		events.append(event)
	return damage
