class_name MovementService
extends RefCounted


## Совместимый фасад для кода, которому не нужны стоимость и маршрут.
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


## Дейкстра учитывает стоимость входа в гекс и сохраняет предков маршрута.
static func search(
	hex_grid: HexGrid,
	start: Vector2i,
	movement_points: int,
	blocked_cells: Dictionary[Vector2i, bool]
) -> MovementSearchResult:
	var costs: Dictionary[Vector2i, int] = {}
	var came_from: Dictionary[Vector2i, Vector2i] = {}

	if movement_points < 0 or not hex_grid.has_cell(start):
		return MovementSearchResult.new(costs, came_from)

	var frontier: Array[Vector2i] = [start]
	costs[start] = 0

	while not frontier.is_empty():
		## Для небольшого поля линейный поиск минимума проще отдельной priority queue.
		var lowest_cost_index := 0

		for index in range(1, frontier.size()):
			if costs[frontier[index]] < costs[frontier[lowest_cost_index]]:
				lowest_cost_index = index

		var current := frontier[lowest_cost_index]
		var current_cost := costs[current]
		frontier.remove_at(lowest_cost_index)

		if current_cost >= movement_points:
			continue

		for neighbor in hex_grid.get_neighbors(current):
			if blocked_cells.has(neighbor):
				continue

			var new_cost := current_cost + hex_grid.get_movement_cost(neighbor)

			if new_cost > movement_points:
				continue

			if costs.has(neighbor) and new_cost >= costs[neighbor]:
				continue

			costs[neighbor] = new_cost
			came_from[neighbor] = current
			frontier.append(neighbor)

	return MovementSearchResult.new(costs, came_from)