extends RefCounted
## The shield prevents damage of any type once, lasts until its side's next phase and comes
## from defending: the end-turn command.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")
const SHIELD := UnitStatusCatalog.SHIELD


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	_run_damage_rules(suite, fixture)
	_run_status_lifetime(suite, fixture)
	_run_defend(suite, fixture)
	_run_phase_lifetime(suite, fixture)


func _run_damage_rules(suite: Node, fixture: Fixtures) -> void:
	var events: Array[BattleEvent] = []
	var unit := fixture.unit(&"unit", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	unit.statuses[SHIELD] = 2
	UnitStatusService.damage(unit, DamageRequest.new(5), events)
	var hit := events.back() as UnitDamagedEvent
	suite.expect(unit.health.current == 97 and not unit.statuses.has(SHIELD), "The shield prevents damage up to its levels and breaks")
	suite.expect(hit.calculated_damage == 3 and hit.damage_modifiers == [{"source_id": SHIELD, "amount": -2}], "The damage trace names the prevented amount")
	var units: Dictionary[StringName, UnitDefinition] = {}
	suite.expect("5 (базовая атака) − 2 (Щит) = 3." in BattleLogFormatter.describe(hit, units, null), "The battle log shows the shield in the damage formula")

	unit.statuses[SHIELD] = 3
	events.clear()
	UnitStatusService.damage(unit, DamageRequest.new(1), events)
	suite.expect(unit.health.current == 97 and not unit.statuses.has(SHIELD), "Preventing any damage removes every shield level")
	var removed := false
	for event: BattleEvent in events:
		removed = removed or (event is UnitStatusChangedEvent and event.previous_statuses.has(SHIELD) and not event.statuses.has(SHIELD))
	suite.expect(removed, "Breaking the shield publishes a status change")

	for type: StringName in DamageType.ALL:
		var target := fixture.unit(&"target", BattleFaction.Value.ENEMY, Vector2i.ZERO)
		target.statuses[SHIELD] = 1
		UnitStatusService.damage(target, DamageRequest.new(3, type), events)
		suite.expect(target.health.current == 98 and not target.statuses.has(SHIELD), "The shield prevents %s damage" % type)

	# The shield is the last layer: damage other statuses already stopped leaves it whole.
	var armored := fixture.unit(&"armored", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	armored.statuses.assign({UnitStatusCatalog.ARMOR: 2, SHIELD: 1})
	UnitStatusService.damage(armored, DamageRequest.new(2), events)
	suite.expect(armored.health.current == 100 and armored.statuses.get(SHIELD, 0) == 1, "Damage the armor blocks does not break the shield")
	events.clear()
	UnitStatusService.damage(armored, DamageRequest.new(4), events)
	hit = events.back() as UnitDamagedEvent
	suite.expect(armored.health.current == 99 and not armored.statuses.has(SHIELD), "Armor reduces the hit first, the shield prevents the rest")
	suite.expect(hit.damage_modifiers == [{"source_id": UnitStatusCatalog.ARMOR, "amount": -2}, {"source_id": SHIELD, "amount": -1}], "The trace lists armor before the shield")
	var wet := fixture.unit(&"wet", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	wet.statuses.assign({UnitStatusCatalog.WET: 3, SHIELD: 1})
	UnitStatusService.damage(wet, DamageRequest.new(2, &"fire"), events)
	suite.expect(wet.health.current == 100 and wet.statuses.get(SHIELD, 0) == 1 and wet.statuses.get(UnitStatusCatalog.WET, 0) == 1, "Fire the wet status absorbs does not break the shield")
	UnitStatusService.damage(wet, DamageRequest.new(2, &"electric"), events)
	suite.expect(wet.health.current == 98 and not wet.statuses.has(SHIELD), "The shield prevents electric damage after the wet bonus")
	var spared := fixture.unit(&"spared", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	spared.statuses[SHIELD] = 1
	UnitStatusService.damage(spared, DamageRequest.new(0), events)
	suite.expect(spared.statuses.get(SHIELD, 0) == 1, "Zero damage leaves the shield")


func _run_status_lifetime(suite: Node, fixture: Fixtures) -> void:
	var events: Array[BattleEvent] = []
	var unit := fixture.unit(&"unit", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	unit.statuses.assign({SHIELD: 2, UnitStatusCatalog.WET: 2})
	UnitStatusService.start_phase(unit, events)
	UnitStatusService.end_phase(unit, false, events)
	suite.expect(unit.statuses.get(SHIELD, 0) == 2 and unit.statuses.get(UnitStatusCatalog.WET, 0) == 1, "The shield is a reserve: the level decay of the phase boundaries skips it")
	unit.statuses.assign({SHIELD: 3, UnitStatusCatalog.ARMOR: 1})
	events.clear()
	UnitStatusService.expire_reserves(unit, events)
	suite.expect(unit.statuses.size() == 1 and unit.statuses.get(UnitStatusCatalog.ARMOR, 0) == 1 and events.size() == 1 and events[0] is UnitStatusChangedEvent, "The phase start removes every shield level and nothing else")
	events.clear()
	UnitStatusService.expire_reserves(unit, events)
	suite.expect(events.is_empty(), "A phase start without a shield publishes nothing")
	suite.expect(UnitStatusCatalog.has_status(SHIELD) and UnitStatusCatalog.display_name(SHIELD) == "Щит", "The shield is a named status")
	suite.expect(ResourceLoader.exists("res://features/battle/ui/icons/status/shield.svg"), "The shield has a status icon")


func _run_defend(suite: Node, fixture: Fixtures) -> void:
	var cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0)]
	var player := fixture.unit(&"player", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var enemy := fixture.unit(&"enemy", BattleFaction.Value.ENEMY, Vector2i(1, 0))
	var engine := BattleEngine.new(fixture.state(cells, [player, enemy]))
	player.statuses[UnitStatusCatalog.ELECTRIFIED] = 2
	var forecast := ActionPreview.build(engine.fork_for_prediction(), engine, EndTurnCommand.new(player.unit_id))
	var change := forecast.units.get(player.unit_id) as ActionPreview.UnitChange
	suite.expect(change != null and change.statuses_after.get(SHIELD, 0) == BattleEngine.DEFEND_SHIELD_LEVELS and change.health_after == 100, "The defend forecast shows the shield; periodic damage is not part of the turn")
	var result := engine.execute(EndTurnCommand.new(player.unit_id))
	var timeline: Array[String] = []
	for event: BattleEvent in result.events:
		if event is UnitDamagedEvent and event.target_id == player.unit_id:
			timeline.append("tick")
		elif event is UnitStatusChangedEvent and event.unit_id == player.unit_id and event.statuses.has(SHIELD) and not event.previous_statuses.has(SHIELD):
			timeline.append("shield")
		elif event is TurnEndedEvent and event.unit_id == player.unit_id:
			timeline.append("end")
	suite.expect(timeline == ["shield", "end"], "Defending raises the shield before the turn ends; the turn end deals no periodic damage")
	suite.expect(player.health.current == 100 and player.statuses.get(SHIELD, 0) == BattleEngine.DEFEND_SHIELD_LEVELS and player.statuses.get(UnitStatusCatalog.ELECTRIFIED, 0) == 2, "The electrified unit keeps its levels and health until its next phase")
	suite.expect(engine.get_active_faction() == BattleFaction.Value.ENEMY and player.statuses.has(SHIELD), "The shield survives the opponent's phase start")
	var attack := engine.execute(AttackCommand.new(enemy.unit_id, player.unit_id))
	var hit: UnitDamagedEvent
	for event: BattleEvent in attack.events:
		if event is UnitDamagedEvent and event.attacker_id == enemy.unit_id and event.target_id == player.unit_id:
			hit = event
	suite.expect(hit != null and hit.damage == 1 and hit.damage_modifiers.back() == {"source_id": SHIELD, "amount": -1} and not player.statuses.has(SHIELD), "The shield prevents one damage of the opponent's attack and breaks")
	suite.expect(not enemy.statuses.has(SHIELD), "Attacking does not give a shield")

	player = fixture.unit(&"player", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	enemy = fixture.unit(&"enemy", BattleFaction.Value.ENEMY, Vector2i(1, 0))
	engine = BattleEngine.new(fixture.state(cells, [player, enemy]))
	engine.execute(EndPhaseCommand.new(BattleFaction.Value.PLAYER))
	suite.expect(engine.get_active_faction() == BattleFaction.Value.ENEMY and not player.statuses.has(SHIELD), "Units passed at the phase end do not defend")


func _run_phase_lifetime(suite: Node, fixture: Fixtures) -> void:
	var cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i(3, 0)]
	var player := fixture.unit(&"player", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var enemy := fixture.unit(&"enemy", BattleFaction.Value.ENEMY, Vector2i(3, 0))
	var engine := BattleEngine.new(fixture.state(cells, [player, enemy]))
	engine.execute(EndTurnCommand.new(player.unit_id))
	var result := engine.execute(EndTurnCommand.new(enemy.unit_id))
	var phase_index := -1
	var removal_index := -1
	for index in range(result.events.size()):
		var event := result.events[index]
		if event is PhaseStartedEvent and event.faction == BattleFaction.Value.PLAYER:
			phase_index = index
		elif event is UnitStatusChangedEvent and event.unit_id == player.unit_id and event.previous_statuses.has(SHIELD) and not event.statuses.has(SHIELD):
			removal_index = index
	suite.expect(engine.get_active_faction() == BattleFaction.Value.PLAYER and not player.statuses.has(SHIELD), "The shield falls at the start of its side's next phase")
	suite.expect(phase_index >= 0 and removal_index > phase_index, "The shield falls after the phase starts")
	suite.expect(enemy.statuses.get(SHIELD, 0) == BattleEngine.DEFEND_SHIELD_LEVELS, "The opponent's shield lasts until its own phase")
	engine.execute(EndTurnCommand.new(player.unit_id))
	suite.expect(not enemy.statuses.has(SHIELD) and player.statuses.get(SHIELD, 0) == BattleEngine.DEFEND_SHIELD_LEVELS, "Each side's shields fall at its own phase start")
	# The side's own periodic damage comes after its shields fell: it never spends one.
	player.statuses[UnitStatusCatalog.BURNING] = 2
	result = engine.execute(EndTurnCommand.new(enemy.unit_id))
	var order: Array[String] = []
	for event: BattleEvent in result.events:
		if event is UnitStatusChangedEvent and event.unit_id == player.unit_id and event.previous_statuses.has(SHIELD) and not event.statuses.has(SHIELD):
			order.append("shield")
		elif event is UnitDamagedEvent and event.target_id == player.unit_id and event.source_status_id == UnitStatusCatalog.BURNING:
			order.append("burning")
	suite.expect(order == ["shield", "burning"] and player.health.current == 99 and player.statuses.get(UnitStatusCatalog.BURNING, 0) == 1, "The shield falls before the side's periodic damage, which then lands in full")

	# The first unit's start effect, a returning spear, meets no shield of a later ally.
	var line: Array[Vector2i] = []
	for q in range(0, 6):
		line.append(Vector2i(q, 0))
	var thrower := fixture.unit(&"a_thrower", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var ally := fixture.unit(&"b_ally", BattleFaction.Value.PLAYER, Vector2i(1, 0))
	var foe := fixture.unit(&"foe", BattleFaction.Value.ENEMY, Vector2i(5, 0))
	var throw := load("res://features/abilities/definitions/spear_throw.tres") as AbilityDefinition
	thrower.abilities[throw.id] = throw
	engine = BattleEngine.new(fixture.state(line, [thrower, ally, foe]))
	suite.expect(engine.execute(UseAbilityCommand.at_hex(thrower.unit_id, Vector2i(4, 0), throw.id)).accepted and ally.health.current == 97, "The thrown spear hits the ally on its path")
	engine.execute(EndTurnCommand.new(ally.unit_id))
	suite.expect(ally.statuses.get(SHIELD, 0) == BattleEngine.DEFEND_SHIELD_LEVELS, "The ally defends after the throw")
	engine.execute(EndPhaseCommand.new(BattleFaction.Value.ENEMY))
	suite.expect(engine.get_active_faction() == BattleFaction.Value.PLAYER and thrower.pending_spear_return.is_empty() and ally.health.current == 94, "Every shield of the side falls before the first unit's start effects")
