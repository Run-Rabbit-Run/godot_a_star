extends RefCounted
## The plain turret of the core package: summoned on a free hex within 4, it has 2 HP and a
## physical attack of 2 at range 2; the summon then waits three own turns.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")

const TURRET := &"core:turret"
const TURRET_UNIT := &"core:turret_unit"


func run(suite: Node) -> void:
	var core: ContentPackage = load("res://content/packages/core/core_package.tres")
	var loaded := ContentLoader.load_packages([core])
	suite.expect(loaded.is_successful, "The core package with the turret loads: %s" % "\n".join(loaded.errors))
	if not loaded.is_successful:
		return
	var snapshot := loaded.snapshot
	var ability := snapshot.get_ability_definition(TURRET)
	var unit := snapshot.get_unit_definition(TURRET_UNIT)
	suite.expect(ability != null and unit != null, "The core package ships the turret summon and its unit")
	if ability == null or unit == null:
		return
	_check_definitions(suite, snapshot, ability, unit, core)
	_check_battle(suite, suite.fixture, ability, unit)


func _check_definitions(suite: Node, snapshot: ContentSnapshot, ability: AbilityDefinition, unit: UnitDefinition, core: ContentPackage) -> void:
	suite.expect(ability.target_mode == AbilityDefinition.TargetMode.EMPTY_HEX and ability.range == 4 and ability.area_radius == 0 and not ability.uses_attack_range, "The turret targets a free hex within 4")
	suite.expect(ability.cooldown_turns == 3 and ability.initial_cooldown_turns == 0, "The turret summon has a cooldown of 3 and none at the start")
	suite.expect(ability.effects.size() == 1 and SummonEffectHandler.unit_id(ability.effects[0]) == TURRET_UNIT, "The turret summon brings core:turret_unit")
	var stats := unit.base_stats
	suite.expect(stats.max_health == 2 and stats.basic_attack_damage == 2 and stats.basic_attack_range == 2 and stats.movement_points == 0, "The turret has 2 HP, attack 2 at range 2 and does not move")
	suite.expect(unit.passive_ability_ids.is_empty() and unit.ability_ids.is_empty(), "The turret has no passives, so its attack stays physical, and no abilities")
	suite.expect(snapshot.get_ability_presentation_definition(ability.presentation_id) != null and snapshot.get_unit_presentation_definition(unit.presentation_id) != null, "The turret summon and its unit have presentations")
	suite.expect(BattleActionIcons.ability(TURRET) == BattleActionIcons.ICONS.turret, "The turret summon uses the turret pictogram")
	var text := AbilityDescription.render(ability, {"find_unit": snapshot.get_unit_definition})
	suite.expect(text == "Призывает «Турель» на свободный гекс на дальности 4: ОЗ 2, атака 2 на дальность 2. Перезарядка 3.", "The turret description fills its summon values: %s" % text)
	var skills := SkillLibrary.new([core])
	var document: Dictionary = skills.builtin_documents().get(String(TURRET), {})
	suite.expect(not document.is_empty() and skills.validate(document).is_empty(), "The skill editor reads the built-in turret summon as valid")


## p at (0, 0) with an ally at (2, 0) and an enemy at (6, 0) on one row: axial distance is |dq|.
func _check_battle(suite: Node, fixture: Fixtures, ability: AbilityDefinition, unit: UnitDefinition) -> void:
	var cells: Array[Vector2i] = []
	for q in range(8):
		cells.append(Vector2i(q, 0))
	var user := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i(0, 0))
	var ally := fixture.unit(&"a", BattleFaction.Value.PLAYER, Vector2i(2, 0))
	var enemy := fixture.unit(&"e", BattleFaction.Value.ENEMY, Vector2i(6, 0))
	user.abilities[ability.id] = ability
	user.ability_cooldowns[ability.id] = 0
	var state := fixture.state(cells, [user, ally, enemy])
	# The battle setup resolves the summoned unit by ID; a hand-built state registers it itself.
	state.unit_definitions[TURRET_UNIT] = unit
	var engine := BattleEngine.new(state)
	var expected: Array[Vector2i] = [Vector2i(1, 0), Vector2i(3, 0), Vector2i(4, 0)]
	suite.expect(AbilityExecutor.get_target_hexes(state, user.unit_id, TURRET) == expected, "The turret targets free hexes up to distance 4, not the ally's hex or distance 5: %s" % [AbilityExecutor.get_target_hexes(state, user.unit_id, TURRET)])
	var too_far := engine.execute(UseAbilityCommand.at_hex(user.unit_id, Vector2i(5, 0), TURRET))
	suite.expect(not too_far.accepted and user.turn.main_action_available, "A summon at distance 5 is rejected without spending the action")

	var summon := engine.execute(UseAbilityCommand.at_hex(user.unit_id, Vector2i(4, 0), TURRET))
	var turret: UnitState = null
	var summoner := StringName()
	for event: BattleEvent in summon.events:
		if event is UnitSummonedEvent:
			turret = state.unit_states.get(event.unit.unit_id)
			summoner = event.summoner_id
	suite.expect(summon.accepted and turret != null, "The turret is summoned at distance 4: %s" % summon.rejection_reason)
	if turret == null:
		return
	suite.expect(summoner == user.unit_id and turret.definition_id == TURRET_UNIT and turret.faction == BattleFaction.Value.PLAYER and turret.is_summoned and turret.hex == Vector2i(4, 0), "The summoned turret is the user's ally on the chosen hex")
	suite.expect(turret.health.current == 2 and turret.health.maximum == 2 and turret.basic_attack_damage == 2 and turret.basic_attack_range == 2 and turret.basic_attack_damage_type == &"physical" and turret.turn.movement_max == 0, "The summoned turret has 2/2 HP, a physical attack of 2 at range 2 and no movement")

	engine.execute(EndTurnCommand.new(ally.unit_id))
	engine.execute(EndPhaseCommand.new(BattleFaction.Value.ENEMY))
	suite.expect(engine.get_round_number() == 2 and engine.can_command(turret.unit_id), "The turret acts in the next player phase")
	var shot := engine.execute(AttackCommand.new(turret.unit_id, enemy.unit_id))
	var hit: UnitDamagedEvent = null
	for event: BattleEvent in shot.events:
		if event is UnitDamagedEvent and event.attacker_id == turret.unit_id:
			hit = event
	suite.expect(shot.accepted and hit != null and hit.target_id == enemy.unit_id and hit.damage == 2 and hit.damage_type == &"physical" and hit.ranged_attack, "The turret shoots an enemy 2 hexes away for 2 physical damage")

	var blocked := true
	for own_turn in range(2, 5):
		if engine.get_round_number() != own_turn or engine.get_active_faction() != BattleFaction.Value.PLAYER:
			blocked = false
			break
		blocked = blocked and not engine.execute(UseAbilityCommand.at_hex(user.unit_id, Vector2i(3, 0), TURRET)).accepted
		engine.execute(EndPhaseCommand.new(BattleFaction.Value.PLAYER))
		engine.execute(EndPhaseCommand.new(BattleFaction.Value.ENEMY))
	suite.expect(blocked, "The turret summon is blocked on the three following own turns")
	var again := engine.execute(UseAbilityCommand.at_hex(user.unit_id, Vector2i(3, 0), TURRET))
	suite.expect(engine.get_round_number() == 5 and again.accepted, "The turret summon is available again on the fourth following own turn: %s" % again.rejection_reason)
