extends RefCounted
## Tactical AI: the best plan of any own ready unit, scored on forecast copies.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")

var _profile := load("res://features/battle/definitions/tactical_enemy_ai.tres") as AIProfileDefinition


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	suite.expect(AICommandSource.supports(_profile) and _profile.id == &"core:tactical_enemy_ai", "The tactical profile is a supported AI profile")
	_run_finishing(suite, fixture)
	_run_unit_choice(suite, fixture)
	_run_threat(suite, fixture)
	_run_shooter_pressure(suite, fixture)


## An enemy phase in which no unit has started, so the AI may pick any of its units.
func _enemy_phase(state: BattleState) -> BattleSession:
	state.turn_service.start()
	state.turn_service.advance_phase()
	var setup := BattleSetup.new(state.battle_id, state.hex_grid, [], [], BattleObjectiveDefinition.new(), BattleFaction.Value.PLAYER, state.deterministic_seed)
	return BattleSession.new(setup, state, BattleEngine.new(state, false), null)


func _line(length: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for q in range(length):
		cells.append(Vector2i(q, 0))
	return cells


func _ai(fixture: Fixtures, id: StringName, hex: Vector2i, attack_range: int, damage: int, movement: int) -> UnitState:
	var unit := fixture.unit(id, BattleFaction.Value.ENEMY, hex, 100, movement)
	unit.basic_attack_range = attack_range
	unit.basic_attack_damage = damage
	return unit


func _run_finishing(suite: Node, fixture: Fixtures) -> void:
	var shooter := _ai(fixture, &"shooter", Vector2i.ZERO, 4, 3, 0)
	var healthy := fixture.unit(&"healthy", BattleFaction.Value.PLAYER, Vector2i(2, 0))
	var wounded := fixture.unit(&"wounded", BattleFaction.Value.PLAYER, Vector2i(3, 0), 3)
	var session := _enemy_phase(fixture.state(_line(5), [shooter, healthy, wounded]))
	var command := AICommandSource.new(_profile).next_command(session)
	suite.expect(command is AttackCommand and command.target_id == &"wounded", "The tactical AI finishes a wounded opponent instead of hitting the nearest")


func _run_unit_choice(suite: Node, fixture: Fixtures) -> void:
	var weak := _ai(fixture, &"weak", Vector2i(6, 0), 3, 1, 0)
	var strong := _ai(fixture, &"strong", Vector2i.ZERO, 3, 3, 0)
	var target := fixture.unit(&"target", BattleFaction.Value.PLAYER, Vector2i(3, 0), 3)
	var session := _enemy_phase(fixture.state(_line(7), [weak, strong, target]))
	suite.expect(session.get_active_unit_id() == &"weak", "The field order would start with the top-right unit")
	var source := AICommandSource.new(_profile)
	source.decision_trace = {}
	var command := source.next_command(session)
	suite.expect(command is AttackCommand and command.attacker_id == &"strong" and command.target_id == &"target", "The tactical AI acts first with the unit whose plan is best")
	suite.expect(source.decision_trace.get("reason") == "tactical_best_plan", "The choice is explained in the AI trace")


func _run_threat(suite: Node, fixture: Fixtures) -> void:
	var shooter := _ai(fixture, &"shooter", Vector2i(3, 0), 3, 3, 1)
	var brute := fixture.unit(&"brute", BattleFaction.Value.PLAYER, Vector2i(5, 0), 100, 1)
	brute.basic_attack_damage = 5
	var session := _enemy_phase(fixture.state(_line(7), [shooter, brute]))
	var command := AICommandSource.new(_profile).next_command(session)
	suite.expect(command is MoveCommand and command.destination == Vector2i(2, 0), "The tactical AI shoots from a hex the opponent cannot reach")


func _run_shooter_pressure(suite: Node, fixture: Fixtures) -> void:
	var fighter := _ai(fixture, &"fighter", Vector2i(2, 0), 1, 2, 1)
	var marksman := fixture.unit(&"marksman", BattleFaction.Value.PLAYER, Vector2i(4, 0))
	marksman.basic_attack_range = 4
	marksman.basic_attack_damage = 1
	var brawler := fixture.unit(&"brawler", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	brawler.basic_attack_damage = 1
	var session := _enemy_phase(fixture.state(_line(5), [fighter, marksman, brawler]))
	var command := AICommandSource.new(_profile).next_command(session)
	suite.expect(command is MoveCommand and command.destination == Vector2i(3, 0), "A tactical melee unit closes in on a shooter to deny its shot")
