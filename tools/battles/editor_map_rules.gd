class_name EditorMapRules
extends RefCounted
## Editing rules of a battle document: what a brush may change on the field and why not.
## The editor shows the reason; commands still check the document when they are applied.

const NO_HEX := Vector2i(999999, 999999)


static func find_cell(document: BattleDocument, hex: Vector2i) -> BattleMapCellDefinition:
	if document == null:
		return null
	for cell: BattleMapCellDefinition in document.map_definition.cells:
		if cell.hex == hex:
			return cell
	return null


static func find_placement(document: BattleDocument, placement_id: StringName) -> UnitPlacementDefinition:
	if document == null or placement_id.is_empty():
		return null
	for placement: UnitPlacementDefinition in document.battle_definition.unit_placements:
		if placement.placement_id == placement_id:
			return placement
	return null


static func obstacle_at(document: BattleDocument, hex: Vector2i) -> BattleObstacleDefinition:
	if document == null:
		return null
	for obstacle: BattleObstacleDefinition in document.map_definition.obstacles:
		if obstacle.hexes.has(hex):
			return obstacle
	return null


static func is_occupied(document: BattleDocument, hex: Vector2i) -> bool:
	if document == null:
		return false
	for placement: UnitPlacementDefinition in document.battle_definition.unit_placements:
		if placement.start_hex == hex:
			return true
	return false


## Empty when a unit (other than the ignored placement) may start on the hex.
static func placement_target_error(document: BattleDocument, hex: Vector2i, ignored_placement_id: StringName) -> String:
	for existing: UnitPlacementDefinition in document.battle_definition.unit_placements:
		if existing.start_hex == hex and existing.placement_id != ignored_placement_id:
			return "Гекс уже занят юнитом."
	var cell := find_cell(document, hex)
	if cell == null:
		return "Юнита можно поставить только на существующий гекс."
	if not cell.traversable or obstacle_at(document, hex) != null:
		return "Нельзя поставить юнита на непроходимый гекс."
	return ""


## Empty when the existing hex may be removed from the map.
static func remove_hex_error(document: BattleDocument, hex: Vector2i) -> String:
	if obstacle_at(document, hex) != null:
		return "Сначала удалите препятствие целиком."
	if is_occupied(document, hex):
		return "Сначала переместите или удалите юнита с этого гекса."
	return ""


## Empty when an obstacle may cover exactly these hexes; `previous` is the obstacle it replaces.
static func obstacle_footprint_error(document: BattleDocument, hexes: Array[Vector2i], previous: BattleObstacleDefinition) -> String:
	for hex: Vector2i in hexes:
		var cell := find_cell(document, hex)
		if not EditorBattleView.is_in_frame(hex) or cell == null or not cell.traversable or is_occupied(document, hex):
			return "Препятствие требует свободные существующие гексы внутри поля."
		var other := obstacle_at(document, hex)
		if other != null and other != previous:
			return "Препятствия не могут пересекаться."
	return ""


## The nearest free traversable hex inside the frame, or NO_HEX.
static func free_hex_near(document: BattleDocument, origin: Vector2i) -> Vector2i:
	var best := NO_HEX
	var best_distance := 999999
	for cell: BattleMapCellDefinition in document.map_definition.cells:
		if not cell.traversable or obstacle_at(document, cell.hex) != null or is_occupied(document, cell.hex) or not EditorBattleView.is_in_frame(cell.hex):
			continue
		var distance := HexGrid.get_distance(origin, cell.hex)
		if distance < best_distance:
			best_distance = distance
			best = cell.hex
	return best


## Obstacle IDs stay unique inside the document across editor sessions.
static func new_obstacle_id(document: BattleDocument) -> StringName:
	var id := StringName()
	while id.is_empty() or document.map_definition.obstacles.any(func(obstacle: BattleObstacleDefinition) -> bool: return obstacle.id == id):
		id = StringName("obstacle:%s" % Crypto.new().generate_random_bytes(8).hex_encode())
	return id
