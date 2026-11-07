extends RefCounted
## «Плечом к плечу»: a unit that ends its own turn — an action or the defence — next to a living
## ally raises one level of shield; the shield falls at the start of its side's next phase.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")
const SHOULDER := &"core:shoulder_to_shoulder"
const SHIELD := UnitStatusCatalog.SHIELD
const PLAYER := BattleFaction.Value.PLAYER
const ENEMY := BattleFaction.Value.ENEMY


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	_run_catalog(suite, fixture)
	_run_attack(suite, fixture)
	_run_defence_and_ability(suite, fixture)
	_run_no_ally(suite, fixture)
	_run_lifetime(suite, fixture)


func _run_catalog(suite: Node, fixture: Fixtures) -> void:
	var ids: Array[StringName] = [SHOULDER]
	suite.expect(PassiveAbilityCatalog.validate(ids).is_empty(), "«Плечом к плечу» is a known passive")
	var definition := UnitDefinition.new()
	definition.base_stats = UnitStatsDefinition.new()
	definition.base_stats.basic_attack_damage = 2
	definition.passive_ability_ids.assign(ids)
	var spawn := UnitSpawnData.new(&"test:unit", &"test:placement", &"test:definition", definition, &"test:side", PLAYER, BattleControlSource.Value.PLAYER, &"", null, Vector2i.ZERO)
	var unit := UnitStateFactory.create(spawn)
	suite.expect(unit != null and unit.ally_shield == 1 and unit.duplicate_state().ally_shield == 1 and UnitSnapshot.new(unit).ally_shield == 1, "The factory gives the passive's shield level to the unit and its copies")
	var text := AbilityDescription.render_passive(PassiveAbilityCatalog.DEFINITIONS[SHOULDER])
	suite.expect(text.contains("рядом с живым союзником") and text.contains("щит ×1") and not "{" in text, "The passive describes itself: %s" % text)
	var skills := fixture.skills()
	var document: Dictionary = skills.builtin_documents().get(String(SHOULDER), {})
	var reread: Dictionary = SkillLibrary.normalized(JSON.parse_string(JSON.stringify(document)))
	suite.expect(not document.is_empty() and skills.validate(reread).is_empty() and skills.is_builtin_default(reread), "The built-in passive survives a JSON round trip as its default document")
	reread.name = "Строй"
	suite.expect(int(SkillLibrary.passive_definitions({reread.id: reread})[SHOULDER].get("ally_shield", 0)) == 1, "Renaming the passive keeps its fixed effect")


## The shoulder unit at the origin, an ally at (1, 0), an enemy at (-1, 0).
func _run_attack(suite: Node, fixture: Fixtures) -> void:
	var setup := _field(fixture, Vector2i(1, 0))
	var unit: UnitState = setup.unit
	var result: BattleResolution = setup.engine.execute(AttackCommand.new(unit.unit_id, setup.enemy.unit_id))
	suite.expect(result.accepted and unit.statuses.get(SHIELD, 0) == 1, "An attack ended next to an ally raises one shield")
	var shield_index := -1
	var ended_index := -1
	for index in range(result.events.size()):
		var event := result.events[index]
		if event is UnitStatusChangedEvent and event.unit_id == unit.unit_id and event.statuses.get(SHIELD, 0) == 1:
			shield_index = index
		if event is TurnEndedEvent and event.unit_id == unit.unit_id:
			ended_index = index
	suite.expect(shield_index >= 0 and shield_index < ended_index, "The shield rises before the turn ends")


func _run_defence_and_ability(suite: Node, fixture: Fixtures) -> void:
	var setup := _field(fixture, Vector2i(1, 0))
	var unit: UnitState = setup.unit
	setup.engine.execute(EndTurnCommand.new(unit.unit_id))
	suite.expect(unit.statuses.get(SHIELD, 0) == 2, "The defence next to an ally gives its own shield and the passive's: 2")

	setup = _field(fixture, Vector2i(1, 0))
	unit = setup.unit
	var strike := fixture.ability(&"test:strike", AbilityDefinition.TargetMode.ENEMY)
	unit.abilities[strike.id] = strike
	unit.ability_cooldowns[strike.id] = 0
	var result: BattleResolution = setup.engine.execute(UseAbilityCommand.new(unit.unit_id, setup.enemy.unit_id, strike.id))
	suite.expect(result.accepted and unit.statuses.get(SHIELD, 0) == 1, "An ability ended next to an ally raises the shield too")

	# A step to an ally before the defence counts where the turn ends.
	setup = _field(fixture, Vector2i(3, 0))
	unit = setup.unit
	setup.engine.execute(MoveCommand.new(unit.unit_id, Vector2i(2, 0)))
	setup.engine.execute(EndTurnCommand.new(unit.unit_id))
	suite.expect(unit.statuses.get(SHIELD, 0) == 2, "The unit that walked up to its ally gets the shield")


func _run_no_ally(suite: Node, fixture: Fixtures) -> void:
	var setup := _field(fixture, Vector2i(2, 0))
	var unit: UnitState = setup.unit
	setup.engine.execute(AttackCommand.new(unit.unit_id, setup.enemy.unit_id))
	suite.expect(not unit.statuses.has(SHIELD), "Without an ally next to it the unit raises no shield")

	setup = _field(fixture, Vector2i(1, 0))
	unit = setup.unit
	setup.ally.health.current = 0
	setup.engine.execute(AttackCommand.new(unit.unit_id, setup.enemy.unit_id))
	suite.expect(not unit.statuses.has(SHIELD), "A fallen ally does not count")

	setup = _field(fixture, Vector2i(1, 0))
	unit = setup.unit
	unit.ally_shield = 0
	setup.engine.execute(AttackCommand.new(unit.unit_id, setup.enemy.unit_id))
	suite.expect(not unit.statuses.has(SHIELD), "A unit without the passive raises no shield after an attack")

	# The phase end is not the unit's own turn end.
	setup = _field(fixture, Vector2i(1, 0))
	unit = setup.unit
	setup.engine.execute(EndPhaseCommand.new(PLAYER))
	suite.expect(not unit.statuses.has(SHIELD), "A turn ended with the phase raises no shield")


## The shield covers the enemy phase and falls at the start of the unit's next phase.
func _run_lifetime(suite: Node, fixture: Fixtures) -> void:
	var setup := _field(fixture, Vector2i(1, 0))
	var unit: UnitState = setup.unit
	var engine: BattleEngine = setup.engine
	engine.execute(AttackCommand.new(unit.unit_id, setup.enemy.unit_id))
	engine.execute(EndTurnCommand.new(setup.ally.unit_id))
	suite.expect(engine.get_active_faction() == ENEMY and unit.statuses.get(SHIELD, 0) == 1, "The shield lasts into the enemy phase")
	var hit := engine.execute(AttackCommand.new(setup.enemy.unit_id, unit.unit_id))
	suite.expect(hit.accepted and unit.health.current == 99 and not unit.statuses.has(SHIELD), "The shield prevents a point of damage and breaks")
	setup = _field(fixture, Vector2i(1, 0))
	unit = setup.unit
	engine = setup.engine
	engine.execute(AttackCommand.new(unit.unit_id, setup.enemy.unit_id))
	engine.execute(EndTurnCommand.new(setup.ally.unit_id))
	engine.execute(EndPhaseCommand.new(ENEMY))
	suite.expect(engine.get_active_faction() == PLAYER and not unit.statuses.has(SHIELD), "An unused shield falls at the start of the unit's next phase")


## The shoulder unit at the origin with attack 2, an ally at `ally_hex`, an enemy at (-1, 0)
## with attack 2, on one row, in the player phase.
static func _field(fixture: Fixtures, ally_hex: Vector2i) -> Dictionary:
	var unit := fixture.unit(&"shoulder", PLAYER, Vector2i.ZERO)
	unit.ally_shield = 1
	var ally := fixture.unit(&"ally", PLAYER, ally_hex)
	var enemy := fixture.unit(&"enemy", ENEMY, Vector2i(-1, 0))
	var cells: Array[Vector2i] = []
	for q in range(-3, 5):
		cells.append(Vector2i(q, 0))
	var engine := BattleEngine.new(fixture.state(cells, [unit, ally, enemy]))
	return {"unit": unit, "ally": ally, "enemy": enemy, "engine": engine}
