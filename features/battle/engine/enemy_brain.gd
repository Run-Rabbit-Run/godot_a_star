class_name EnemyBrain
extends RefCounted

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


static func choose_move(
	unit_id: StringName,
	start: Vector2i,
	target: Vector2i,
	movement_search: MovementSearchResult
) -> MoveCommand:
	if unit_id.is_empty() or movement_search == null:
		return null

	var has_best_cell := false
	var best_cell := Vector2i.ZERO
	var best_distance := 0
	var best_cost := 0

	for cell: Vector2i in movement_search.get_reachable_cells():
		if cell == start:
			continue

		var distance := HexGrid.get_distance(cell, target)
		var cost := movement_search.get_cost(cell)

		if cost < 0:
			continue

		if has_best_cell and not _is_better_candidate(
			cell,
			distance,
			cost,
			best_cell,
			best_distance,
			best_cost
		):
			continue

		has_best_cell = true
		best_cell = cell
		best_distance = distance
		best_cost = cost

	if not has_best_cell:
		return null

	return MoveCommand.new(unit_id, best_cell)


static func choose_attack(
	attacker_id: StringName,
	attacker_hex: Vector2i,
	target_id: StringName,
	target_hex: Vector2i,
	main_action_available: bool
) -> AttackCommand:
	if attacker_id.is_empty() or target_id.is_empty():
		return null

	if attacker_id == target_id:
		return null

	if not main_action_available:
		return null

	if HexGrid.get_distance(attacker_hex, target_hex) != 1:
		return null

	return AttackCommand.new(attacker_id, target_id)

static func _is_better_candidate(
	cell: Vector2i,
	distance: int,
	cost: int,
	best_cell: Vector2i,
	best_distance: int,
	best_cost: int
) -> bool:
	if distance != best_distance:
		return distance < best_distance

	if cost != best_cost:
		return cost < best_cost

	if cell.x != best_cell.x:
		return cell.x < best_cell.x

	return cell.y < best_cell.y
