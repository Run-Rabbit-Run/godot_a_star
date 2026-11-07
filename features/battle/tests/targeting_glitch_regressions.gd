extends RefCounted
## «Сбой наведения»: an enemy within 6 gets a targeting glitch; its next ordinary attack —
## at a unit, an obstacle or a retaliation — deals 1 less per level, not below 0, and spends
## the glitch. Unspent, the glitch falls at the end of the target's next phase.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")
const GLITCH_ABILITY := &"core:targeting_glitch"
const GLITCH := UnitStatusCatalog.TARGETING_GLITCH
const PLAYER := BattleFaction.Value.PLAYER
const ENEMY := BattleFaction.Value.ENEMY


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var core: ContentPackage = load("res://content/packages/core/core_package.tres")
	var loaded := ContentLoader.load_packages([core])
	var ability := loaded.snapshot.get_ability_definition(GLITCH_ABILITY) if loaded.is_successful else null
	suite.expect(ability != null, "The core package ships «Сбой наведения»: %s" % "\n".join(loaded.errors))
	if ability == null:
		return
	_run_definition(suite, loaded.snapshot, ability, core)
	_run_ability(suite, fixture, ability)
	_run_attack(suite, fixture)
	_run_other_attacks(suite, fixture)
	_run_expiry(suite, fixture, ability)


func _run_definition(suite: Node, snapshot: ContentSnapshot, ability: AbilityDefinition, core: ContentPackage) -> void:
	suite.expect(ability.target_mode == AbilityDefinition.TargetMode.ENEMY and ability.range == 6 and ability.area_radius == 0 and not ability.melee_attack, "«Сбой наведения» targets an enemy within 6")
	suite.expect(ability.cooldown_turns == 1 and ability.initial_cooldown_turns == 0, "«Сбой наведения» has a cooldown of 1 and none at the start")
	var effect := ability.effects[0] if ability.effects.size() == 1 else null
	suite.expect(effect != null and effect.effect_type_id == &"core:unit_status" and StringName(effect.parameters.get("status_id")) == GLITCH and effect.parameters.get("levels") == 1, "«Сбой наведения» gives one level of the glitch")
	suite.expect(snapshot.get_ability_presentation_definition(ability.presentation_id) != null, "«Сбой наведения» has a presentation")
	var text := AbilityDescription.render(ability)
	suite.expect(text.contains("сбой наведения ×1") and text.contains("6") and not "{" in text, "The ability describes itself: %s" % text)
	suite.expect(UnitStatusCatalog.category(GLITCH) == UnitStatusCatalog.Category.RESERVE and UnitStatusCatalog.drops_at_phase_end(GLITCH) and not UnitStatusCatalog.drops_at_phase_start(GLITCH), "The glitch is a reserve that falls whole at the end of its side's phase")
	suite.expect(ResourceLoader.exists("res://features/battle/ui/icons/status/targeting_glitch.svg"), "The glitch has a status icon")
	var skills := SkillLibrary.new([core])
	var document: Dictionary = skills.builtin_documents().get(String(GLITCH_ABILITY), {})
	var reread: Dictionary = SkillLibrary.normalized(JSON.parse_string(JSON.stringify(document)))
	suite.expect(not document.is_empty() and skills.validate(reread).is_empty() and skills.is_builtin_default(reread), "The skill editor reads the built-in glitch ability as valid")


func _run_ability(suite: Node, fixture: Fixtures, ability: AbilityDefinition) -> void:
	var user := fixture.unit(&"user", PLAYER, Vector2i.ZERO)
	_give(user, ability)
	var ally := fixture.unit(&"ally", PLAYER, Vector2i(1, 0))
	var near := fixture.unit(&"near", ENEMY, Vector2i(6, 0))
	var far := fixture.unit(&"far", ENEMY, Vector2i(7, 0))
	var state := fixture.state(_line(-1, 8), [user, ally, near, far])
	var engine := BattleEngine.new(state)
	var expected: Array[Vector2i] = [near.hex]
	suite.expect(AbilityExecutor.get_target_hexes(state, user.unit_id, GLITCH_ABILITY) == expected, "The glitch reaches an enemy at 6, not at 7 nor an ally")
	var result := engine.execute(UseAbilityCommand.new(user.unit_id, near.unit_id, GLITCH_ABILITY))
	suite.expect(result.accepted and near.statuses.get(GLITCH, 0) == 1 and not user.turn.main_action_available, "The glitch lands on the enemy and ends the user's turn")
	suite.expect(far.statuses.get(GLITCH, 0) == 0 and ally.statuses.is_empty(), "Only the chosen enemy is glitched")
	var events: Array[BattleEvent] = []
	UnitStatusService.apply(near, GLITCH, 1, events)
	suite.expect(near.statuses.get(GLITCH, 0) == 2, "A second glitch adds a level")


## The enemy at (1, 0) with attack 3 strikes the player at the origin.
func _run_attack(suite: Node, fixture: Fixtures) -> void:
	var setup := _duel(fixture, 3, 1)
	var engine: BattleEngine = setup.engine
	var attacker: UnitState = setup.enemy
	var target: UnitState = setup.player
	var command := AttackCommand.new(attacker.unit_id, target.unit_id)
	var preview := ActionPreview.build(engine.fork_for_prediction(), engine, command)
	suite.expect(preview.accepted and preview.units[target.unit_id].health_after == 98, "The preview of a glitched attack deals 1 less")
	var result := engine.execute(command)
	var hit := _hit(result.events, target.unit_id)
	suite.expect(result.accepted and target.health.current == 98 and hit != null and hit.base_damage == 3 and hit.calculated_damage == 2, "A glitched attack of 3 deals 2")
	suite.expect(hit != null and hit.damage_modifiers == [{"source_id": GLITCH, "amount": -1}], "The damage formula names the glitch: %s" % [hit.damage_modifiers if hit != null else []])
	suite.expect(not attacker.statuses.has(GLITCH), "The attack spends the glitch")
	var spent := _status_change_index(result.events, attacker.unit_id)
	suite.expect(spent >= 0 and spent < result.events.find(hit), "The glitch is spent before the hit lands")

	# Never below 0, and two levels take 2.
	setup = _duel(fixture, 1, 2)
	result = setup.engine.execute(AttackCommand.new(setup.enemy.unit_id, setup.player.unit_id))
	hit = _hit(result.events, setup.player.unit_id)
	suite.expect(result.accepted and setup.player.health.current == 100 and hit != null and hit.damage == 0 and hit.damage_modifiers == [{"source_id": GLITCH, "amount": -1}], "A glitch takes damage down to 0, never below")
	setup = _duel(fixture, 5, 2)
	setup.engine.execute(AttackCommand.new(setup.enemy.unit_id, setup.player.unit_id))
	suite.expect(setup.player.health.current == 97, "Two levels of glitch take 2 damage")

	# After the attack charge and the melee halving of a shooter.
	setup = _duel(fixture, 2, 1)
	setup.enemy.statuses[UnitStatusCatalog.ATTACK_CHARGE] = 1
	result = setup.engine.execute(AttackCommand.new(setup.enemy.unit_id, setup.player.unit_id))
	hit = _hit(result.events, setup.player.unit_id)
	suite.expect(hit != null and hit.damage == 2 and hit.damage_modifiers == [{"source_id": UnitStatusCatalog.ATTACK_CHARGE, "amount": 1}, {"source_id": GLITCH, "amount": -1}], "The glitch comes after the attack charge")
	setup = _duel(fixture, 4, 1)
	setup.enemy.basic_attack_range = 3
	result = setup.engine.execute(AttackCommand.new(setup.enemy.unit_id, setup.player.unit_id))
	hit = _hit(result.events, setup.player.unit_id)
	suite.expect(hit != null and hit.damage == 1 and hit.damage_modifiers == [{"source_id": BasicAttackRules.RANGED_MELEE_PENALTY, "amount": -2}, {"source_id": GLITCH, "amount": -1}], "The glitch comes after a shooter's melee halving")


func _run_other_attacks(suite: Node, fixture: Fixtures) -> void:
	# A strike at an obstacle is the unit's attack too.
	var setup := _duel(fixture, 3, 1)
	var state: BattleState = setup.state
	state.hex_grid.add_obstacle(_obstacle(Vector2i(2, 0)))
	var result: BattleResolution = setup.engine.execute(AttackObstacleCommand.new(setup.enemy.unit_id, Vector2i(2, 0)))
	suite.expect(result.accepted and state.hex_grid.get_obstacle(Vector2i(2, 0)).current_hp == 8 and not setup.enemy.statuses.has(GLITCH), "A glitched strike at an obstacle deals 1 less and spends the glitch")

	# A retaliation is the defender's next attack.
	setup = _duel(fixture, 3, 1)
	var defender: UnitState = setup.enemy
	defender.melee_retaliation = true
	defender.retaliation_configured = true
	var player: UnitState = setup.player
	var engine: BattleEngine = setup.engine
	engine.execute(EndPhaseCommand.new(ENEMY))
	suite.expect(engine.get_active_faction() == PLAYER and defender.statuses.get(GLITCH, 0) == 0, "Unspent, the glitch falls when the enemy phase ends")
	defender.statuses[GLITCH] = 1
	result = engine.execute(AttackCommand.new(player.unit_id, defender.unit_id))
	var response := _hit(result.events, player.unit_id)
	suite.expect(result.accepted and response != null and response.source_ability_id == &"core:melee_retaliation" and response.damage == 2 and not defender.statuses.has(GLITCH), "A glitched retaliation deals 1 less and spends the glitch")

	# Abilities are no attack: they neither suffer from the glitch nor spend it.
	setup = _duel(fixture, 3, 1)
	var bomb := fixture.ability(&"test:bomb", AbilityDefinition.TargetMode.HEX)
	_give(setup.enemy, bomb)
	result = setup.engine.execute(UseAbilityCommand.at_hex(setup.enemy.unit_id, setup.player.hex, bomb.id))
	suite.expect(result.accepted and setup.player.health.current == 97 and setup.enemy.statuses.get(GLITCH, 0) == 1, "An ability deals full damage and keeps the glitch")


## The glitch lasts through the target's next phase: it does not fall at the phase start.
func _run_expiry(suite: Node, fixture: Fixtures, ability: AbilityDefinition) -> void:
	var user := fixture.unit(&"user", PLAYER, Vector2i.ZERO)
	_give(user, ability)
	var target := fixture.unit(&"target", ENEMY, Vector2i(4, 0))
	var engine := BattleEngine.new(fixture.state(_line(-1, 6), [user, target]))
	engine.execute(UseAbilityCommand.new(user.unit_id, target.unit_id, GLITCH_ABILITY))
	suite.expect(engine.get_active_faction() == ENEMY and target.statuses.get(GLITCH, 0) == 1, "The glitch lasts into the target's phase")
	var ended := engine.execute(EndPhaseCommand.new(ENEMY))
	suite.expect(ended.accepted and engine.get_active_faction() == PLAYER and not target.statuses.has(GLITCH), "The glitch falls at the end of the target's phase")
	var dropped := false
	for event: BattleEvent in ended.events:
		dropped = dropped or (event is UnitStatusChangedEvent and event.unit_id == target.unit_id and event.previous_statuses.has(GLITCH) and not event.statuses.has(GLITCH))
	suite.expect(dropped, "Its fall is announced to the view")


## A player at the origin and an enemy at (1, 0) with the given attack and glitch levels, in
## the enemy's phase; a second enemy far away keeps the phase going after the first acts.
static func _duel(fixture: Fixtures, damage: int, glitch: int) -> Dictionary:
	var player := fixture.unit(&"player", PLAYER, Vector2i.ZERO)
	var enemy := fixture.unit(&"enemy", ENEMY, Vector2i(1, 0))
	enemy.basic_attack_damage = damage
	enemy.statuses[GLITCH] = glitch
	var reserve := fixture.unit(&"reserve", ENEMY, Vector2i(4, 0))
	var state := fixture.state(_line(-1, 4), [enemy, player, reserve])
	Fixtures.start_turns(state)
	var engine := BattleEngine.new(state, false)
	return {"player": player, "enemy": enemy, "state": state, "engine": engine}


static func _give(unit: UnitState, ability: AbilityDefinition) -> void:
	unit.abilities[ability.id] = ability
	unit.ability_cooldowns[ability.id] = 0


static func _hit(events: Array[BattleEvent], target_id: StringName) -> UnitDamagedEvent:
	for event: BattleEvent in events:
		if event is UnitDamagedEvent and event.target_id == target_id:
			return event
	return null


static func _status_change_index(events: Array[BattleEvent], unit_id: StringName) -> int:
	for index in range(events.size()):
		if events[index] is UnitStatusChangedEvent and events[index].unit_id == unit_id:
			return index
	return -1


static func _obstacle(hex: Vector2i) -> BattleObstacleDefinition:
	var obstacle := BattleObstacleDefinition.new()
	obstacle.id = StringName("test:obstacle_%d_%d" % [hex.x, hex.y])
	obstacle.destructible = true
	obstacle.max_hp = 10
	obstacle.hexes.append(hex)
	return obstacle


static func _line(from: int, to: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for q in range(from, to + 1):
		cells.append(Vector2i(q, 0))
	return cells
