extends RefCounted
## Ordinary attack: a ranged unit cannot shoot while engaged and strikes neighbors for half damage.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	_run_penalty(suite)
	_run_engine(suite, fixture)
	_run_retaliation(suite, fixture)
	_run_obstacles(suite, fixture)
	_run_ai(suite, fixture)


func _run_penalty(suite: Node) -> void:
	var halved: Array[int] = []
	for damage: int in [1, 2, 3, 4, 5, 6]:
		halved.append(damage - BasicAttackRules.melee_penalty(3, damage))
	suite.expect(halved == [1, 1, 1, 2, 2, 3], "Melee strike of a ranged unit halves damage, rounding down, at least 1")
	suite.expect(BasicAttackRules.melee_penalty(1, 6) == 0, "A melee unit strikes without the penalty")
	suite.expect(BasicAttackRules.melee_penalty(3, 0) == 0, "Zero damage gets no penalty")
	var opponents: Array[Vector2i] = [Vector2i(1, 0)]
	suite.expect(BasicAttackRules.is_engaged(Vector2i.ZERO, opponents) and not BasicAttackRules.is_engaged(Vector2i(-1, 0), opponents), "Only a neighboring opponent engages")
	suite.expect(not BasicAttackRules.reaches(3, Vector2i.ZERO, Vector2i(3, 0), true) and BasicAttackRules.reaches(3, Vector2i.ZERO, Vector2i(1, 0), true), "An engaged ranged unit reaches only its neighbors")


func _run_engine(suite: Node, fixture: Fixtures) -> void:
	var cells := _line(-2, 6)
	var shooter := _shooter(fixture, &"shooter", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var near := fixture.unit(&"near", BattleFaction.Value.ENEMY, Vector2i(1, 0))
	var far := fixture.unit(&"far", BattleFaction.Value.ENEMY, Vector2i(3, 0))
	var state := fixture.state(cells, [shooter, near, far])
	var engine := BattleEngine.new(state)
	var targets := engine.get_attackable_targets(shooter.unit_id)
	suite.expect(targets.size() == 1 and targets[0].unit_id == near.unit_id, "An engaged shooter may attack only the neighboring opponent")
	suite.expect(not engine.execute(AttackCommand.new(shooter.unit_id, far.unit_id)).accepted and shooter.turn.main_action_available, "A shot past the neighbor is rejected without spending the action")
	var strike := engine.execute(AttackCommand.new(shooter.unit_id, near.unit_id))
	var hit := _first_damage(strike.events)
	suite.expect(strike.accepted and near.health.current == 98, "A melee strike deals half of 5 damage")
	suite.expect(hit != null and not hit.ranged_attack and hit.base_damage == 5 and hit.calculated_damage == 2, "The strike event keeps base damage and is not a shot")
	suite.expect(hit != null and not hit.damage_modifiers.is_empty() and hit.damage_modifiers[0].source_id == BasicAttackRules.RANGED_MELEE_PENALTY and hit.damage_modifiers[0].amount == -3, "The penalty is the first damage modifier")
	suite.expect(hit != null and BattleLogFormatter._damage_formula(hit, null).contains("стрелок в ближнем бою"), "The battle log names the penalty")

	# Steam protects against the shot, not against the melee strike.
	shooter = _shooter(fixture, &"shooter", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	near = fixture.unit(&"near", BattleFaction.Value.ENEMY, Vector2i(1, 0))
	state = fixture.state(cells, [shooter, near])
	state.hex_grid.set_hex_state(near.hex, &"core:steam")
	engine = BattleEngine.new(state)
	engine.execute(AttackCommand.new(shooter.unit_id, near.unit_id))
	suite.expect(near.health.current == 98, "Steam does not reduce a melee strike")
	shooter = _shooter(fixture, &"shooter", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	far = fixture.unit(&"far", BattleFaction.Value.ENEMY, Vector2i(3, 0))
	state = fixture.state(cells, [shooter, far])
	state.hex_grid.set_hex_state(far.hex, &"core:steam")
	engine = BattleEngine.new(state)
	var shot := engine.execute(AttackCommand.new(shooter.unit_id, far.unit_id))
	hit = _first_damage(shot.events)
	suite.expect(shot.accepted and far.health.current == 98 and hit != null and hit.ranged_attack, "A free shooter shoots at full damage, reduced only by steam")
	suite.expect(hit != null and hit.damage_modifiers.size() == 1 and hit.damage_modifiers[0].source_id == &"core:steam", "A shot carries no melee penalty")


func _run_retaliation(suite: Node, fixture: Fixtures) -> void:
	var cells := _line(-2, 6)
	var shooter := _shooter(fixture, &"shooter", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var guard := fixture.unit(&"guard", BattleFaction.Value.ENEMY, Vector2i(1, 0))
	guard.passive_ability_ids = [&"core:melee_retaliation"]
	var engine := BattleEngine.new(fixture.state(cells, [shooter, guard]))
	engine.execute(AttackCommand.new(shooter.unit_id, guard.unit_id))
	suite.expect(guard.health.current == 98 and shooter.health.current == 98, "A melee strike of a shooter provokes retaliation")

	shooter = _shooter(fixture, &"shooter", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	guard = fixture.unit(&"guard", BattleFaction.Value.ENEMY, Vector2i(3, 0))
	guard.passive_ability_ids = [&"core:melee_retaliation"]
	engine = BattleEngine.new(fixture.state(cells, [shooter, guard]))
	engine.execute(AttackCommand.new(shooter.unit_id, guard.unit_id))
	suite.expect(guard.health.current == 95 and shooter.health.current == 100, "A shot provokes no retaliation")

	var fighter := fixture.unit(&"fighter", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var ranged_guard := _shooter(fixture, &"ranged_guard", BattleFaction.Value.ENEMY, Vector2i(1, 0))
	ranged_guard.passive_ability_ids = [&"core:melee_retaliation"]
	engine = BattleEngine.new(fixture.state(cells, [fighter, ranged_guard]))
	var attack := engine.execute(AttackCommand.new(fighter.unit_id, ranged_guard.unit_id))
	var response: UnitDamagedEvent
	for event: BattleEvent in attack.events:
		if event is UnitDamagedEvent and event.source_ability_id == &"core:melee_retaliation":
			response = event
	suite.expect(fighter.health.current == 98 and response != null and not response.ranged_attack, "A ranged defender retaliates in melee for half damage")


func _run_obstacles(suite: Node, fixture: Fixtures) -> void:
	var cells := _line(-2, 6)
	var shooter := _shooter(fixture, &"shooter", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var near := fixture.unit(&"near", BattleFaction.Value.ENEMY, Vector2i(-1, 0))
	var state := fixture.state(cells, [shooter, near])
	state.hex_grid.add_obstacle(_obstacle(Vector2i(2, 0)))
	var engine := BattleEngine.new(state)
	suite.expect(engine.get_attackable_obstacle_hexes(shooter.unit_id).is_empty(), "An engaged shooter cannot shoot an obstacle")
	suite.expect(not engine.execute(AttackObstacleCommand.new(shooter.unit_id, Vector2i(2, 0))).accepted, "The obstacle shot command is rejected while engaged")

	shooter = _shooter(fixture, &"shooter", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var distant := fixture.unit(&"distant", BattleFaction.Value.ENEMY, Vector2i(5, 0))
	state = fixture.state(cells, [shooter, distant])
	state.hex_grid.add_obstacle(_obstacle(Vector2i(1, 0)))
	engine = BattleEngine.new(state)
	suite.expect(engine.execute(AttackObstacleCommand.new(shooter.unit_id, Vector2i(1, 0))).accepted and state.hex_grid.get_obstacle(Vector2i(1, 0)).current_hp == 8, "A shooter strikes an adjacent obstacle for half damage")


func _run_ai(suite: Node, fixture: Fixtures) -> void:
	var cells := _line(-3, 3)
	var shooter := _shooter(fixture, &"ai_shooter", BattleFaction.Value.ENEMY, Vector2i.ZERO)
	var player := fixture.unit(&"player", BattleFaction.Value.PLAYER, Vector2i(1, 0))
	var session := fixture.ai_session(fixture.state(cells, [shooter, player]))
	var source := AICommandSource.new(null)
	source.decision_trace = {}
	var command := source.next_command(session)
	suite.expect(command is MoveCommand and command.destination == Vector2i(-1, 0), "An engaged AI shooter steps to the nearest free firing position")
	suite.expect(source.decision_trace.get("reason") == "ranged_disengage_before_shot", "The step away is explained in the AI trace")
	suite.expect(session.step(command).accepted, "The AI step is accepted")
	command = source.next_command(session)
	suite.expect(command is AttackCommand and command.target_id == player.unit_id, "After stepping away the AI shooter shoots")
	suite.expect(session.step(command).accepted and player.health.current == 95, "The AI shot deals full damage")

	shooter = _shooter(fixture, &"ai_shooter", BattleFaction.Value.ENEMY, Vector2i.ZERO, 0)
	player = fixture.unit(&"player", BattleFaction.Value.PLAYER, Vector2i(1, 0))
	session = fixture.ai_session(fixture.state(cells, [shooter, player]))
	command = source.next_command(session)
	suite.expect(command is AttackCommand and command.target_id == player.unit_id, "An AI shooter that cannot step away strikes in melee")

	# Approaching, a shooter stops short of a cell next to another opponent.
	var grid := HexGrid.new(_line(0, 6))
	var blocked: Dictionary[Vector2i, bool] = {Vector2i(4, 0): true}
	var search := MovementService.search(grid, Vector2i.ZERO, 5, blocked)
	var opponents: Array[Vector2i] = [Vector2i(4, 0), Vector2i(2, 1)]
	var approach := EnemyBrain.choose_move(&"ai_shooter", Vector2i.ZERO, Vector2i(4, 0), search, grid, 10, 2, null, opponents)
	suite.expect(approach != null and approach.destination == Vector2i(1, 0), "An approaching AI shooter does not end next to an opponent")


func _shooter(fixture: Fixtures, id: StringName, faction: BattleFaction.Value, hex: Vector2i, movement := 8) -> UnitState:
	var unit := fixture.unit(id, faction, hex, 100, movement)
	unit.basic_attack_range = 3
	unit.basic_attack_damage = 5
	return unit


func _line(from: int, to: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for q in range(from, to + 1):
		cells.append(Vector2i(q, 0))
	return cells


func _obstacle(hex: Vector2i) -> BattleObstacleDefinition:
	var obstacle := BattleObstacleDefinition.new()
	obstacle.id = StringName("test:obstacle_%d_%d" % [hex.x, hex.y])
	obstacle.destructible = true
	obstacle.max_hp = 10
	obstacle.hexes.append(hex)
	return obstacle


func _first_damage(events: Array[BattleEvent]) -> UnitDamagedEvent:
	for event: BattleEvent in events:
		if event is UnitDamagedEvent:
			return event
	return null
