extends RefCounted
## Side phases: the player faction acts with its units in any order, then the enemy faction.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	_run_order(suite, fixture)
	_run_choice_and_lock(suite, fixture)
	_run_phase_effects(suite, fixture)
	_run_end_phase(suite, fixture)
	_run_summon(suite, fixture)


## Placement order [p1, e1, e2, p2]: the phase keeps both player units together.
func _battle(fixture: Fixtures) -> Dictionary:
	var cells: Array[Vector2i] = []
	for q in range(7):
		cells.append(Vector2i(q, 0))
	var p1 := fixture.unit(&"p1", BattleFaction.Value.PLAYER, Vector2i(0, 0))
	var e1 := fixture.unit(&"e1", BattleFaction.Value.ENEMY, Vector2i(6, 0))
	var e2 := fixture.unit(&"e2", BattleFaction.Value.ENEMY, Vector2i(5, 0))
	var p2 := fixture.unit(&"p2", BattleFaction.Value.PLAYER, Vector2i(1, 0))
	return {"state": fixture.state(cells, [p1, e1, e2, p2]), "p1": p1, "e1": e1, "e2": e2, "p2": p2}


func _run_order(suite: Node, fixture: Fixtures) -> void:
	var battle := _battle(fixture)
	var engine := BattleEngine.new(battle.state)
	suite.expect(engine.get_active_faction() == BattleFaction.Value.PLAYER and engine.get_active_unit_id() == &"p1", "The battle opens with the player phase")
	suite.expect(engine.get_ready_unit_ids() == [&"p1", &"p2"], "Every player unit is ready in the player phase")
	engine.execute(EndTurnCommand.new(&"p1"))
	suite.expect(engine.get_active_unit_id() == &"p2", "The next player unit acts before any enemy, whatever the placement order")
	var handoff := engine.execute(EndTurnCommand.new(&"p2"))
	suite.expect(engine.get_active_faction() == BattleFaction.Value.ENEMY and engine.get_active_unit_id() == &"e1" and engine.get_round_number() == 1, "The enemy phase follows in the same round")
	suite.expect(_index_of_phase(handoff.events, BattleFaction.Value.ENEMY) >= 0, "The handoff announces the enemy phase")
	engine.execute(EndTurnCommand.new(&"e1"))
	engine.execute(EndTurnCommand.new(&"e2"))
	suite.expect(engine.get_active_faction() == BattleFaction.Value.PLAYER and engine.get_round_number() == 2 and engine.get_active_unit_id() == &"p1", "The next round opens with the player phase again")


func _run_choice_and_lock(suite: Node, fixture: Fixtures) -> void:
	var battle := _battle(fixture)
	var engine := BattleEngine.new(battle.state)
	suite.expect(engine.can_command(&"p2") and not engine.can_command(&"e1"), "Any ready unit of the acting faction may start, an enemy may not")
	suite.expect(engine.execute(MoveCommand.new(&"p2", Vector2i(2, 0))).accepted and engine.get_current_unit_id() == &"p2", "Moving starts that unit's turn")
	suite.expect(not engine.execute(MoveCommand.new(&"p1", Vector2i(1, 0))).accepted and not engine.execute(EndTurnCommand.new(&"p1")).accepted, "Another unit cannot act while one has started")
	suite.expect(engine.get_movement_search(&"p1").get_reachable_cells().is_empty() and engine.get_attackable_targets(&"p1").is_empty(), "Queries offer nothing to a unit that has to wait")
	suite.expect(engine.execute(EndTurnCommand.new(&"p2")).accepted and engine.get_current_unit_id().is_empty() and engine.get_active_unit_id() == &"p1", "Ending the started unit's turn frees the choice")
	suite.expect(not engine.can_command(&"p2"), "A unit acts once per phase")
	suite.expect(engine.execute(MoveCommand.new(&"p1", Vector2i(1, 0))).accepted, "The remaining unit acts afterwards")


func _run_phase_effects(suite: Node, fixture: Fixtures) -> void:
	# Start-of-turn exposure reaches every enemy at the start of its phase, before any acts.
	var battle := _battle(fixture)
	var state: BattleState = battle.state
	state.hex_grid.set_hex_state(Vector2i(6, 0), &"core:fire")
	state.hex_grid.set_hex_state(Vector2i(5, 0), &"core:fire")
	var engine := BattleEngine.new(state)
	engine.execute(EndTurnCommand.new(&"p1"))
	var handoff := engine.execute(EndTurnCommand.new(&"p2"))
	var phase_index := _index_of_phase(handoff.events, BattleFaction.Value.ENEMY)
	var exposed: Array[StringName] = []
	for index in range(phase_index + 1, handoff.events.size()):
		var event := handoff.events[index]
		if event is UnitDamagedEvent and event.source_hex_state_id == &"core:fire":
			exposed.append(event.target_id)
	suite.expect(phase_index >= 0 and exposed == [&"e1", &"e2"], "Both enemies take terrain exposure at the start of their phase")

	# End-of-turn effects follow the unit's own action; others wait for the phase end.
	battle = _battle(fixture)
	engine = BattleEngine.new(battle.state)
	battle.p1.statuses[&"core:burning"] = 2
	battle.p2.statuses[&"core:burning"] = 2
	var first := engine.execute(EndTurnCommand.new(&"p1"))
	suite.expect(_ticks(first.events) == [&"p1"] and battle.p2.health.current == 100, "Only the unit that ended its turn burns right away")
	suite.expect(_ticks_before_turn_end(first.events, &"p1"), "The burn precedes that unit's turn end")


func _run_end_phase(suite: Node, fixture: Fixtures) -> void:
	var battle := _battle(fixture)
	var engine := BattleEngine.new(battle.state)
	battle.p2.statuses[&"core:burning"] = 2
	suite.expect(not engine.execute(EndPhaseCommand.new(BattleFaction.Value.ENEMY)).accepted, "Only the acting faction can end its phase")
	var ended := engine.execute(EndPhaseCommand.new(BattleFaction.Value.PLAYER))
	suite.expect(ended.accepted and engine.get_active_faction() == BattleFaction.Value.ENEMY, "Ending the phase passes the turn")
	suite.expect(_ticks(ended.events) == [&"p2"] and _ticks_before_turn_end(ended.events, &"p2"), "Units that did not act get their end-of-turn effects with the phase end")
	var phase_index := _index_of_phase(ended.events, BattleFaction.Value.ENEMY)
	var turn_ends := 0
	for index in range(phase_index):
		if ended.events[index] is TurnEndedEvent:
			turn_ends += 1
	suite.expect(turn_ends == 2, "Every remaining player unit ends its turn before the enemy phase")

	battle = _battle(fixture)
	battle.p2.statuses[&"core:paralysis"] = 1
	engine = BattleEngine.new(battle.state)
	suite.expect(engine.get_ready_unit_ids() == [&"p1"], "A paralyzed unit is not ready in its phase")
	var skipped := engine.execute(EndTurnCommand.new(&"p1"))
	var marked := false
	for event: BattleEvent in skipped.events:
		marked = marked or (event is TurnEndedEvent and event.unit_id == &"p2" and event.was_skipped)
	suite.expect(marked and not battle.p2.statuses.has(&"core:paralysis") and engine.get_active_faction() == BattleFaction.Value.ENEMY, "The paralyzed unit is skipped at the phase end and paralysis decays")


func _run_summon(suite: Node, fixture: Fixtures) -> void:
	var battle := _battle(fixture)
	var turret := load("res://features/abilities/definitions/electric_turret.tres") as AbilityDefinition
	battle.p1.abilities[turret.id] = turret
	battle.p1.ability_cooldowns[turret.id] = 0
	var engine := BattleEngine.new(battle.state)
	var summon := engine.execute(UseAbilityCommand.at_hex(&"p1", Vector2i(3, 0), turret.id))
	var summoned := StringName()
	for event: BattleEvent in summon.events:
		if event is UnitSummonedEvent:
			summoned = event.unit.unit_id
	suite.expect(summon.accepted and not summoned.is_empty(), "The turret is summoned")
	suite.expect(not engine.can_command(summoned) and engine.get_ready_unit_ids() == [&"p2"], "A summoned unit waits for its side's next phase")
	var handoff := engine.execute(EndTurnCommand.new(&"p2"))
	var summon_ended := false
	for event: BattleEvent in handoff.events:
		summon_ended = summon_ended or (event is TurnEndedEvent and event.unit_id == summoned)
	suite.expect(summon_ended, "The summoned unit resolves its end-of-turn effects with the phase end")
	engine.execute(EndPhaseCommand.new(BattleFaction.Value.ENEMY))
	suite.expect(engine.get_active_faction() == BattleFaction.Value.PLAYER and engine.can_command(summoned), "The summoned unit acts in the next player phase")


func _index_of_phase(events: Array[BattleEvent], faction: BattleFaction.Value) -> int:
	for index in range(events.size()):
		if events[index] is PhaseStartedEvent and events[index].faction == faction:
			return index
	return -1


## Targets of burning ticks, in event order.
func _ticks(events: Array[BattleEvent]) -> Array[StringName]:
	var targets: Array[StringName] = []
	for event: BattleEvent in events:
		if event is UnitDamagedEvent and event.source_status_id == &"core:burning":
			targets.append(event.target_id)
	return targets


func _ticks_before_turn_end(events: Array[BattleEvent], unit_id: StringName) -> bool:
	var ticked := false
	for event: BattleEvent in events:
		if event is UnitDamagedEvent and event.source_status_id == &"core:burning" and event.target_id == unit_id:
			ticked = true
		if event is TurnEndedEvent and event.unit_id == unit_id:
			return ticked
	return false
