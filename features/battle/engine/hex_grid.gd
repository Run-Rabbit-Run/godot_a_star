class_name HexGrid
extends RefCounted


## Шесть направлений в осевой системе координат (q, r).
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


func _init(
	cells: Array[Vector2i],
	movement_costs: Dictionary[Vector2i, int] = {}
) -> void:
	for cell in cells:
		_cells[cell] = true
		_movement_costs[cell] = maxi(movement_costs.get(cell, 1), 1)


func has_cell(cell: Vector2i) -> bool:
	return _cells.has(cell)


## Отсутствующая клетка отмечается значением -1, существующая стоит минимум 1.
func get_movement_cost(cell: Vector2i) -> int:
	if not has_cell(cell):
		return -1

	return _movement_costs[cell]


## Возвращается копия ключей, поэтому внутреннее множество нельзя изменить снаружи.
func get_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(_cells.keys())

	return result


## Потенциальные соседи за границей логической сетки отбрасываются.
func get_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []

	if not has_cell(cell):
		return neighbors

	for direction in DIRECTIONS:
		var neighbor := cell + direction

		if has_cell(neighbor):
			neighbors.append(neighbor)

	return neighbors


func get_cells_in_range(
	center: Vector2i,
	radius: int
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	if radius < 0 or not has_cell(center):
		return result

	for cell in _cells:
		if get_distance(center, cell) <= radius:
			result.append(cell)

	return result


## Осевые координаты дополняются кубической осью s, где q + r + s = 0.
static func get_distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	var delta_q := from_cell.x - to_cell.x
	var delta_r := from_cell.y - to_cell.y
	var delta_s := -delta_q - delta_r

	return maxi(
		absi(delta_q),
		maxi(
			absi(delta_r),
			absi(delta_s)
		)
	)
