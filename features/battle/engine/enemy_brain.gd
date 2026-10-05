class_name EnemyBrain
extends RefCounted


## How many movement points of detour the AI accepts to avoid losing all current health.
## Damage is weighed as a share of current health: two points at 100 health barely change
## the choice, while at five health they push the unit onto a safer route.
const FULL_HEALTH_DETOUR_COST := 10


static func choose_target(
	origin: Vector2i,
	candidates: Array[UnitSnapshot]
) -> UnitSnapshot:
	var best_target: UnitSnapshot
	var best_distance := 0

	for candidate: UnitSnapshot in candidates:
		if candidate == null or candidate.health.is_defeated():
			continue

		var distance := HexGrid.get_distance(origin, candidate.hex)

		if (
			best_target != null
			and distance > best_distance
		):
			continue

		if (
			best_target != null
			and distance == best_distance
			and String(candidate.unit_id) >= String(best_target.unit_id)
		):
			continue

		best_target = candidate
		best_distance = distance

	return best_target


## Returns null when no reachable cell scores better than staying on the start cell.
static func choose_move(
	unit_id: StringName,
	start: Vector2i,
	target: Vector2i,
	movement_search: MovementSearchResult,
	grid: HexGrid = null,
	current_health: int = 0,
	attack_range: int = 1,
	forecast_unit: UnitSnapshot = null
) -> MoveCommand:
	if unit_id.is_empty() or movement_search == null:
		return null

	var health := maxi(current_health, 1)
	var approach_costs := _get_approach_costs(grid, target, attack_range)
	# Without a path to an attack position the unit still closes the straight distance.
	var uses_paths := approach_costs.has(start)
	var start_approach := HexGrid.get_distance(start, target)

	if uses_paths:
		start_approach = approach_costs[start]

	var stay_score := _get_position_score(
		start_approach,
		int(MovementImpactForecast.evaluate(forecast_unit, grid, [start]).damage) if forecast_unit != null and grid != null else _get_standing_damage(grid, start),
		health
	)
	var has_best_cell := false
	var best_cell := Vector2i.ZERO
	var best_score := 0
	var best_cost := 0

	for cell: Vector2i in movement_search.get_reachable_cells():
		if cell == start:
			continue

		var cost := movement_search.get_cost(cell)

		if cost < 0:
			continue

		var approach := HexGrid.get_distance(cell, target)

		if uses_paths:
			if not approach_costs.has(cell):
				continue

			approach = approach_costs[cell]

		var route_damage := _get_route_damage(grid, movement_search, cell)
		var total_damage := route_damage + _get_standing_damage(grid, cell)
		if forecast_unit != null and grid != null:
			var forecast := MovementImpactForecast.evaluate(forecast_unit, grid, movement_search.build_path(cell))
			if not forecast.reached or forecast.lethal:
				continue
			total_damage = forecast.damage

		# A unit that dies on the way never reaches the cell.
		if forecast_unit == null and grid != null and route_damage >= current_health:
			continue

		var score := _get_position_score(
			approach,
			total_damage,
			health
		)

		# Moving without gain only burns movement and makes units shuffle in place.
		if score >= stay_score:
			continue

		if has_best_cell and not _is_better_candidate(
			cell,
			score,
			cost,
			best_cell,
			best_score,
			best_cost
		):
			continue

		has_best_cell = true
		best_cell = cell
		best_score = score
		best_cost = cost

	if not has_best_cell:
		return null

	return MoveCommand.new(unit_id, best_cell)


## Lower is better. Approach is scaled by health, so damage counts as a share of it.
static func _get_position_score(approach: int, damage: int, health: int) -> int:
	return approach * health + damage * FULL_HEALTH_DETOUR_COST


## Movement cost from every connected cell to the nearest cell that can attack the target.
## Units are ignored: they move away, while walls and holes stay.
static func _get_approach_costs(
	grid: HexGrid,
	target: Vector2i,
	attack_range: int
) -> Dictionary[Vector2i, int]:
	var costs: Dictionary[Vector2i, int] = {}

	if grid == null:
		return costs

	var frontier: Array[Vector2i] = []

	for cell: Vector2i in grid.get_cells_in_range(target, maxi(attack_range, 1)):
		if cell != target and grid.is_traversable(cell):
			costs[cell] = 0
			frontier.append(cell)

	while not frontier.is_empty():
		var lowest_cost_index := 0

		for index: int in range(1, frontier.size()):
			if costs[frontier[index]] < costs[frontier[lowest_cost_index]]:
				lowest_cost_index = index

		var current := frontier[lowest_cost_index]
		frontier.remove_at(lowest_cost_index)
		# Stepping from a neighbor into the current cell pays the current cell's cost.
		var neighbor_cost := costs[current] + grid.get_movement_cost(current)

		for neighbor: Vector2i in grid.get_neighbors(current):
			if costs.has(neighbor) and neighbor_cost >= costs[neighbor]:
				continue

			costs[neighbor] = neighbor_cost
			frontier.append(neighbor)

	return costs


static func _get_route_damage(
	grid: HexGrid,
	movement_search: MovementSearchResult,
	cell: Vector2i
) -> int:
	if grid == null:
		return 0

	var damage := 0
	var path := movement_search.build_path(cell)

	# The engine walks exactly this path and applies every crossed hazard once.
	for index in range(1, path.size()):
		damage += HexStateCatalog.get_damage(grid.get_hex_state_id(path[index]))

	return damage


## A unit ending its move on a hazard takes this damage again when its next turn starts.
static func _get_standing_damage(grid: HexGrid, cell: Vector2i) -> int:
	if grid == null:
		return 0

	return HexStateCatalog.get_damage(grid.get_hex_state_id(cell))


static func _is_better_candidate(
	cell: Vector2i,
	score: int,
	cost: int,
	best_cell: Vector2i,
	best_score: int,
	best_cost: int
) -> bool:
	if score != best_score:
		return score < best_score

	if cost != best_cost:
		return cost < best_cost

	if cell.x != best_cell.x:
		return cell.x < best_cell.x

	return cell.y < best_cell.y
