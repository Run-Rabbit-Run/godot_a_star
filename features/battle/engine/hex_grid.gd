class_name HexGrid
extends RefCounted


const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
]


var _cells: Dictionary[Vector2i, bool] = {}
var _movement_costs: Dictionary[Vector2i, int] = {}
var _terrain_ids: Dictionary[Vector2i, StringName] = {}
var _traversable: Dictionary[Vector2i, bool] = {}


func _init(
	cells: Array[Vector2i],
	movement_costs: Dictionary[Vector2i, int] = {},
	terrain_ids: Dictionary[Vector2i, StringName] = {},
	traversal: Dictionary[Vector2i, bool] = {}
) -> void:
	for cell: Vector2i in cells:
		_cells[cell] = true
		_movement_costs[cell] = maxi(movement_costs.get(cell, 1), 1)
		_terrain_ids[cell] = terrain_ids.get(cell, &"core:default")
		_traversable[cell] = traversal.get(cell, true)


func has_cell(cell: Vector2i) -> bool:
	return _cells.has(cell)


func is_traversable(cell: Vector2i) -> bool:
	return has_cell(cell) and _traversable.get(cell, false)


func get_movement_cost(cell: Vector2i) -> int:
	if not is_traversable(cell):
		return -1

	return _movement_costs[cell]


func get_configured_movement_cost(cell: Vector2i) -> int:
	if not has_cell(cell):
		return -1

	return _movement_costs[cell]


func get_terrain_id(cell: Vector2i) -> StringName:
	return _terrain_ids.get(cell, StringName())


func get_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(_cells.keys())
	return result


func get_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []

	if not has_cell(cell):
		return neighbors

	for direction: Vector2i in DIRECTIONS:
		var neighbor := cell + direction

		if is_traversable(neighbor):
			neighbors.append(neighbor)

	return neighbors


func get_cells_in_range(
	center: Vector2i,
	radius: int
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	if radius < 0 or not has_cell(center):
		return result

	for cell: Vector2i in _cells:
		if get_distance(center, cell) <= radius:
			result.append(cell)

	return result


func duplicate_grid() -> HexGrid:
	return HexGrid.new(
		get_cells(),
		_movement_costs,
		_terrain_ids,
		_traversable
	)


func replace_with(other: HexGrid) -> bool:
	if other == null:
		return false

	_cells.clear()
	_movement_costs.clear()
	_terrain_ids.clear()
	_traversable.clear()

	for cell: Vector2i in other.get_cells():
		_cells[cell] = true
		_movement_costs[cell] = other._movement_costs[cell]
		_terrain_ids[cell] = other._terrain_ids[cell]
		_traversable[cell] = other._traversable[cell]

	return true


func add_cell(
	cell: Vector2i,
	terrain_id: StringName,
	movement_cost: int,
	traversable: bool
) -> bool:
	if has_cell(cell) or terrain_id.is_empty() or movement_cost < 1:
		return false

	_cells[cell] = true
	_movement_costs[cell] = movement_cost
	_terrain_ids[cell] = terrain_id
	_traversable[cell] = traversable
	return true


func remove_cell(cell: Vector2i) -> bool:
	if not has_cell(cell):
		return false

	_cells.erase(cell)
	_movement_costs.erase(cell)
	_terrain_ids.erase(cell)
	_traversable.erase(cell)
	return true


func change_terrain(cell: Vector2i, terrain_id: StringName) -> bool:
	if not has_cell(cell) or terrain_id.is_empty():
		return false

	_terrain_ids[cell] = terrain_id
	return true


func set_traversal(
	cell: Vector2i,
	traversable: bool,
	movement_cost: int
) -> bool:
	if not has_cell(cell) or movement_cost < 1:
		return false

	_traversable[cell] = traversable
	_movement_costs[cell] = movement_cost
	return true


static func get_distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	var delta_q := from_cell.x - to_cell.x
	var delta_r := from_cell.y - to_cell.y
	var delta_s := -delta_q - delta_r
	return maxi(
		absi(delta_q),
		maxi(absi(delta_r), absi(delta_s))
	)
