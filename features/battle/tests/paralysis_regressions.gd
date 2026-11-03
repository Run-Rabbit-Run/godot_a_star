extends RefCounted
## Paralysis never stacks and leaves resistance behind, so no unit stays paralyzed for good.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	_run_status_rules(suite, fixture)
	_run_phase_cycle(suite, fixture)
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
	UnitStatusService.end_turn(unit, events)
	suite.expect(not unit.statuses.has(&"core:paralysis") and unit.statuses.get(&"core:paralysis_resistance", 0) == 1, "Worn-off paralysis leaves one resistance level that survives its own turn end")
	var shown := false
	for event: BattleEvent in events:
		shown = shown or (event is UnitStatusChangedEvent and event.statuses.has(&"core:paralysis_resistance"))
	suite.expect(shown, "The status change event shows the new resistance")
	UnitStatusService.end_turn(unit, events)
	suite.expect(unit.statuses.is_empty(), "Resistance loses its level at the next own turn end")


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
