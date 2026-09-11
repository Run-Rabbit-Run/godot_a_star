class_name MovementSearchResult
extends RefCounted


var _costs: Dictionary[Vector2i, int] = {}
var _came_from: Dictionary[Vector2i, Vector2i] = {}
var map_revision: int
var state_revision: int


## Копии не позволяют вызывающему коду изменить уже завершённый поиск.
func _init(
	costs: Dictionary[Vector2i, int],
	came_from: Dictionary[Vector2i, Vector2i],
	p_map_revision: int = 0,
	p_state_revision: int = 0
) -> void:
	map_revision = maxi(p_map_revision, 0)
	state_revision = maxi(p_state_revision, 0)
	for cell in costs:
		_costs[cell] = costs[cell]

	for cell in came_from:
		_came_from[cell] = came_from[cell]


func get_reachable_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(_costs.keys())

	return result


func get_cost(cell: Vector2i) -> int:
	return _costs.get(cell, -1)


## Цепочка хранится от цели к старту, поэтому перед возвратом разворачивается.
func build_path(destination: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []

	if not _costs.has(destination):
		return path

	var current := destination
	path.append(current)

	while _came_from.has(current):
		current = _came_from[current]
		path.append(current)

	path.reverse()

	return path