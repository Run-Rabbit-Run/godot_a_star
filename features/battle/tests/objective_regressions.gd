extends RefCounted
## Battle objectives: hold out, defeat the commander, keep marked units alive, the round limit.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	_run_outcomes(suite, fixture)
	_run_survive_in_battle(suite, fixture)
	_run_setup(suite, fixture)
	_run_validation(suite, fixture)
	_run_document(suite, fixture)
	_run_tactical_focus(suite, fixture)


func _units(fixture: Fixtures) -> Dictionary[StringName, UnitState]:
	var units: Dictionary[StringName, UnitState] = {}
	for unit: UnitState in [
		fixture.unit(&"hero", BattleFaction.Value.PLAYER, Vector2i.ZERO),
		fixture.unit(&"guide", BattleFaction.Value.PLAYER, Vector2i(1, 0)),
		fixture.unit(&"boss", BattleFaction.Value.ENEMY, Vector2i(4, 0)),
		fixture.unit(&"grunt", BattleFaction.Value.ENEMY, Vector2i(5, 0)),
	]:
		units[unit.unit_id] = unit
	return units


func _run_outcomes(suite: Node, fixture: Fixtures) -> void:
	var units := _units(fixture)
	var survive := ObjectiveSystem.new(SurviveRoundsObjective.new(2, BattleFaction.Value.ENEMY, "Hold"), BattleFaction.Value.PLAYER)
	suite.expect(survive.get_outcome(units, 2) == BattleOutcome.Value.IN_PROGRESS and survive.get_outcome(units, 3) == BattleOutcome.Value.VICTORY, "Holding out wins once the given round has ended")
	units[&"hero"].health.current = 0
	units[&"guide"].health.current = 0
	suite.expect(survive.get_outcome(units, 3) == BattleOutcome.Value.DEFEAT, "Losing every unit is a defeat even at the last round")

	units = _units(fixture)
	var commander := ObjectiveSystem.new(EliminateTargetsObjective.new([&"boss"], BattleFaction.Value.ENEMY, "Boss"), BattleFaction.Value.PLAYER)
	units[&"grunt"].health.current = 0
	suite.expect(commander.get_outcome(units, 1) == BattleOutcome.Value.IN_PROGRESS, "Other enemies falling does not win the commander objective")
	units[&"grunt"].health.current = 100
	units[&"boss"].health.current = 0
	suite.expect(commander.get_outcome(units, 1) == BattleOutcome.Value.VICTORY and commander.get_target_unit_ids() == [&"boss"], "Defeating the commander wins while others still stand")

	units = _units(fixture)
	var protect := ObjectiveSystem.new(EliminateFactionObjective.new(BattleFaction.Value.ENEMY, "All"), BattleFaction.Value.PLAYER, [&"guide"])
	units[&"guide"].health.current = 0
	suite.expect(protect.get_outcome(units, 1) == BattleOutcome.Value.DEFEAT, "Losing a protected unit loses the battle")
	units[&"boss"].health.current = 0
	units[&"grunt"].health.current = 0
	suite.expect(protect.get_outcome(units, 1) == BattleOutcome.Value.DEFEAT, "Defeat outweighs a victory reached at the same moment")

	units = _units(fixture)
	var limited := ObjectiveSystem.new(EliminateFactionObjective.new(BattleFaction.Value.ENEMY, "All"), BattleFaction.Value.PLAYER, [], 2)
	suite.expect(limited.get_outcome(units, 2) == BattleOutcome.Value.IN_PROGRESS and limited.get_outcome(units, 3) == BattleOutcome.Value.DEFEAT, "A battle not won when the round limit ends is lost")
	suite.expect(BattleObjectiveDefinition.new().round_limit == 99, "The default round limit is 99")


func _run_survive_in_battle(suite: Node, fixture: Fixtures) -> void:
	var player := fixture.unit(&"player", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var enemy := fixture.unit(&"enemy", BattleFaction.Value.ENEMY, Vector2i(5, 0))
	var cells: Array[Vector2i] = []
	for q in range(6):
		cells.append(Vector2i(q, 0))
	var state := fixture.state(cells, [player, enemy])
	state.objective_system = ObjectiveSystem.new(SurviveRoundsObjective.new(2, BattleFaction.Value.ENEMY, "Hold"), BattleFaction.Value.PLAYER)
	var engine := BattleEngine.new(state)
	var resolution: BattleResolution
	for step in range(4):
		resolution = engine.execute(EndPhaseCommand.new(engine.get_active_faction()))
	var round_three_started := false
	for event: BattleEvent in resolution.events:
		round_three_started = round_three_started or (event is PhaseStartedEvent and event.round_number == 3)
	suite.expect(resolution.battle_result != null and resolution.battle_result.outcome == BattleOutcome.Value.VICTORY and resolution.battle_result.round_number == 3, "The battle is won when round two has ended")
	suite.expect(not round_three_started, "A decided battle starts no new phase")


## The battle definition of the regression fixture with its objective replaced.
func _request(fixture: Fixtures, objective: BattleObjectiveDefinition) -> BattleStartRequest:
	var request := fixture.request()
	var snapshot := request.content_snapshot
	var battle := snapshot.get_battle_definition(request.battle_id)
	battle.primary_objective = objective
	var units: Array[UnitDefinition] = []
	request.content_snapshot = snapshot.with_battle_document(snapshot.get_map_definition(battle.map_id), battle, units)
	return request


func _run_setup(suite: Node, fixture: Fixtures) -> void:
	var objective := BattleObjectiveDefinition.new()
	objective.type = BattleObjectiveType.Value.ELIMINATE_TARGETS
	objective.description = "Убить командира"
	objective.target_placement_ids = [&"author:placement_8"]
	objective.protected_placement_ids = [&"author:placement_5"]
	var creation := BattleSessionFactory.create(_request(fixture, objective))
	suite.expect(creation.is_successful, "A commander objective with a protected unit starts a battle")
	if creation.is_successful:
		suite.expect(creation.session.get_objective_target_ids() == [&"plateau:battle:author:placement_8"] and creation.session.get_protected_unit_ids() == [&"plateau:battle:author:placement_5"], "Marked placements become the battle's unit ids")


func _run_validation(suite: Node, fixture: Fixtures) -> void:
	var battle := fixture.request().content_snapshot.get_battle_definition(&"plateau:battle")
	var cases := [
		[BattleObjectiveType.Value.ELIMINATE_TARGETS, [], [], 5, 99, "commander"],
		[BattleObjectiveType.Value.ELIMINATE_TARGETS, [&"author:placement_4"], [], 5, 99, "target faction"],
		[BattleObjectiveType.Value.ELIMINATE_FACTION, [], [&"author:placement_7"], 5, 99, "protected faction"],
		[BattleObjectiveType.Value.SURVIVE_ROUNDS, [], [], 20, 10, "Rounds to survive"],
		[BattleObjectiveType.Value.ELIMINATE_FACTION, [], [], 5, 0, "round limit"],
	]
	for entry: Array in cases:
		var objective := BattleObjectiveDefinition.new()
		objective.type = entry[0]
		objective.description = "Test"
		objective.target_placement_ids.assign(entry[1])
		objective.protected_placement_ids.assign(entry[2])
		objective.rounds = entry[3]
		objective.round_limit = entry[4]
		battle.primary_objective = objective
		var result := BattleDefinitionValidator.validate(battle)
		suite.expect(not result.is_valid and String(entry[5]) in result.error_message, "Objective validation rejects: %s" % entry[5])


func _run_document(suite: Node, _fixture: Fixtures) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Fixtures.BATTLE_PATH))
	var document := BattleDocumentSerializer.from_dictionary(data)
	suite.expect(document.battle_definition.primary_objective.round_limit == 99 and document.battle_definition.primary_objective.rounds == 5 and document.battle_definition.primary_objective.target_placement_ids.is_empty(), "Older files read the objective defaults")
	var objective := document.battle_definition.primary_objective
	objective.type = BattleObjectiveType.Value.SURVIVE_ROUNDS
	objective.rounds = 7
	objective.round_limit = 30
	objective.protected_placement_ids = [&"author:placement_4"]
	var copy := BattleDocumentSerializer.from_dictionary(BattleDocumentSerializer.to_dictionary(document)).battle_definition.primary_objective
	suite.expect(copy.type == BattleObjectiveType.Value.SURVIVE_ROUNDS and copy.rounds == 7 and copy.round_limit == 30 and copy.protected_placement_ids == [&"author:placement_4"], "Objective parameters survive a save and load")


func _run_tactical_focus(suite: Node, fixture: Fixtures) -> void:
	var shooter := fixture.unit(&"shooter", BattleFaction.Value.ENEMY, Vector2i.ZERO, 100, 0)
	shooter.basic_attack_range = 4
	shooter.basic_attack_damage = 3
	var near := fixture.unit(&"near", BattleFaction.Value.PLAYER, Vector2i(2, 0))
	var guarded := fixture.unit(&"guarded", BattleFaction.Value.PLAYER, Vector2i(3, 0))
	var cells: Array[Vector2i] = []
	for q in range(5):
		cells.append(Vector2i(q, 0))
	var state := fixture.state(cells, [shooter, near, guarded])
	state.objective_system = ObjectiveSystem.new(EliminateFactionObjective.new(BattleFaction.Value.ENEMY, "All"), BattleFaction.Value.PLAYER, [&"guarded"])
	state.turn_service.start()
	state.turn_service.advance_phase()
	var setup := BattleSetup.new(state.battle_id, state.hex_grid, [], [], BattleObjectiveDefinition.new(), BattleFaction.Value.PLAYER, state.deterministic_seed)
	var session := BattleSession.new(setup, state, BattleEngine.new(state, false), null)
	var command := AICommandSource.new(load("res://features/battle/definitions/tactical_enemy_ai.tres")).next_command(session)
	suite.expect(command is AttackCommand and command.target_id == &"guarded", "The tactical AI goes for the unit the player has to protect")
