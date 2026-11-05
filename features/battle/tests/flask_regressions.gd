extends RefCounted
## Flasks: obstacles that burst when destroyed — a spill of their contents, a pressure wave or
## an explosion — with chain reactions, forecasts, transactions, documents, log and AI.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")

const DEFECT := "did not settle"
const PLAYER := BattleFaction.Value.PLAYER
const ENEMY := BattleFaction.Value.ENEMY

var _tactical := load("res://features/battle/definitions/tactical_enemy_ai.tres") as AIProfileDefinition


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	_check_definitions(suite)
	_check_spills(suite, fixture)
	_check_pressure(suite, fixture)
	_check_explosion(suite, fixture)
	_check_chain(suite, fixture)
	_check_forecast_and_transaction(suite, fixture)
	_check_defect(suite, fixture)
	_check_documents(suite, fixture)
	_check_texts(suite)
	_check_ai(suite, fixture)


func _check_definitions(suite: Node) -> void:
	var flask := _flask(&"flask", Vector2i(1, 0), &"core:acid")
	for contents: StringName in BattleObstacleDefinition.CONTENTS:
		flask.contents = contents
		suite.expect(flask.validate().is_empty() and flask.is_flask(), "A flask with %s is valid" % contents)
	var invalid := flask.duplicate(true) as BattleObstacleDefinition
	invalid.hexes.append(Vector2i(2, 0))
	suite.expect(not invalid.validate().is_empty(), "A flask fills exactly one hex")
	invalid = flask.duplicate(true) as BattleObstacleDefinition
	invalid.destructible = false
	suite.expect(not invalid.validate().is_empty(), "A flask is always destructible")
	invalid = flask.duplicate(true) as BattleObstacleDefinition
	invalid.contents = &""
	suite.expect(not invalid.validate().is_empty(), "A spilling flask needs contents")
	invalid.contents = &"core:fire"
	suite.expect(not invalid.validate().is_empty(), "A flask holds only acid, water, oil or electricity")
	var rocks := _flask(&"rocks", Vector2i(1, 0), &"core:acid")
	suite.expect(not rocks.validate().is_empty() and not rocks.is_flask(), "Ordinary obstacles have no contents")
	rocks.contents = &""
	suite.expect(rocks.validate().is_empty(), "Rocks without contents stay valid")
	var pressure := _flask(&"pressure_flask", Vector2i(1, 0))
	suite.expect(pressure.validate().is_empty(), "A pressure flask needs no contents")
	pressure.contents = &"core:water"
	suite.expect(not pressure.validate().is_empty(), "A pressure flask holds no contents")
	var explosive := _flask(&"explosive_flask", Vector2i(1, 0))
	suite.expect(explosive.validate().is_empty() and explosive.blast_damage == BattleObstacleDefinition.DEFAULT_BLAST_DAMAGE, "An explosive flask has a default blast damage")
	for damage: int in [0, BattleObstacleDefinition.MAX_BLAST_DAMAGE + 1]:
		explosive.blast_damage = damage
		suite.expect(not explosive.validate().is_empty(), "Blast damage %d is out of range" % damage)
	explosive.blast_damage = BattleObstacleDefinition.MAX_BLAST_DAMAGE
	suite.expect(explosive.validate().is_empty(), "The largest blast damage is valid")


func _check_spills(suite: Node, fixture: Fixtures) -> void:
	# A broken small flask leaves its contents on its own hex only.
	var attacker := fixture.unit(&"attacker", PLAYER, Vector2i.ZERO)
	var enemy := fixture.unit(&"enemy", ENEMY, Vector2i(-3, 3))
	var state := fixture.state(_cells(3), [attacker, enemy])
	state.hex_grid.add_obstacle(_flask(&"flask", Vector2i(1, 0), &"core:acid", 2))
	var engine := BattleEngine.new(state)
	var result := engine.execute(AttackObstacleCommand.new(attacker.unit_id, Vector2i(1, 0)))
	suite.expect(result.accepted and result.terminal_error.is_empty() and not state.hex_grid.has_obstacle(Vector2i(1, 0)), "An attack breaks a flask")
	suite.expect(state.hex_grid.get_liquid(Vector2i(1, 0)) == &"core:acid", "A broken flask leaves its contents on its hex")
	suite.expect(not state.hex_grid.has_layers(Vector2i.ZERO) and not state.hex_grid.has_layers(Vector2i(2, 0)) and attacker.statuses.is_empty(), "A small flask spills on its own hex only")
	var broken := _broken(result.events)
	var removal := _last_obstacle_update(result.events)
	var spill := _layer_event(result.events, Vector2i(1, 0))
	suite.expect(broken.size() == 1 and broken[0].hex == Vector2i(1, 0) and broken[0].obstacle.current_hp == 0, "The burst is published once with the destroyed flask")
	suite.expect(removal >= 0 and removal < result.events.find(broken[0]) and result.events.find(broken[0]) < spill, "Map update, burst, then its spill")
	suite.expect(engine.get_active_unit_id() == enemy.unit_id, "Breaking a flask ends the attacker's turn")

	# A big flask also covers every existing neighbor, skipping other obstacles, and exposes occupants.
	attacker = fixture.unit(&"attacker", PLAYER, Vector2i.ZERO)
	var neighbor := fixture.unit(&"neighbor", ENEMY, Vector2i(2, 0))
	enemy = fixture.unit(&"enemy", ENEMY, Vector2i(-3, 3))
	# A second unit keeps the player phase going: no enemy phase exposes the neighbor again.
	var spare := fixture.unit(&"spare", PLAYER, Vector2i(-3, 0))
	state = fixture.state(_cells(3), [attacker, spare, neighbor, enemy])
	state.hex_grid.add_obstacle(_flask(&"big_flask", Vector2i(1, 0), &"core:water", 1))
	var rock := _flask(&"rocks", Vector2i(1, -1))
	rock.destructible = false
	state.hex_grid.add_obstacle(rock)
	engine = BattleEngine.new(state)
	result = engine.execute(AttackObstacleCommand.new(attacker.unit_id, Vector2i(1, 0)))
	var watered := true
	for direction: Vector2i in HexGrid.DIRECTIONS:
		var hex := Vector2i(1, 0) + direction
		if hex != rock.hexes[0]:
			watered = watered and state.hex_grid.get_liquid(hex) == &"core:water"
	suite.expect(result.accepted and watered and state.hex_grid.get_liquid(Vector2i(1, 0)) == &"core:water", "A big flask spills on its hex and every neighbor")
	suite.expect(state.hex_grid.has_obstacle(rock.hexes[0]) and not state.hex_grid.has_layers(rock.hexes[0]), "The spill skips another obstacle")
	suite.expect(neighbor.statuses.get(UnitStatusCatalog.WET, 0) == 2 and attacker.statuses.get(UnitStatusCatalog.WET, 0) > 0, "Units on the spill are exposed to it")

	# Electricity and oil spill as their own layers.
	state = fixture.state(_cells(2))
	state.hex_grid.add_obstacle(_flask(&"flask", Vector2i.ZERO, &"core:electricity"))
	state.hex_grid.add_obstacle(_flask(&"big_flask", Vector2i(2, -1), &"core:oil"))
	var events: Array[BattleEvent] = []
	suite.expect(ObstacleService.damage(state, Vector2i.ZERO, 5, events).is_empty() and state.hex_grid.get_energy(Vector2i.ZERO) == &"core:electricity", "An electricity flask leaves electricity")
	ObstacleService.damage(state, Vector2i(2, -1), 1, events)
	suite.expect(state.hex_grid.get_liquid(Vector2i(1, 0)) == &"core:oil" and state.hex_grid.get_movement_cost(Vector2i(1, 0)) == 2, "A big oil flask covers its neighbors with oil")
	var damaged := _flask(&"flask", Vector2i(0, 1), &"core:acid", 3)
	state.hex_grid.add_obstacle(damaged)
	events.clear()
	ObstacleService.damage(state, Vector2i(0, 1), 2, events)
	suite.expect(state.hex_grid.get_obstacle(Vector2i(0, 1)).current_hp == 1 and _broken(events).is_empty() and not state.hex_grid.has_layers(Vector2i(0, 1)), "A damaged flask that stands does not burst")


func _check_pressure(suite: Node, fixture: Fixtures) -> void:
	var east := fixture.unit(&"east", ENEMY, Vector2i(1, 0))
	var south := fixture.unit(&"south", PLAYER, Vector2i(0, 1))
	var west := fixture.unit(&"west", ENEMY, Vector2i(-1, 0))
	var wall := fixture.unit(&"wall", ENEMY, Vector2i(-2, 0))
	var holder := fixture.unit(&"holder", ENEMY, Vector2i(0, -1))
	holder.holds_hex = true
	var state := fixture.state(_cells(3), [east, south, west, wall, holder])
	state.hex_grid.add_obstacle(_flask(&"pressure_flask", Vector2i.ZERO))
	var events: Array[BattleEvent] = []
	suite.expect(ObstacleService.damage(state, Vector2i.ZERO, 1, events).is_empty(), "A pressure flask bursts")
	suite.expect(east.hex == Vector2i(3, 0) and south.hex == Vector2i(0, 3), "Neighbors of both sides fly 2 hexes straight away from the flask")
	suite.expect(east.health.current == 100 and south.health.current == 100, "A free flight costs no health")
	suite.expect(west.hex == Vector2i(-1, 0) and west.health.current == 99 and wall.health.current == 99 and wall.hex == Vector2i(-2, 0), "A unit behind stops the push and both take the collision")
	suite.expect(holder.hex == Vector2i(0, -1), "A unit that holds its hex stays")
	var pushes: Array[UnitPushedEvent] = []
	for event: BattleEvent in events:
		if event is UnitPushedEvent:
			pushes.append(event)
	suite.expect(pushes.size() == 3 and pushes.all(func(push: UnitPushedEvent) -> bool: return push.source_unit_id.is_empty()), "Flask pushes have no source unit")
	suite.expect(not state.hex_grid.has_layers(Vector2i.ZERO), "A pressure flask leaves no layer")

	# A unit pushed into a flask breaks it: its contents spill where it stood.
	var pusher := fixture.unit(&"pusher", PLAYER, Vector2i.ZERO)
	var target := fixture.unit(&"target", ENEMY, Vector2i(1, 0))
	state = fixture.state(_cells(3), [pusher, target])
	state.hex_grid.add_obstacle(_flask(&"flask", Vector2i(3, 0), &"core:acid"))
	events = BattleEffectContext.new(state, &"test:push").push(pusher.unit_id, target.unit_id, 2)
	suite.expect(target.hex == Vector2i(2, 0) and target.health.current == 99 and state.hex_grid.get_liquid(Vector2i(3, 0)) == &"core:acid", "A collision breaks a flask and it spills")
	suite.expect(_broken(events).size() == 1, "The collision's burst is part of the push's events")


func _check_explosion(suite: Node, fixture: Fixtures) -> void:
	var enemy := fixture.unit(&"enemy", ENEMY, Vector2i(1, 0))
	var ally := fixture.unit(&"ally", PLAYER, Vector2i(-1, 0))
	var far := fixture.unit(&"far", ENEMY, Vector2i(3, 0))
	var state := fixture.state(_cells(3), [ally, enemy, far])
	var flask := _flask(&"explosive_flask", Vector2i.ZERO)
	flask.blast_damage = 4
	state.hex_grid.add_obstacle(flask)
	var rock := _flask(&"rocks", Vector2i(0, 1), &"", 10)
	state.hex_grid.add_obstacle(rock)
	var events: Array[BattleEvent] = []
	suite.expect(ObstacleService.damage(state, Vector2i.ZERO, 1, events).is_empty(), "An explosive flask bursts")
	var blasts: Array[UnitDamagedEvent] = []
	for event: BattleEvent in events:
		if event is UnitDamagedEvent and not event.source_obstacle_id.is_empty():
			blasts.append(event)
	suite.expect(blasts.size() == 2 and blasts.all(func(hit: UnitDamagedEvent) -> bool: return hit.base_damage == 4 and hit.damage_type == &"fire" and hit.source_obstacle_id == flask.id and hit.attacker_id.is_empty()), "The blast deals its fire damage to every neighbor, of both sides")
	suite.expect(far.health.current == 100 and far.statuses.is_empty(), "The blast does not reach beyond the neighbors")
	var burning := true
	for hex: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1)]:
		burning = burning and state.hex_grid.get_energy(hex) == &"core:fire"
	suite.expect(burning, "Fire covers the flask's hex and its neighbors")
	suite.expect(state.hex_grid.get_obstacle(rock.hexes[0]).current_hp == 6 and not state.hex_grid.has_layers(rock.hexes[0]), "The blast damages an obstacle around and does not set it alight")
	suite.expect(enemy.health.current == 95 and enemy.statuses.get(UnitStatusCatalog.BURNING, 0) == 2, "A neighbor takes the blast, then the burning hex acts on it")

	# A melee attacker beside the flask is caught by its blast; a lethal blast decides the battle.
	var attacker := fixture.unit(&"attacker", PLAYER, Vector2i(-1, 0))
	var victim := fixture.unit(&"victim", ENEMY, Vector2i(1, 0), 3)
	state = fixture.state(_cells(3), [attacker, victim])
	flask = _flask(&"explosive_flask", Vector2i.ZERO, &"", 2)
	flask.blast_damage = 5
	state.hex_grid.add_obstacle(flask)
	var engine := BattleEngine.new(state)
	var result := engine.execute(AttackObstacleCommand.new(attacker.unit_id, Vector2i.ZERO))
	suite.expect(result.accepted and attacker.health.current == 94 and victim.health.is_defeated(), "The attacker is hit by its own blast and the victim dies")
	suite.expect(engine.get_outcome() == BattleOutcome.Value.VICTORY and result.battle_result != null, "A blast that kills the last enemy wins the battle")


func _check_chain(suite: Node, fixture: Fixtures) -> void:
	var near_both := fixture.unit(&"near_both", ENEMY, Vector2i(0, 1))
	var near_second := fixture.unit(&"near_second", ENEMY, Vector2i(2, 0))
	var state := fixture.state(_cells(3), [near_both, near_second])
	var first := _flask(&"explosive_flask", Vector2i.ZERO)
	var second := _flask(&"explosive_flask", Vector2i(1, 0), &"", 3)
	var sturdy := _flask(&"flask", Vector2i(-1, 0), &"core:acid", 5)
	for value: BattleObstacleDefinition in [first, second, sturdy]:
		state.hex_grid.add_obstacle(value)
	var events: Array[BattleEvent] = []
	suite.expect(ObstacleService.damage(state, Vector2i.ZERO, 1, events).is_empty(), "A chain of flasks resolves")
	var broken := _broken(events)
	suite.expect(broken.size() == 2 and broken[0].obstacle.id == first.id and broken[1].obstacle.id == second.id, "A flask caught by a blast bursts next, each flask once")
	suite.expect(not state.hex_grid.has_obstacle(Vector2i(1, 0)) and state.hex_grid.get_energy(Vector2i(1, 0)) == &"core:fire" and state.hex_grid.get_energy(Vector2i(2, 0)) == &"core:fire", "The second blast sets its own area alight")
	suite.expect(state.hex_grid.get_obstacle(sturdy.hexes[0]).current_hp == 2, "A sturdier flask only takes the blast")
	suite.expect(near_second.health.current == 96, "A unit beside the second flask takes its blast and its fire")
	suite.expect(near_both.health.current == 93, "A unit beside both flasks takes both blasts but its fire once")


func _check_forecast_and_transaction(suite: Node, fixture: Fixtures) -> void:
	var user := fixture.unit(&"user", PLAYER, Vector2i(-2, 0))
	var enemy := fixture.unit(&"enemy", ENEMY, Vector2i(2, 0))
	var spare := fixture.unit(&"spare", PLAYER, Vector2i(-3, 3))
	var ability := fixture.ability(&"test:blast", AbilityDefinition.TargetMode.HEX, 1)
	user.abilities[ability.id] = ability
	var state := fixture.state(_cells(3), [user, spare, enemy])
	var flask := _flask(&"explosive_flask", Vector2i(1, 0), &"", 3)
	flask.blast_damage = 2
	state.hex_grid.add_obstacle(flask)
	var engine := BattleEngine.new(state)
	var command := UseAbilityCommand.at_hex(user.unit_id, Vector2i(1, 0), ability.id)
	var preview := ActionPreview.build(engine.fork_for_prediction(), engine, command)
	suite.expect(preview.accepted and preview.broken_flasks.size() == 1 and preview.broken_flasks[0].id == flask.id, "The forecast names the flask that would burst")
	var change := preview.units.get(enemy.unit_id) as ActionPreview.UnitChange
	suite.expect(change != null and change.health_after == 94, "The forecast includes the blast, its fire and the ability's own hit")
	suite.expect(state.hex_grid.has_obstacle(Vector2i(1, 0)) and enemy.health.current == 100, "A forecast leaves the live flask and units untouched")
	var result := engine.execute(command)
	suite.expect(result.accepted and not state.hex_grid.has_obstacle(Vector2i(1, 0)) and enemy.health.current == 94, "An area ability breaks the flask inside its transaction")


func _check_defect(suite: Node, fixture: Fixtures) -> void:
	# A struck flask whose spill cannot settle stops the battle: the hit itself has landed.
	var attacker := fixture.unit(&"attacker", PLAYER, Vector2i.ZERO)
	var enemy := fixture.unit(&"enemy", ENEMY, Vector2i(-3, 3))
	var state := _defective(fixture, [attacker, enemy])
	var engine := _engine(state)
	var result := engine.execute(AttackObstacleCommand.new(attacker.unit_id, Vector2i(1, 0)))
	suite.expect(result.accepted and result.terminal_error.contains(DEFECT), "A burst that cannot settle stops the battle after the hit")
	suite.expect(not state.hex_grid.has_obstacle(Vector2i(1, 0)) and not state.hex_grid.has_layers(Vector2i(1, 0)), "The hit stands, the refused spill leaves no layer")
	suite.expect(not engine.execute(EndTurnCommand.new(enemy.unit_id)).accepted, "A stopped battle accepts no further commands")

	# Inside an ability the same burst rejects the whole ability.
	var user := fixture.unit(&"user", PLAYER, Vector2i.ZERO)
	enemy = fixture.unit(&"enemy", ENEMY, Vector2i(-3, 3))
	var ability := fixture.ability(&"test:blast", AbilityDefinition.TargetMode.HEX, 0)
	user.abilities[ability.id] = ability
	state = _defective(fixture, [user, enemy])
	engine = _engine(state)
	result = engine.execute(UseAbilityCommand.at_hex(user.unit_id, Vector2i(1, 0), ability.id))
	suite.expect(not result.accepted and result.rejection_reason.contains(DEFECT), "An ability whose burst cannot settle is rejected")
	suite.expect(state.hex_grid.get_obstacle(Vector2i(1, 0)) != null and state.hex_grid.get_obstacle(Vector2i(1, 0)).current_hp == 1 and user.turn.main_action_available, "The rejected ability leaves the flask and the action")


func _check_documents(suite: Node, fixture: Fixtures) -> void:
	var cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	var map := BattleMapDefinition.new()
	map.id = &"test:map"
	for hex: Vector2i in cells:
		map.cells.append(BattleMapCellDefinition.new(hex))
	var explosive := _flask(&"explosive_flask", Vector2i(1, 0), &"", 4)
	explosive.blast_damage = 7
	map.obstacles.append(_flask(&"big_flask", Vector2i.ZERO, &"core:oil", 2))
	map.obstacles.append(explosive)
	map.obstacles.append(_flask(&"pressure_flask", Vector2i(2, 0)))
	map.obstacles.append(_flask(&"rocks", Vector2i(3, 0), &"", 5))
	var battle := BattleDefinition.new()
	battle.id = &"test:battle"
	battle.map_id = map.id
	var document := BattleDocument.new(&"test:document", map, battle)
	var encoded := BattleDocumentSerializer.to_dictionary(document)
	var entries: Array = encoded.map.obstacles
	suite.expect(entries[0].contents == "core:oil" and not entries[0].has("blast_damage") and entries[1].blast_damage == 7 and not entries[1].has("contents"), "Flask settings are written for the flasks that use them")
	suite.expect(not entries[2].has("contents") and not entries[2].has("blast_damage") and not entries[3].has("contents") and not entries[3].has("blast_damage"), "Other obstacles carry no flask settings")
	var loaded := BattleDocumentSerializer.from_dictionary(JSON.parse_string(JSON.stringify(encoded)))
	suite.expect(loaded != null and loaded.map_definition.obstacles[0].contents == &"core:oil" and loaded.map_definition.obstacles[1].blast_damage == 7 and loaded.map_definition.obstacles[1].max_hp == 4, "Flasks survive the JSON round trip")
	var grid := BattleMapFactory.create_hex_grid(loaded.map_definition)
	suite.expect(grid != null and grid.get_obstacle(Vector2i(1, 0)).terrain_type == &"explosive_flask" and grid.get_obstacle(Vector2i.ZERO).contents == &"core:oil", "A saved document builds its flasks")
	var state := fixture.state(cells)
	state.hex_grid = grid.duplicate_grid()
	var events: Array[BattleEvent] = []
	ObstacleService.damage(state, Vector2i.ZERO, 9, events)
	suite.expect(state.hex_grid.get_liquid(Vector2i.ZERO) == &"core:oil" and grid.has_obstacle(Vector2i.ZERO) and not grid.has_layers(Vector2i.ZERO), "A burst on a grid copy leaves the original untouched")
	encoded.map.obstacles[0].contents = 5
	suite.expect(BattleDocumentSerializer.from_dictionary(encoded) == null, "Malformed flask contents are rejected structurally")


func _check_texts(suite: Node) -> void:
	var samples: Array[BattleObstacleDefinition] = [
		_flask(&"flask", Vector2i(1, 2), &"core:acid"), _flask(&"big_flask", Vector2i(1, 2), &"core:electricity"),
		_flask(&"pressure_flask", Vector2i(1, 2)), _flask(&"explosive_flask", Vector2i(1, 2)),
	]
	for flask: BattleObstacleDefinition in samples:
		var line := BattleLogFormatter.describe(ObstacleBrokenEvent.new(flask), {}, null)
		suite.expect(line.begins_with(ObstacleDescription.display_name(flask)) and line.contains("(1, 2)"), "The log describes the burst: %s" % line)
		suite.expect(not ObstacleDescription.burst(flask).is_empty(), "Hover details explain the burst of %s" % flask.terrain_type)
		suite.expect(ObstacleArt.texture(ObstacleArt.art_id(flask)) != null, "Art exists for %s" % ObstacleArt.art_id(flask))
	for contents: StringName in BattleObstacleDefinition.CONTENTS:
		suite.expect(ObstacleArt.SOURCES.has(ObstacleArt.art_id(_flask(&"flask", Vector2i.ZERO, contents))) and ObstacleArt.SOURCES.has(ObstacleArt.art_id(_flask(&"big_flask", Vector2i.ZERO, contents))), "Both flask sizes have art with %s" % contents)
	suite.expect(ObstacleDescription.display_name(samples[0]) == "Колба с кислотой" and ObstacleDescription.burst(_flask(&"rocks", Vector2i.ZERO)).is_empty(), "Flask names carry their contents; rocks have no burst")
	var hit := UnitDamagedEvent.new(&"", &"target", 3, 97, false)
	hit.source_obstacle_id = &"test:flask"
	hit.damage_type = &"fire"
	var line := BattleLogFormatter.describe(hit, {}, null)
	suite.expect(line.begins_with("Взрыв колбы → target: 3 урона") and line.contains("(взрыв колбы)"), "The log names blast damage: %s" % line)
	var preview := ActionPreview.new()
	preview.broken_flasks.append(samples[3])
	var lines: PackedStringArray = ActionPreviewText.describe(preview, {}, {}, false).lines
	suite.expect(lines.has("Взрывоопасная колба разобьётся"), "The forecast summary names the flask that bursts")


func _check_ai(suite: Node, fixture: Fixtures) -> void:
	# A shooter that cannot reach anyone breaks the flask beside two opponents.
	var shooter := fixture.unit(&"shooter", ENEMY, Vector2i(-1, 0), 100, 0)
	shooter.basic_attack_range = 2
	var first := fixture.unit(&"first", PLAYER, Vector2i(2, 0))
	var second := fixture.unit(&"second", PLAYER, Vector2i(2, -1))
	var state := fixture.state(_cells(3), [shooter, first, second])
	var flask := _flask(&"explosive_flask", Vector2i(1, 0), &"", 2)
	flask.blast_damage = 5
	state.hex_grid.add_obstacle(flask)
	var session := fixture.ai_session(state)
	var command := AICommandSource.new(_tactical).next_command(session)
	suite.expect(command is AttackObstacleCommand and command.target_hex == Vector2i(1, 0), "The tactical AI breaks a flask whose blast hits opponents")

	# The simple policy does not break a barrier flask that would hurt its own unit.
	var walker := fixture.unit(&"walker", ENEMY, Vector2i(0, 0), 100, 0)
	var ally := fixture.unit(&"ally", ENEMY, Vector2i(1, 1))
	var target := fixture.unit(&"target", PLAYER, Vector2i(3, 0))
	state = fixture.state(_cells(3), [walker, ally, target])
	state.hex_grid.add_obstacle(_flask(&"explosive_flask", Vector2i(1, 0), &"", 2))
	session = fixture.ai_session(state)
	command = AICommandSource.new(null).next_command(session)
	suite.expect(command is EndTurnCommand, "The simple AI leaves a flask whose blast would hurt its side")
	walker = fixture.unit(&"walker", ENEMY, Vector2i(0, 0), 100, 0)
	ally = fixture.unit(&"ally", ENEMY, Vector2i(1, 1))
	target = fixture.unit(&"target", PLAYER, Vector2i(3, 0))
	state = fixture.state(_cells(3), [walker, ally, target])
	state.hex_grid.add_obstacle(_flask(&"big_flask", Vector2i(1, 0), &"core:water", 2))
	session = fixture.ai_session(state)
	command = AICommandSource.new(null).next_command(session)
	suite.expect(command is AttackObstacleCommand, "The simple AI clears a flask whose burst costs no health")


## The battle screen draws flasks with their own art and plays each burst to its end.
func run_presentation(suite: Node) -> void:
	var screen := preload("res://features/battle/battle_screen.tscn").instantiate() as BattleScreen
	suite.expect(screen.setup(suite.fixture.request(true)), "Flask presentation battle setup accepted")
	suite.add_child(screen)
	await suite.get_tree().process_frame
	await suite.get_tree().process_frame
	var controller: BattleController = screen.get("_battle_controller")
	var queue: BattlePresentationQueue = controller.get("_presentation_queue")
	queue.set_speed(4.0)
	var map: BattleMapView = controller.get("_map_view")
	var hud := screen.get_node("BattleMap/BattleUI") as BattleHUD
	var views: BattleUnitViewRegistry = controller.get("_unit_views")
	var session: BattleSession = controller.get("_battle_session")
	var origin := HexCoordinateMapper.offset_to_axial(Vector2i(4, 4))
	var grid := HexGrid.new([origin, origin + Vector2i(1, 0)])
	var flask := _flask(&"explosive_flask", origin, &"", 2)
	grid.add_obstacle(flask)
	map.render_grid(grid)
	var visuals: Dictionary = map.get("_terrain_property_nodes")
	suite.expect(visuals.get(origin) is ObstacleCellVisual and (visuals[origin] as ObstacleCellVisual).obstacle.terrain_type == &"explosive_flask", "The battle map draws a flask on its hex")
	for type: StringName in BattleObstacleDefinition.FLASK_TYPES:
		var sample := _flask(type, origin, &"core:water" if BattleObstacleDefinition.SPILL_TYPES.has(type) else &"")
		var events: Array[BattleEvent] = [ObstacleBrokenEvent.new(sample)]
		var presented: bool = await queue.present(BattleResolution.success(events, 0, session.get_active_unit_id()), views.actors, views.definitions, map, hud)
		suite.expect(presented and queue.interrupted_steps == 0, "The burst of %s plays to its end" % type)
	await suite.get_tree().process_frame
	suite.expect(map.find_children("FlaskBurst", "", true, false).is_empty(), "Burst effects free themselves")
	screen.queue_free()
	await suite.get_tree().process_frame


## A flask on (1, 0) with water beside it, under a spreading rule that never settles.
func _defective(fixture: Fixtures, units: Array[UnitState]) -> BattleState:
	var state := fixture.state(_cells(3), units)
	state.hex_grid.set_hex_state(Vector2i(2, 0), &"core:water")
	state.hex_grid.set_hex_state(Vector2i(3, 0), &"core:water")
	state.hex_grid.add_obstacle(_flask(&"flask", Vector2i(1, 0), &"core:water"))
	state.spread_rule = _never_settles
	return state


## Electricity keeps running into water: the smallest rule that cannot settle.
func _never_settles(_source_liquid: StringName, _source_energy: StringName, neighbor_liquid: StringName, _neighbor_energy: StringName) -> StringName:
	return &"core:electricity" if neighbor_liquid == &"core:water" else &""


func _engine(state: BattleState) -> BattleEngine:
	Fixtures.start_turns(state)
	return BattleEngine.new(state, false)


static func _flask(type: StringName, hex: Vector2i, contents: StringName = &"", hp := 1) -> BattleObstacleDefinition:
	var value := BattleObstacleDefinition.new()
	value.id = StringName("test:%s_%d_%d" % [type, hex.x, hex.y])
	value.terrain_type = type
	value.hexes.assign([hex])
	value.destructible = true
	value.max_hp = hp
	value.current_hp = hp
	value.contents = contents
	return value


static func _broken(events: Array[BattleEvent]) -> Array[ObstacleBrokenEvent]:
	var result: Array[ObstacleBrokenEvent] = []
	for event: BattleEvent in events:
		if event is ObstacleBrokenEvent:
			result.append(event)
	return result


static func _last_obstacle_update(events: Array[BattleEvent]) -> int:
	var index := -1
	for position in range(events.size()):
		if events[position] is MapMutationEvent and events[position].obstacle_changed:
			index = position
	return index


static func _layer_event(events: Array[BattleEvent], hex: Vector2i) -> int:
	for position in range(events.size()):
		var event := events[position]
		if event is MapMutationEvent and event.kind == MapMutationKind.Value.APPLY_HEX_STATE and event.hex == hex:
			return position
	return -1


## A hexagon of the given radius around the origin.
static func _cells(radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		for r in range(maxi(-radius, -q - radius), mini(radius, radius - q) + 1):
			cells.append(Vector2i(q, r))
	return cells
