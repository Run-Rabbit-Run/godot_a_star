extends RefCounted
## Unit statuses, their periodic damage, the order of turn effects and damage in the battle log.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")


func run_statuses(suite: Node) -> void:
	_check_statuses(suite)
	_check_fixed_status_damage(suite)


func _check_statuses(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var unit := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var events: Array[BattleEvent] = []
	UnitStatusService.apply(unit, &"core:wet", 3, events)
	UnitStatusService.damage(unit, DamageRequest.new(1, &"electric"), events)
	suite.expect(unit.health.current == 98 and unit.statuses.get(&"core:wet", 0) == 3, "Wet amplifies electric damage without decay")
	UnitStatusService.damage(unit, DamageRequest.new(2, &"fire"), events)
	suite.expect(unit.health.current == 98 and unit.statuses.get(&"core:wet", 0) == 1, "Wet absorbs fire one-to-one")
	UnitStatusService.apply(unit, &"core:plasma", 2, events)
	suite.expect(not unit.statuses.has(&"core:wet"), "Plasma removes wet")
	UnitStatusService.damage(unit, DamageRequest.new(8, &"water"), events)
	suite.expect(unit.health.current == 98, "Plasma blocks water damage")
	unit.status_immunities.append(&"core:burning")
	UnitStatusService.apply(unit, &"core:burning", 2, events)
	suite.expect(not unit.statuses.has(&"core:burning"), "Burning immunity blocks only status")
	UnitStatusService.damage(unit, DamageRequest.new(2, &"fire"), events)
	suite.expect(unit.health.current == 96, "Status immunity is not damage immunity")
	UnitStatusService.apply(unit, &"core:armor", 8, events)
	UnitStatusService.apply(unit, &"core:acid", 5, events)
	suite.expect(not unit.statuses.has(&"core:armor") and not unit.statuses.has(&"core:acid"), "Acid threshold removes armor and acid")
	events.clear()
	UnitStatusService.end_turn(unit, events)
	var periodic_found := false
	for event: BattleEvent in events:
		if event is UnitDamagedEvent:
			periodic_found = periodic_found or (event.source_status_id == &"core:plasma" and event.source_hex_state_id.is_empty())
	suite.expect(periodic_found, "Periodic damage identifies status rather than terrain")
	var snapshot := UnitSnapshot.new(unit)
	snapshot.statuses.clear()
	suite.expect(not unit.statuses.is_empty(), "Status snapshots are detached")


func _check_fixed_status_damage(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	for spec: Dictionary in [
		{"id": &"core:burning", "amount": 1, "type": &"fire"},
		{"id": &"core:electrified", "amount": 1, "type": &"electric"},
		{"id": &"core:plasma", "amount": 2, "type": &"fire"},
	]:
		for levels: int in [0, 1, 3, 7]:
			var unit := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO)
			if levels > 0:
				unit.statuses[spec.id] = levels
			var events: Array[BattleEvent] = []
			UnitStatusService.end_turn(unit, events)
			var expected_damage: int = spec.amount if levels > 0 else 0
			suite.expect(unit.health.current == 100 - expected_damage and unit.statuses.get(spec.id, 0) == maxi(0, levels - 1), "Fixed status damage and one-level decay: %s/%d" % [spec.id, levels])
			var hits := 0
			for event: BattleEvent in events:
				if event is UnitDamagedEvent:
					hits += 1
					suite.expect(event.base_damage == expected_damage and event.damage_type == spec.type and event.source_status_id == spec.id and event.source_hex_state_id.is_empty(), "Periodic event preserves fixed base, type and source: %s/%d" % [spec.id, levels])
			suite.expect(hits == (1 if levels > 0 else 0), "Absent status does not damage: %s/%d" % [spec.id, levels])
	for levels: int in [0, 1, 3, 7]:
		var unit := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO)
		if levels > 0:
			unit.statuses[&"core:wet"] = levels
		var events: Array[BattleEvent] = []
		UnitStatusService.damage(unit, DamageRequest.new(3, &"electric"), events)
		suite.expect(unit.health.current == (96 if levels > 0 else 97) and unit.statuses.get(&"core:wet", 0) == levels, "Wet adds one electric damage without consumption: %d" % levels)
	var wet := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	wet.statuses[&"core:wet"] = 3
	var no_damage: Array[BattleEvent] = []
	UnitStatusService.damage(wet, DamageRequest.new(0, &"electric"), no_damage)
	suite.expect(wet.health.current == 100 and no_damage.is_empty(), "Wet amplification cannot create damage from zero")
	var protected := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	protected.statuses.assign({&"core:plasma": 3, &"core:wet": 1})
	var events: Array[BattleEvent] = []
	UnitStatusService.end_turn(protected, events)
	suite.expect(protected.health.current == 99 and not protected.statuses.has(&"core:wet"), "Plasma periodic fire damage uses fire absorption")
	var oily := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	oily.statuses[&"core:sticky_oil"] = 3
	UnitStatusService.apply(oily, &"core:burning", 2, events)
	suite.expect(oily.health.current == 95 and not oily.statuses.has(&"core:sticky_oil"), "Oil explosion retains sum-of-levels rule")


func run_damage_log(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var attacker := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var target := fixture.unit(&"e", BattleFaction.Value.ENEMY, Vector2i(2, 0))
	attacker.basic_attack_damage = 6
	attacker.basic_attack_range = 3
	target.statuses[&"core:armor"] = 1
	var state := fixture.state([attacker.hex, target.hex], [attacker, target])
	state.hex_grid.set_hex_state(target.hex, &"core:steam")
	var engine := BattleEngine.new(state)
	var result := engine.execute(AttackCommand.new(attacker.unit_id, target.unit_id))
	var hit: UnitDamagedEvent
	for event: BattleEvent in result.events:
		if event is UnitDamagedEvent and event.attacker_id == attacker.unit_id:
			hit = event
	suite.expect(result.accepted and hit != null, "Ranged attack publishes a damage calculation")
	if hit == null:
		return
	suite.expect(hit.base_damage == 6 and hit.calculated_damage == 2 and hit.damage == 2, "Damage calculation preserves 6 minus steam 3 minus armor 1 equals 2")
	suite.expect(hit.damage_modifiers == [{"source_id": &"core:steam", "amount": -3}, {"source_id": &"core:armor", "amount": -1}], "Damage event identifies ordered actual reductions")
	var units: Dictionary[StringName, UnitDefinition] = {}
	var text := BattleLogFormatter.describe(hit, units, null)
	suite.expect("физический" in text and "6 (базовая атака) − 3 (гекс: Пар) − 1 (Броня) = 2." in text, "Combat log displays damage type and requested formula")
	target.statuses.clear()
	state.hex_grid.set_hex_state(target.hex, &"core:water")
	suite.expect(BattleLogFormatter.describe(hit, units, null) == text, "Later status and terrain changes cannot alter historical formula")
	var ability := fixture.ability(&"test:ranged", AbilityDefinition.TargetMode.ENEMY)
	attacker.abilities[ability.id] = ability
	state.hex_grid.set_hex_state(target.hex, &"core:steam")
	var context := BattleEffectContext.new(state, ability.id)
	var events := context.apply_damage_events(attacker.unit_id, target.unit_id, 8, &"acid")
	hit = events[0] as UnitDamagedEvent
	suite.expect(hit != null and hit.damage == 5 and hit.damage_modifiers == [{"source_id": &"core:steam", "amount": -3}], "Ability damage records steam protection")
	suite.expect("кислотный" in BattleLogFormatter.describe(hit, units, null) and "умение:" in BattleLogFormatter.describe(hit, units, null), "Ability log names damage type and origin")
	# Each interaction is traced before the status is consumed or removed.
	for scenario: Dictionary in [
		{"type": &"fire", "status": &"core:wet", "levels": 2, "delta": -2, "final": 3},
		{"type": &"water", "status": &"core:burning", "levels": 2, "delta": -2, "final": 3},
		{"type": &"water", "status": &"core:plasma", "levels": 1, "delta": -5, "final": 0},
		{"type": &"electric", "status": &"core:wet", "levels": 2, "delta": 1, "final": 6},
		{"type": &"physical", "status": &"core:armor", "levels": 9, "delta": -5, "final": 0},
	]:
		var unit := fixture.unit(&"victim", BattleFaction.Value.ENEMY, Vector2i.ZERO)
		unit.statuses[scenario.status] = scenario.levels
		events.clear()
		UnitStatusService.damage(unit, DamageRequest.new(5, scenario.type), events)
		hit = events.back() as UnitDamagedEvent
		suite.expect(hit != null and hit.calculated_damage == scenario.final and hit.damage_modifiers == [{"source_id": scenario.status, "amount": scenario.delta}], "Trace matches actual status interaction: %s/%s" % [scenario.type, scenario.status])
		var sum := hit.base_damage
		for modifier: Dictionary in hit.damage_modifiers:
			sum += int(modifier.amount)
		suite.expect(sum == hit.calculated_damage and unit.health.current == 100 - hit.damage, "Trace arithmetic reconciles with actual health loss")
	var fragile := fixture.unit(&"fragile", BattleFaction.Value.ENEMY, Vector2i.ZERO, 2)
	events.clear()
	UnitStatusService.damage(fragile, DamageRequest.new(6, &"plasma").from_hex_state(&"core:plasma"), events)
	hit = events.back() as UnitDamagedEvent
	suite.expect(hit.base_damage == 6 and hit.calculated_damage == 6 and hit.damage == 2, "Overkill preserves calculated damage separately from health loss")
	text = BattleLogFormatter.describe(hit, units, null)
	suite.expect("плазменный" in text and "гекс: Плазма" in text and "Снято 2 ОЗ" in text, "Log distinguishes overkill from damage absorption")
	events.clear()
	UnitStatusService.damage(target, DamageRequest.new(2).from_unit(attacker.unit_id).with_cover(3, &"core:steam"), events)
	hit = events.back() as UnitDamagedEvent
	suite.expect(hit.damage == 0 and hit.damage_modifiers == [{"source_id": &"core:steam", "amount": -2}], "Protection records absorbed amount rather than unused capacity")


func run_turn_effect_order(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	for action: String in ["end", "attack", "ability"]:
		var p := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO)
		var e := fixture.unit(&"e", BattleFaction.Value.ENEMY, Vector2i(1, 0))
		var state := fixture.state([p.hex, e.hex], [p, e])
		var engine := BattleEngine.new(state)
		p.statuses[&"core:electrified"] = 2
		var command = EndTurnCommand.new(p.unit_id)
		if action == "attack":
			command = AttackCommand.new(p.unit_id, e.unit_id)
		elif action == "ability":
			var ability := fixture.ability(&"test:turn_order", AbilityDefinition.TargetMode.ENEMY)
			p.abilities[ability.id] = ability
			command = UseAbilityCommand.new(p.unit_id, e.unit_id, ability.id)
		var result := engine.execute(command)
		var tick_index := -1
		var boundary_index := -1
		var ticks := 0
		for index in range(result.events.size()):
			var event := result.events[index]
			if event is UnitDamagedEvent and event.source_status_id == &"core:electrified":
				tick_index = index
				ticks += 1
			if event is TurnEndedEvent and event.unit_id == p.unit_id:
				boundary_index = index
		suite.expect(result.accepted and ticks == 1 and tick_index >= 0 and tick_index < boundary_index, "Periodic tick precedes handoff exactly once: %s" % action)
		suite.expect(p.health.current == 99 and p.statuses[&"core:electrified"] == 1, "End tick uses fixed damage and one-level decay: %s" % action)
		p.health.current = 100
		var start_result := engine.execute(EndTurnCommand.new(e.unit_id))
		var premature_tick := false
		for event: BattleEvent in start_result.events:
			if event is UnitDamagedEvent and event.target_id == p.unit_id and not event.source_status_id.is_empty():
				premature_tick = true
		suite.expect(start_result.accepted and engine.get_round_number() == 2 and p.health.current == 100 and not premature_tick, "Starting the next own turn does not apply periodic damage: %s" % action)
	# A skipped unit has its own boundary, after its own tick, before the next round.
	var p := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var e := fixture.unit(&"e", BattleFaction.Value.ENEMY, Vector2i(1, 0))
	var state := fixture.state([p.hex, e.hex], [p, e])
	var engine := BattleEngine.new(state)
	e.statuses.assign({&"core:electrified": 2, &"core:paralysis": 1})
	var result := engine.execute(EndTurnCommand.new(p.unit_id))
	var timeline: Array[String] = []
	var skipped = null
	for event: BattleEvent in result.events:
		if event is TurnEndedEvent:
			timeline.append("end:%s:%d" % [event.unit_id, event.round_number])
			if event.was_skipped:
				skipped = event
		elif event is UnitDamagedEvent:
			timeline.append("tick:%s" % event.target_id)
	suite.expect(timeline == ["end:p:1", "tick:e", "end:e:1"], "A paralyzed unit ticks at the end of its own phase, before its turn end")
	suite.expect(skipped != null and skipped.unit_id == e.unit_id and skipped.round_number == 1, "The skipped turn names the paralyzed unit and its round")
	suite.expect(e.health.current == 99 and not e.statuses.has(&"core:paralysis") and engine.get_active_unit_id() == p.unit_id, "Paralysis skip retains tick and decay once")
	var units: Dictionary[StringName, UnitDefinition] = {}
	suite.expect("пропущен из-за паралича" in BattleLogFormatter.describe(skipped, units, null), "Log explicitly explains skipped end-of-turn effects")
	# Direct terrain damage still belongs to the new turn, unlike periodic status damage.
	e.statuses.clear()
	state.hex_grid.set_hex_state(e.hex, &"core:electricity")
	result = engine.execute(EndTurnCommand.new(p.unit_id))
	timeline.clear()
	for event: BattleEvent in result.events:
		if event is TurnEndedEvent:
			timeline.append("handoff")
		elif event is UnitDamagedEvent:
			timeline.append("terrain" if event.source_hex_state_id == &"core:electricity" and event.source_status_id.is_empty() else "periodic")
	suite.expect(timeline == ["handoff", "terrain"], "Beginning terrain exposure follows handoff and does not tick electrified status")
	# The first participant can already be paralyzed when the battle starts.
	p.statuses.assign({&"core:electrified": 2, &"core:paralysis": 1})
	e.statuses.clear()
	state = fixture.state([p.hex, e.hex], [p, e])
	engine = BattleEngine.new(state)
	timeline.clear()
	skipped = null
	for event: BattleEvent in engine.get_initial_resolution().events:
		if event is UnitDamagedEvent:
			timeline.append("tick")
		elif event is TurnEndedEvent:
			timeline.append("handoff")
			skipped = event
	suite.expect(timeline == ["tick", "handoff"] and engine.get_active_unit_id() == e.unit_id, "Initial paralysis resolves end tick before the handoff")
	suite.expect(skipped != null and skipped.was_skipped, "Initial paralysis is explicitly marked as a skipped turn")
	# Lethal periodic damage must also precede the terminal turn boundary.
	e.health.current = 1
	e.statuses[&"core:electrified"] = 2
	result = engine.execute(EndTurnCommand.new(e.unit_id))
	timeline.clear()
	for event: BattleEvent in result.events:
		if event is UnitDamagedEvent:
			timeline.append("tick")
		elif event is TurnEndedEvent:
			timeline.append("handoff")
	suite.expect(timeline == ["tick", "handoff"] and result.battle_result != null, "Lethal end tick precedes battle-ending boundary")
