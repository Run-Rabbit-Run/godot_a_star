extends RefCounted
## Paralysis never stacks and leaves resistance behind, so no unit stays paralyzed for good.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	_run_status_rules(suite, fixture)
	_run_phase_cycle(suite, fixture)
	_run_one_turn(suite, fixture)
	var pin := load("res://features/abilities/definitions/spear_pin.tres") as AbilityDefinition
	suite.expect(pin.cooldown_turns == 3, "Spear pin waits three own turns between uses")


func _run_status_rules(suite: Node, fixture: Fixtures) -> void:
	var events: Array[BattleEvent] = []
	var unit := fixture.unit(&"unit", BattleFaction.Value.ENEMY, Vector2i.ZERO)
	UnitStatusService.apply(unit, &"core:paralysis", 2, events)
	UnitStatusService.apply(unit, &"core:paralysis", 1, events)
	suite.expect(unit.statuses.get(&"core:paralysis", 0) == 1, "Paralysis does not stack past one level")
	unit.statuses.clear()
	UnitStatusService.apply(unit, &"core:electrified", 5, events)
	UnitStatusService.apply(unit, &"core:electrified", 2, events)
	suite.expect(unit.statuses.get(&"core:paralysis", 0) == 1, "Repeated charge past the threshold keeps a single paralysis level")

	unit.statuses.assign({&"core:paralysis_resistance": 1})
	UnitStatusService.apply(unit, &"core:paralysis", 1, events)
	UnitStatusService.apply(unit, &"core:electrified", 6, events)
	suite.expect(not unit.statuses.has(&"core:paralysis"), "Resistance blocks paralysis from abilities and from charge")

	unit.statuses.assign({&"core:paralysis": 1})
	UnitStatusService.apply(unit, &"core:paralysis_resistance", 1, events)
	suite.expect(not unit.statuses.has(&"core:paralysis") and unit.statuses.get(&"core:paralysis_resistance", 0) == 1, "Applying resistance lifts paralysis at once")

	unit.statuses.assign({&"core:paralysis": 1})
	events.clear()
	UnitStatusService.end_phase(unit, false, events)
	suite.expect(unit.statuses.get(&"core:paralysis", 0) == 1 and events.is_empty(), "Paralysis that took no turn stays past the phase end")
	UnitStatusService.end_phase(unit, true, events)
	suite.expect(not unit.statuses.has(&"core:paralysis") and unit.statuses.get(&"core:paralysis_resistance", 0) == 1, "Paralysis that took the turn wears off at the phase end and leaves one resistance level")
	var shown := false
	for event: BattleEvent in events:
		shown = shown or (event is UnitStatusChangedEvent and event.statuses.has(&"core:paralysis_resistance"))
	suite.expect(shown, "The status change event shows the new resistance")
	UnitStatusService.end_phase(unit, true, events)
	suite.expect(unit.statuses.get(&"core:paralysis_resistance", 0) == 1, "Resistance is a property: the phase end does not wear it off")
	UnitStatusService.start_phase(unit, events)
	suite.expect(unit.statuses.is_empty(), "Resistance loses its level at the start of its side's next phase")


func _run_phase_cycle(suite: Node, fixture: Fixtures) -> void:
	var cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	var player := fixture.unit(&"player", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var enemy := fixture.unit(&"enemy", BattleFaction.Value.ENEMY, Vector2i(3, 0))
	var engine := BattleEngine.new(fixture.state(cells, [player, enemy]))
	var events: Array[BattleEvent] = []
	UnitStatusService.apply(enemy, &"core:paralysis", 1, events)
	engine.execute(EndPhaseCommand.new(BattleFaction.Value.PLAYER))
	suite.expect(engine.get_active_faction() == BattleFaction.Value.PLAYER and engine.get_round_number() == 2, "The paralyzed enemy loses its phase")
	suite.expect(enemy.statuses.get(&"core:paralysis_resistance", 0) == 1, "The enemy comes out of paralysis resistant")
	UnitStatusService.apply(enemy, &"core:paralysis", 1, events)
	engine.execute(EndPhaseCommand.new(BattleFaction.Value.PLAYER))
	suite.expect(engine.get_active_faction() == BattleFaction.Value.ENEMY and engine.can_command(&"enemy"), "A resistant enemy acts in its next phase")
	engine.execute(EndTurnCommand.new(&"enemy"))
	UnitStatusService.apply(enemy, &"core:paralysis", 1, events)
	suite.expect(enemy.statuses.get(&"core:paralysis", 0) == 1, "After its turn the enemy can be paralyzed again")


## Paralysis costs exactly one turn, whenever the unit gets it.
func _run_one_turn(suite: Node, fixture: Fixtures) -> void:
	var cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(5, 0)]
	var first := fixture.unit(&"a_first", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var second := fixture.unit(&"b_second", BattleFaction.Value.PLAYER, Vector2i(0, 1))
	var enemy := fixture.unit(&"enemy", BattleFaction.Value.ENEMY, Vector2i(5, 0))
	var engine := BattleEngine.new(fixture.state(cells, [first, second, enemy]))
	var events: Array[BattleEvent] = []
	engine.execute(EndTurnCommand.new(first.unit_id))
	UnitStatusService.apply(first, &"core:paralysis", 1, events)
	engine.execute(EndTurnCommand.new(second.unit_id))
	suite.expect(engine.get_active_faction() == BattleFaction.Value.ENEMY and first.statuses.get(&"core:paralysis", 0) == 1, "Paralysis gained after the unit's turn survives the phase end")
	engine.execute(EndTurnCommand.new(enemy.unit_id))
	suite.expect(engine.get_active_faction() == BattleFaction.Value.PLAYER and not engine.can_command(first.unit_id) and engine.can_command(second.unit_id), "It takes the unit's next phase")
	engine.execute(EndTurnCommand.new(second.unit_id))
	suite.expect(not first.statuses.has(&"core:paralysis") and first.statuses.get(&"core:paralysis_resistance", 0) == 1, "It wears off at the end of the phase it took")

	# Paralysis in the middle of the unit's own turn takes the rest of this phase only.
	first = fixture.unit(&"a_first", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	second = fixture.unit(&"b_second", BattleFaction.Value.PLAYER, Vector2i(0, 1))
	enemy = fixture.unit(&"enemy", BattleFaction.Value.ENEMY, Vector2i(5, 0))
	var state := fixture.state(cells, [first, second, enemy])
	state.hex_grid.set_hex_state(Vector2i(1, 0), &"core:electricity")
	engine = BattleEngine.new(state)
	first.statuses[&"core:electrified"] = 3
	var moved := engine.execute(MoveCommand.new(first.unit_id, Vector2i(1, 0)))
	var ended := false
	for event: BattleEvent in moved.events:
		ended = ended or (event is TurnEndedEvent and event.unit_id == first.unit_id)
	suite.expect(first.statuses.get(&"core:paralysis", 0) == 1 and ended and engine.can_command(second.unit_id), "Charge paralysis ends the started turn")
	engine.execute(EndTurnCommand.new(second.unit_id))
	suite.expect(not first.statuses.has(&"core:paralysis") and first.statuses.get(&"core:paralysis_resistance", 0) == 1, "Paralysis that broke off the turn wears off at the end of that phase")
	engine.execute(EndTurnCommand.new(enemy.unit_id))
	suite.expect(engine.can_command(first.unit_id) and not first.statuses.has(&"core:paralysis") and not first.statuses.has(&"core:paralysis_resistance"), "The resistance still blocks the paralysis of the unit's own hex at the phase start, then wears off")
