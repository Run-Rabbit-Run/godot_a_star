extends RefCounted
## Editing rules of the battle editor on a small hand-built document, without the editor UI.


func run(suite: Node) -> void:
	var document := _document()
	var free := Vector2i(1, 1)
	var unit_hex := Vector2i(1, 2)
	var blocked := Vector2i(2, 1)
	var missing := Vector2i(5, 5)
	var empty: StringName = &""

	suite.expect(EditorMapRules.placement_target_error(document, free, empty).is_empty(), "A unit may start on a free traversable hex")
	suite.expect(EditorMapRules.placement_target_error(document, unit_hex, empty) == "Гекс уже занят юнитом.", "A unit may not start on another unit")
	suite.expect(EditorMapRules.placement_target_error(document, unit_hex, &"author:placement_1").is_empty(), "A unit may stay on its own hex when it moves")
	suite.expect(EditorMapRules.placement_target_error(document, missing, empty) == "Юнита можно поставить только на существующий гекс.", "A unit may not start outside the map")
	suite.expect(EditorMapRules.placement_target_error(document, blocked, empty) == "Нельзя поставить юнита на непроходимый гекс.", "A unit may not start on an impassable hex")
	suite.expect(EditorMapRules.placement_target_error(document, Vector2i(3, 1), empty) == "Нельзя поставить юнита на непроходимый гекс.", "A unit may not start on an obstacle")

	suite.expect(EditorMapRules.remove_hex_error(document, free).is_empty(), "A free hex may be removed")
	suite.expect(EditorMapRules.remove_hex_error(document, Vector2i(4, 1)) == "Сначала удалите препятствие целиком.", "A hex under an obstacle is not removed piece by piece")
	suite.expect(EditorMapRules.remove_hex_error(document, unit_hex) == "Сначала переместите или удалите юнита с этого гекса.", "A hex with a unit is not removed")

	var obstacle := EditorMapRules.obstacle_at(document, Vector2i(3, 1))
	var footprint: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1)]
	suite.expect(EditorMapRules.obstacle_footprint_error(document, footprint, null) == "Препятствие требует свободные существующие гексы внутри поля.", "An obstacle may not cover an impassable hex")
	footprint.assign([Vector2i(1, 1), Vector2i(1, 2)])
	suite.expect(not EditorMapRules.obstacle_footprint_error(document, footprint, null).is_empty(), "An obstacle may not cover a unit")
	footprint.assign([Vector2i(2, 2), Vector2i(3, 1)])
	suite.expect(EditorMapRules.obstacle_footprint_error(document, footprint, null) == "Препятствия не могут пересекаться.", "Obstacles may not overlap")
	footprint.assign([Vector2i(3, 1), Vector2i(4, 1), Vector2i(4, 0)])
	suite.expect(EditorMapRules.obstacle_footprint_error(document, footprint, obstacle).is_empty(), "An obstacle may be reshaped over its own hexes")

	var copy_hex := EditorMapRules.free_hex_near(document, unit_hex)
	suite.expect(HexGrid.get_distance(copy_hex, unit_hex) == 1 and EditorMapRules.placement_target_error(document, copy_hex, empty).is_empty(), "The nearest free traversable hex is chosen for a copy")
	var crowded := _document()
	for cell: BattleMapCellDefinition in crowded.map_definition.cells:
		cell.traversable = false
	suite.expect(EditorMapRules.free_hex_near(crowded, unit_hex) == EditorMapRules.NO_HEX, "No free hex is reported as NO_HEX")
	var id := EditorMapRules.new_obstacle_id(document)
	suite.expect(String(id).begins_with("obstacle:") and EditorMapRules.obstacle_at(document, Vector2i(3, 1)).id != id, "A new obstacle ID is unique in the document")


## Cells (0..4, 0..2); an impassable hex at (2, 1), a unit at (1, 2), an obstacle on (3, 1)-(4, 1).
func _document() -> BattleDocument:
	var map := BattleMapDefinition.new()
	map.id = &"test:rules_map"
	for q in range(5):
		for r in range(3):
			map.cells.append(BattleMapCellDefinition.new(Vector2i(q, r)))
	for cell: BattleMapCellDefinition in map.cells:
		if cell.hex == Vector2i(2, 1):
			cell.traversable = false
	var obstacle := BattleObstacleDefinition.new()
	obstacle.id = &"test:rock"
	obstacle.hexes.assign([Vector2i(3, 1), Vector2i(4, 1)])
	map.obstacles.append(obstacle)
	var battle := BattleDefinition.new()
	battle.id = &"test:rules_battle"
	battle.map_id = map.id
	var placement := UnitPlacementDefinition.new()
	placement.placement_id = &"author:placement_1"
	placement.start_hex = Vector2i(1, 2)
	battle.unit_placements.append(placement)
	return BattleDocument.new(&"test:rules_document", map, battle)
