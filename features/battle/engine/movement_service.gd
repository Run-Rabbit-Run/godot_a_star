class_name MovementService
extends RefCounted


static func get_reachable_cells(
	hex_grid: HexGrid,
	start: Vector2i,
	movement_points: int,
	blocked_cells: Dictionary[Vector2i, bool]
) -> Array[Vector2i]:
	return search(
		hex_grid,
		start,
		movement_points,
		blocked_cells
	).get_reachable_cells()


static func search(
	hex_grid: HexGrid,
	start: Vector2i,
	movement_points: int,
	blocked_cells: Dictionary[Vector2i, bool],
	map_revision: int = 0,
	state_revision: int = 0
) -> MovementSearchResult:
	var costs: Dictionary[Vector2i, int] = {}
	var came_from: Dictionary[Vector2i, Vector2i] = {}

	if movement_points < 0 or not hex_grid.has_cell(start):
		return MovementSearchResult.new(
			costs,
			came_from,
			map_revision,
			state_revision
		)

	var frontier: Array[Vector2i] = [start]
	costs[start] = 0

	while not frontier.is_empty():
		var lowest_cost_index := 0

		for index: int in range(1, frontier.size()):
			if costs[frontier[index]] < costs[frontier[lowest_cost_index]]:
				lowest_cost_index = index

		var current := frontier[lowest_cost_index]
		var current_cost := costs[current]
		frontier.remove_at(lowest_cost_index)

		if current_cost >= movement_points:
			continue

		for neighbor: Vector2i in hex_grid.get_neighbors(current):
			if blocked_cells.has(neighbor):
				continue

			var movement_cost := hex_grid.get_movement_cost(neighbor)

			if movement_cost < 1:
				continue

			var new_cost := current_cost + movement_cost

			if new_cost > movement_points:
				continue

			if costs.has(neighbor) and new_cost >= costs[neighbor]:
				continue

			costs[neighbor] = new_cost
			came_from[neighbor] = current
			frontier.append(neighbor)

	return MovementSearchResult.new(
		costs,
		came_from,
		map_revision,
		state_revision
	)