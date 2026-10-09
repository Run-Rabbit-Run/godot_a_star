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


var _obstacles: Dictionary[StringName, BattleObstacleDefinition] = {}
var _obstacle_cells: Dictionary[Vector2i, StringName] = {}

var _cells: Dictionary[Vector2i, bool] = {}
var _movement_costs: Dictionary[Vector2i, int] = {}
var _terrain_ids: Dictionary[Vector2i, StringName] = {}
var _traversable: Dictionary[Vector2i, bool] = {}
var _hex_state_ids: Dictionary[Vector2i, StringName] = {}
var _hex_state_turns: Dictionary[Vector2i, int] = {}


func _init(
	cells: Array[Vector2i],
	movement_costs: Dictionary[Vector2i, int] = {},
	terrain_ids: Dictionary[Vector2i, StringName] = {},
	traversal: Dictionary[Vector2i, bool] = {},
	hex_state_ids: Dictionary[Vector2i, StringName] = {},
	hex_state_turns: Dictionary[Vector2i, int] = {}
) -> void:
	for cell: Vector2i in cells:
		_cells[cell] = true
		_movement_costs[cell] = maxi(movement_costs.get(cell, 1), 1)
		_terrain_ids[cell] = terrain_ids.get(cell, &"core:default")
		_traversable[cell] = traversal.get(cell, true)
		_hex_state_ids[cell] = hex_state_ids.get(cell, StringName())
		_hex_state_turns[cell] = hex_state_turns.get(cell, HexStateCatalog.LIFETIME) if not _hex_state_ids[cell].is_empty() else 0


func has_cell(cell: Vector2i) -> bool:
	return _cells.has(cell)


func is_traversable(cell: Vector2i) -> bool:
	return has_cell(cell) and not has_obstacle(cell) and _traversable.get(cell, false)


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


func get_hex_state_id(cell: Vector2i) -> StringName:
	return _hex_state_ids.get(cell, StringName())


func get_hex_state_turns(cell: Vector2i) -> int:
	return _hex_state_turns.get(cell, 0)


func set_hex_state_turns(cell: Vector2i, turns: int) -> bool:
	if not has_cell(cell) or get_hex_state_id(cell).is_empty() or turns < 1 or turns > HexStateCatalog.LIFETIME:
		return false
	_hex_state_turns[cell] = turns
	return true


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
	var copy := HexGrid.new(
		get_cells(),
		_movement_costs,
		_terrain_ids,
		_traversable,
		_hex_state_ids,
		_hex_state_turns
	)
	copy._copy_obstacles(self)
	return copy


func replace_with(other: HexGrid) -> bool:
	if other == null:
		return false

	_copy_obstacles(other)
	_cells.clear()
	_movement_costs.clear()
	_terrain_ids.clear()
	_traversable.clear()
	_hex_state_ids.clear()
	_hex_state_turns.clear()

	for cell: Vector2i in other.get_cells():
		_cells[cell] = true
		_movement_costs[cell] = other._movement_costs[cell]
		_terrain_ids[cell] = other._terrain_ids[cell]
		_traversable[cell] = other._traversable[cell]
		_hex_state_ids[cell] = other._hex_state_ids[cell]
		_hex_state_turns[cell] = other._hex_state_turns[cell]

	return true


func add_cell(
	cell: Vector2i,
	terrain_id: StringName,
	movement_cost: int,
	traversable: bool,
	hex_state_id: StringName = StringName()
) -> bool:
	if has_cell(cell) or terrain_id.is_empty() or movement_cost < 1:
		return false

	if not hex_state_id.is_empty() and (
		not HexStateCatalog.has_state(hex_state_id)
		or movement_cost != HexStateCatalog.get_movement_cost(hex_state_id)
	):
		return false

	_cells[cell] = true
	_movement_costs[cell] = movement_cost
	_terrain_ids[cell] = terrain_id
	_traversable[cell] = traversable
	_hex_state_ids[cell] = hex_state_id
	_hex_state_turns[cell] = HexStateCatalog.LIFETIME if not hex_state_id.is_empty() else 0
	return true


func remove_cell(cell: Vector2i) -> bool:
	if not has_cell(cell) or has_obstacle(cell):
		return false

	_cells.erase(cell)
	_movement_costs.erase(cell)
	_terrain_ids.erase(cell)
	_traversable.erase(cell)
	_hex_state_ids.erase(cell)
	_hex_state_turns.erase(cell)
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

	var state_id := get_hex_state_id(cell)

	if not state_id.is_empty() and movement_cost != HexStateCatalog.get_movement_cost(state_id):
		return false

	_traversable[cell] = traversable
	_movement_costs[cell] = movement_cost
	return true


func set_hex_state(cell: Vector2i, id: StringName) -> bool:
	if not has_cell(cell) or has_obstacle(cell) or (not id.is_empty() and not HexStateCatalog.has_state(id)):
		return false
	_hex_state_ids[cell] = id
	_hex_state_turns[cell] = HexStateCatalog.LIFETIME if not id.is_empty() else 0
	_movement_costs[cell] = HexStateCatalog.get_movement_cost(id)
	return true


static func get_distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	var delta_q := from_cell.x - to_cell.x
	var delta_r := from_cell.y - to_cell.y
	var delta_s := -delta_q - delta_r
	return maxi(
		absi(delta_q),
		maxi(absi(delta_r), absi(delta_s))
	)


func has_obstacle(hex: Vector2i) -> bool:
	return _obstacle_cells.has(hex)

func get_obstacle(hex: Vector2i) -> BattleObstacleDefinition:
	var value := _obstacles.get(_obstacle_cells.get(hex, &"")) as BattleObstacleDefinition
	return value.duplicate(true) as BattleObstacleDefinition if value != null else null

func add_obstacle(value: BattleObstacleDefinition) -> bool:
	if value == null or not value.validate().is_empty() or _obstacles.has(value.id):
		return false
	for hex: Vector2i in value.hexes:
		if not is_traversable(hex) or has_obstacle(hex) or not get_hex_state_id(hex).is_empty():
			return false
	var copy := value.duplicate(true) as BattleObstacleDefinition
	copy.current_hp = copy.max_hp
	_obstacles[copy.id] = copy
	for hex: Vector2i in copy.hexes:
		_obstacle_cells[hex] = copy.id
	return true

func damage_obstacle(hex: Vector2i, amount: int) -> int:
	var value := _obstacles.get(_obstacle_cells.get(hex, &"")) as BattleObstacleDefinition
	if value == null or not value.destructible or amount <= 0:
		return 0
	var damage := mini(amount, value.current_hp)
	value.current_hp -= damage
	if value.current_hp == 0:
		for occupied: Vector2i in value.hexes:
			_obstacle_cells.erase(occupied)
		_obstacles.erase(value.id)
	return damage

func _copy_obstacles(other: HexGrid) -> void:
	_obstacles.clear()
	_obstacle_cells = other._obstacle_cells.duplicate()
	for id: StringName in other._obstacles:
		_obstacles[id] = other._obstacles[id].duplicate(true) as BattleObstacleDefinition
