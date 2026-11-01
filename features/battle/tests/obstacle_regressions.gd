extends RefCounted
## Obstacles: grid footprint, document round trip, attacks and their artwork in battle.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")


func run_obstacles(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0)]
	var obstacle := BattleObstacleDefinition.new()
	obstacle.id = &"test:obstacle"
	obstacle.destructible = true
	obstacle.max_hp = 5
	for size in range(1, 5):
		obstacle.hexes.clear()
		for index in range(size):
			obstacle.hexes.append(Vector2i(index + 1, 0))
		var grid := HexGrid.new(cells)
		suite.expect(grid.add_obstacle(obstacle), "Place obstacle of size %d" % size)
		suite.expect(not grid.is_traversable(obstacle.hexes.back()), "Every obstacle hex blocks movement")
		suite.expect(not grid.set_hex_state(obstacle.hexes[0], &"core:fire"), "Obstacle rejects direct hex states")
		var events: Array[BattleEvent] = []
		var explosions: Array[Dictionary] = []
		HexStateService.apply_to_grid(grid, obstacle.hexes[0], &"core:water", events, explosions)
		suite.expect(events.is_empty() and grid.get_hex_state_id(obstacle.hexes[0]).is_empty(), "Hex state effect skips obstacle without events")
		var snapshot := grid.get_obstacle(obstacle.hexes[0])
		snapshot.current_hp = 1
		suite.expect(grid.get_obstacle(obstacle.hexes[0]).current_hp == 5, "Obstacle query is detached")
		suite.expect(grid.damage_obstacle(obstacle.hexes.back(), 2) == 2, "Any obstacle hex can receive damage")
		suite.expect(grid.get_obstacle(obstacle.hexes[0]).current_hp == 3, "Footprint shares HP")
		var copy := grid.duplicate_grid()
		suite.expect(copy.get_obstacle(obstacle.hexes[0]).current_hp == 3, "Grid clone preserves partial HP")
		copy.damage_obstacle(obstacle.hexes[0], 30)
		suite.expect(grid.has_obstacle(obstacle.hexes[0]), "Prediction clone cannot destroy live obstacle")
		suite.expect(copy.is_traversable(obstacle.hexes.back()), "Destroyed clone releases whole footprint")
		grid.replace_with(copy)
		suite.expect(not grid.has_obstacle(obstacle.hexes[0]), "Grid commit copies obstacle removal")
	obstacle.hexes.assign([Vector2i(1, 0), Vector2i(2, 0)])
	obstacle.destructible = false
	var grid := HexGrid.new(cells)
	grid.add_obstacle(obstacle)
	suite.expect(grid.damage_obstacle(Vector2i(1, 0), 999) == 0 and grid.has_obstacle(Vector2i(1, 0)), "Indestructible obstacle ignores damage")
	var overlap := obstacle.duplicate(true) as BattleObstacleDefinition
	overlap.id = &"test:overlap"
	suite.expect(not grid.add_obstacle(overlap), "Overlapping obstacle rejected")
	suite.expect(not grid.remove_cell(Vector2i(1, 0)), "Cannot delete part of a runtime obstacle")
	var invalid := obstacle.duplicate(true) as BattleObstacleDefinition
	invalid.hexes.assign([Vector2i(1, 0), Vector2i(3, 0)])
	suite.expect(not invalid.validate().is_empty(), "Footprint with a gap rejected")
	invalid.hexes.assign([Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)])
	suite.expect(not invalid.validate().is_empty(), "Bent footprint rejected")
	invalid.hexes.assign(cells)
	suite.expect(not invalid.validate().is_empty(), "Footprint larger than four rejected")
	invalid.hexes.assign([Vector2i(1, 0)])
	invalid.max_hp = 0
	suite.expect(not invalid.validate().is_empty(), "Nonpositive obstacle HP rejected")
	grid.set_hex_state(Vector2i.ZERO, &"core:fire")
	var propagation: Array[BattleEvent] = []
	HexStateService.propagate(grid, [Vector2i.ZERO], propagation)
	suite.expect(grid.get_hex_state_id(Vector2i(1, 0)).is_empty(), "Propagation cannot give obstacle a state")
	# A document with an obstacle survives its JSON round trip with the same resource definition.
	var map := BattleMapDefinition.new()
	map.id = &"test:map"
	for hex: Vector2i in cells:
		map.cells.append(BattleMapCellDefinition.new(hex))
	var battle := BattleDefinition.new()
	battle.id = &"test:battle"
	battle.map_id = map.id
	var document := BattleDocument.new(&"test:document", map, battle)
	obstacle.destructible = true
	document.map_definition.obstacles.append(obstacle.duplicate(true))
	var encoded := BattleDocumentSerializer.to_dictionary(document)
	var loaded := BattleDocumentSerializer.from_dictionary(encoded)
	suite.expect(loaded != null and loaded.map_definition.obstacles.size() == 1, "Obstacle JSON round trip")
	suite.expect(loaded.map_definition.obstacles[0].hexes == obstacle.hexes and loaded.map_definition.obstacles[0].max_hp == 5, "Footprint and HP survive JSON")
	suite.expect(BattleMapFactory.create_hex_grid(loaded.map_definition).has_obstacle(Vector2i(2, 0)), "Saved document builds obstacle in ordinary map factory")
	encoded.map.obstacles[0].hexes = [["bad", 0]]
	suite.expect(BattleDocumentSerializer.from_dictionary(encoded) == null, "Malformed obstacle coordinate rejected structurally")
	# Attack consumes one action, rejects invalid attempts, frees all cells after destruction.
	var player := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var enemy := fixture.unit(&"e", BattleFaction.Value.ENEMY, Vector2i(5, 0))
	var state := fixture.state(cells, [player, enemy])
	state.hex_grid.add_obstacle(obstacle)
	var engine := BattleEngine.new(state)
	var result := engine.execute(AttackObstacleCommand.new(player.unit_id, Vector2i(2, 0)))
	suite.expect(not result.accepted and player.turn.main_action_available, "Out of range obstacle attack consumes nothing")
	result = engine.execute(AttackObstacleCommand.new(player.unit_id, Vector2i(1, 0)))
	suite.expect(result.accepted and state.hex_grid.get_obstacle(Vector2i(2, 0)).current_hp == 3, "Basic attack damages shared obstacle HP")
	suite.expect(engine.get_active_unit_id() == enemy.unit_id, "Obstacle attack ends acting unit turn")
	var damage_events: Array[BattleEvent] = []
	ObstacleService.damage(state, Vector2i(2, 0), 3, damage_events)
	suite.expect(state.hex_grid.is_traversable(Vector2i(1, 0)) and state.hex_grid.is_traversable(Vector2i(2, 0)), "Destruction frees every hex")
	suite.expect(damage_events.size() == 2 and damage_events[0].obstacle == null, "Destruction publishes map updates for every occupied cell")
	suite.expect(not BattleLogFormatter.describe(damage_events[0], {}, null).is_empty(), "Obstacle damage is visible in battle log")
	# Area damage hits a multi-cell obstacle once, and state-only casts skip it.
	player = fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	enemy = fixture.unit(&"e", BattleFaction.Value.ENEMY, Vector2i(5, 0))
	var ability := fixture.ability(&"test:blast", AbilityDefinition.TargetMode.HEX, 1)
	player.abilities[ability.id] = ability
	state = fixture.state(cells, [player, enemy])
	state.hex_grid.add_obstacle(obstacle)
	engine = BattleEngine.new(state)
	result = engine.execute(UseAbilityCommand.at_hex(player.unit_id, Vector2i(1, 0), ability.id))
	suite.expect(result.accepted and state.hex_grid.get_obstacle(Vector2i(2, 0)).current_hp == 2, "Area damage hits obstacle exactly once")
	var serialized: Dictionary = BattleLogSerializer.encode(state.hex_grid)
	suite.expect(serialized.cells[1].obstacle.current_hp == 2, "Diagnostic snapshot includes obstacle HP")
	# AI clears a reachable destructible barrier when no movement can approach the enemy.
	player = fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i(5, 0))
	enemy = fixture.unit(&"e", BattleFaction.Value.ENEMY, Vector2i.ZERO)
	state = fixture.state(cells, [enemy, player])
	state.hex_grid.add_obstacle(obstacle)
	var session := fixture.ai_session(state)
	var command := AICommandSource.new(null).next_command(session)
	suite.expect(command is AttackObstacleCommand, "AI chooses obstacle attack with movement available")
	enemy.turn.movement_remaining = 0
	command = AICommandSource.new(null).next_command(session)
	suite.expect(command is AttackObstacleCommand and session.step(command).accepted, "AI attacks a blocking barrier even after movement is exhausted")


func run_obstacle_view(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var origin := HexCoordinateMapper.offset_to_axial(Vector2i(4, 4))
	var request := fixture.request(true)
	var screen := (load("res://features/battle/battle_screen.tscn") as PackedScene).instantiate() as BattleScreen
	screen.setup(request)
	suite.get_tree().root.add_child(screen)
	await suite.get_tree().process_frame
	await suite.get_tree().process_frame
	var map := screen.get_node("BattleMap") as BattleMapView
	var grid := HexGrid.new([origin, origin + Vector2i(1, 0)])
	var obstacle := BattleObstacleDefinition.new()
	obstacle.id = &"test:view_obstacle"
	obstacle.hexes.assign([origin, origin + Vector2i(1, 0)])
	obstacle.destructible = true
	obstacle.max_hp = 5
	grid.add_obstacle(obstacle)
	map.render_grid(grid)
	var visuals: Dictionary = map.get("_terrain_property_nodes")
	suite.expect(visuals[origin] is ObstacleCellVisual and visuals[origin + Vector2i(1, 0)] is ObstacleCellVisual, "Runtime map draws terrain artwork on every obstacle cell")
	var events: Array[BattleEvent] = []
	var state := fixture.state(grid.get_cells())
	state.hex_grid = grid
	ObstacleService.damage(state, origin, 2, events)
	for event: MapMutationEvent in events:
		map.apply_map_event(event)
	suite.expect((visuals[origin] as ObstacleCellVisual).obstacle.current_hp == 3, "Runtime map applies HP update from authoritative events")
	events.clear()
	ObstacleService.damage(state, origin, 9, events)
	for event: MapMutationEvent in events:
		map.apply_map_event(event)
	suite.expect(not visuals.has(origin) and not visuals.has(origin + Vector2i(1, 0)), "Runtime destruction events remove all obstacle artwork")
	screen.queue_free()
	await suite.get_tree().process_frame
