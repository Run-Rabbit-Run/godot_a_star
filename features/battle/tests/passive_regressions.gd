extends RefCounted
## Passives of the battle: immunity to pushes; «Я здесь» — one attack charge for a unit that
## starts its turn next to an opponent, spent by its next own ordinary attack; and the choice
## between a physical and an electric ordinary attack that stays with the unit.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")
const IMMUNE_PUSH := &"core:immune_push"
const ENGAGED_CHARGE := &"core:engaged_charge"
const ATTACK_CHOICE := &"core:electric_attack_choice"
const CHARGE := UnitStatusCatalog.ATTACK_CHARGE
const PLAYER := BattleFaction.Value.PLAYER
const ENEMY := BattleFaction.Value.ENEMY


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	_run_factory(suite)
	_run_push_immunity(suite, fixture)
	_run_charge_grant(suite, fixture)
	_run_charge_spend(suite, fixture)
	_run_attack_type(suite, fixture)
	_run_ai(suite, fixture)
	_run_content(suite, fixture)


func _run_factory(suite: Node) -> void:
	var state := _create([IMMUNE_PUSH, ENGAGED_CHARGE, ATTACK_CHOICE])
	suite.expect(state != null and state.push_immune and state.engaged_charge == 1, "The factory turns push immunity and «Я здесь» into the unit's state")
	suite.expect(state != null and state.basic_attack_damage_type == &"physical" and state.attack_damage_types == [&"physical", &"electric"], "The attack choice starts physical and offers electric")
	suite.expect(state != null and not state.statuses.has(CHARGE), "A unit enters the battle without a charge")
	if state != null:
		var copy := state.duplicate_state()
		var snapshot := UnitSnapshot.new(state)
		suite.expect(copy.push_immune and copy.engaged_charge == 1 and copy.attack_damage_types == state.attack_damage_types, "A prediction copy keeps the new passives")
		suite.expect(snapshot.push_immune and snapshot.engaged_charge == 1 and snapshot.attack_damage_types == state.attack_damage_types, "The unit snapshot shows the new passives")
	var plain := _create([])
	suite.expect(plain != null and not plain.push_immune and plain.engaged_charge == 0 and plain.attack_damage_types.is_empty(), "A unit without the passives has no immunity, charge or choice")
	var both: Array[StringName] = [ATTACK_CHOICE, &"core:electric_attack"]
	suite.expect(not PassiveAbilityCatalog.validate(both).is_empty(), "The attack choice is an attack type passive: another one cannot join it")


func _run_push_immunity(suite: Node, fixture: Fixtures) -> void:
	var pusher := fixture.unit(&"pusher", PLAYER, Vector2i.ZERO)
	var target := fixture.unit(&"target", ENEMY, Vector2i(1, 0))
	var blocker := fixture.unit(&"blocker", ENEMY, Vector2i(2, 0))
	target.push_immune = true
	var state := fixture.state(_cells(4), [pusher, target, blocker])
	var context := BattleEffectContext.new(state, &"test:push")
	var events := context.push(pusher.unit_id, target.unit_id, 2)
	suite.expect(target.hex == Vector2i(1, 0) and events.is_empty() and not context.has_failed(), "A push leaves an immune unit on its hex and publishes nothing")
	suite.expect(target.health.current == 100 and blocker.health.current == 100, "An immune unit does not collide: nobody takes collision damage")
	var shove := load("res://content/packages/core/shove.tres") as AbilityDefinition
	pusher.abilities[shove.id] = shove
	var engine := BattleEngine.new(state)
	var result := engine.execute(UseAbilityCommand.new(pusher.unit_id, target.unit_id, shove.id))
	suite.expect(result.accepted and target.hex == Vector2i(1, 0) and target.health.current == 99 and blocker.health.current == 100, "Shove still hits an immune unit but does not move it")


func _run_charge_grant(suite: Node, fixture: Fixtures) -> void:
	var hero := fixture.unit(&"hero", PLAYER, Vector2i.ZERO)
	var enemy := fixture.unit(&"enemy", ENEMY, Vector2i(1, 0))
	hero.engaged_charge = 1
	enemy.engaged_charge = 1
	var engine := BattleEngine.new(fixture.state(_cells(3), [hero, enemy]))
	var start := engine.get_initial_resolution().events
	suite.expect(hero.statuses.get(CHARGE, 0) == 1, "A unit with «Я здесь» that starts its turn next to an opponent gets a charge")
	suite.expect(start.any(func(event: BattleEvent) -> bool: return event is UnitStatusChangedEvent and event.unit_id == hero.unit_id and event.statuses.get(CHARGE, 0) == 1), "The charge is published as a status change")
	suite.expect(not enemy.statuses.has(CHARGE), "The other side gets its charge only when its own phase starts")
	engine.execute(EndTurnCommand.new(hero.unit_id))
	suite.expect(engine.get_active_faction() == ENEMY and enemy.statuses.get(CHARGE, 0) == 1, "The opponent's phase start gives the opponent its charge")
	engine.execute(EndTurnCommand.new(enemy.unit_id))
	suite.expect(engine.get_active_faction() == PLAYER and hero.statuses.get(CHARGE, 0) == 1, "Another turn started next to an opponent keeps one charge: charges do not stack")

	var lonely := _granted(fixture, [fixture.unit(&"enemy", ENEMY, Vector2i(2, 0))])
	suite.expect(lonely == 0, "A unit that starts its turn away from opponents gets no charge")
	var ally_only := _granted(fixture, [fixture.unit(&"ally", PLAYER, Vector2i(1, 0)), fixture.unit(&"enemy", ENEMY, Vector2i(-3, 0))])
	suite.expect(ally_only == 0, "An ally next to the unit gives no charge")
	var body := fixture.unit(&"body", ENEMY, Vector2i(1, 0))
	body.health.current = 0
	suite.expect(_granted(fixture, [body, fixture.unit(&"enemy", ENEMY, Vector2i(-3, 0))]) == 0, "An opponent's body next to the unit gives no charge")

	var paralyzed := fixture.unit(&"hero", PLAYER, Vector2i.ZERO)
	paralyzed.engaged_charge = 1
	paralyzed.statuses[UnitStatusCatalog.PARALYSIS] = 1
	BattleEngine.new(fixture.state(_cells(3), [paralyzed, fixture.unit(&"enemy", ENEMY, Vector2i(1, 0))]))
	suite.expect(not paralyzed.statuses.has(CHARGE), "A paralyzed unit loses its turn and gets no charge")
	var without := fixture.unit(&"hero", PLAYER, Vector2i.ZERO)
	BattleEngine.new(fixture.state(_cells(3), [without, fixture.unit(&"enemy", ENEMY, Vector2i(1, 0))]))
	suite.expect(not without.statuses.has(CHARGE), "A unit without «Я здесь» gets no charge next to an opponent")


func _run_charge_spend(suite: Node, fixture: Fixtures) -> void:
	var hero := fixture.unit(&"hero", PLAYER, Vector2i.ZERO)
	var enemy := fixture.unit(&"enemy", ENEMY, Vector2i(1, 0))
	hero.engaged_charge = 1
	var engine := BattleEngine.new(fixture.state(_cells(3), [hero, enemy]))
	var command := AttackCommand.new(hero.unit_id, enemy.unit_id)
	var preview := ActionPreview.build(engine.fork_for_prediction(), engine, command)
	suite.expect(preview.accepted and preview.units[enemy.unit_id].health_after == 97 and hero.statuses.get(CHARGE, 0) == 1, "The attack preview counts the charge and leaves it on the live unit")
	var result := engine.execute(command)
	var hit := _hit(result.events, enemy.unit_id)
	suite.expect(result.accepted and enemy.health.current == 97, "The charge adds 1 to the next ordinary attack: 2 + 1")
	suite.expect(hit != null and hit.base_damage == 2 and hit.damage_modifiers == [{"source_id": CHARGE, "amount": 1}] and hit.calculated_damage == 3, "The hit records the charge as a damage modifier")
	suite.expect(not hero.statuses.has(CHARGE), "The attack spends the whole charge")
	suite.expect(hit != null and BattleLogFormatter._damage_formula(hit, null).contains("+ 1 (Заряд)"), "The battle log names the charge in the formula")

	# A ranged unit striking in melee: the charge adds after the halving.
	var shooter := fixture.unit(&"shooter", PLAYER, Vector2i.ZERO)
	shooter.basic_attack_damage = 5
	shooter.basic_attack_range = 3
	shooter.statuses[CHARGE] = 1
	var near := fixture.unit(&"near", ENEMY, Vector2i(1, 0))
	engine = BattleEngine.new(fixture.state(_cells(3), [shooter, near]))
	hit = _hit(engine.execute(AttackCommand.new(shooter.unit_id, near.unit_id)).events, near.unit_id)
	suite.expect(near.health.current == 97 and hit != null and hit.damage_modifiers.size() == 2 and hit.damage_modifiers[0].source_id == BasicAttackRules.RANGED_MELEE_PENALTY and hit.damage_modifiers[1].source_id == CHARGE, "A ranged melee strike halves its damage first, then adds the charge: 2 + 1")

	# Retaliation neither uses nor spends the defender's charge.
	var attacker := fixture.unit(&"attacker", PLAYER, Vector2i.ZERO)
	var defender := fixture.unit(&"defender", ENEMY, Vector2i(1, 0))
	defender.melee_retaliation = true
	defender.retaliation_configured = true
	defender.statuses[CHARGE] = 1
	engine = BattleEngine.new(fixture.state(_cells(3), [attacker, defender]))
	engine.execute(AttackCommand.new(attacker.unit_id, defender.unit_id))
	suite.expect(attacker.health.current == 98 and defender.statuses.get(CHARGE, 0) == 1, "Retaliation strikes for ordinary damage and keeps the defender's charge")

	# An ability does not spend it, even one using the attack damage.
	var caster := fixture.unit(&"caster", PLAYER, Vector2i.ZERO)
	var victim := fixture.unit(&"victim", ENEMY, Vector2i(2, 0))
	var ability := fixture.ability(&"test:hit", AbilityDefinition.TargetMode.ENEMY)
	caster.abilities[ability.id] = ability
	caster.statuses[CHARGE] = 1
	engine = BattleEngine.new(fixture.state(_cells(3), [caster, victim]))
	result = engine.execute(UseAbilityCommand.new(caster.unit_id, victim.unit_id, ability.id))
	suite.expect(result.accepted and victim.health.current == 97 and caster.statuses.get(CHARGE, 0) == 1, "An ability neither gains from nor spends the charge")

	# An attack on an obstacle is the unit's own ordinary attack: it spends the charge too.
	var breaker := fixture.unit(&"breaker", PLAYER, Vector2i.ZERO)
	breaker.statuses[CHARGE] = 1
	var state := fixture.state(_cells(3), [breaker, fixture.unit(&"enemy", ENEMY, Vector2i(-3, 0))])
	var rock := BattleObstacleDefinition.new()
	rock.id = &"test:rock"
	rock.hexes.assign([Vector2i(1, 0)])
	rock.destructible = true
	rock.max_hp = 5
	state.hex_grid.add_obstacle(rock)
	engine = BattleEngine.new(state)
	result = engine.execute(AttackObstacleCommand.new(breaker.unit_id, Vector2i(1, 0)))
	suite.expect(result.accepted and state.hex_grid.get_obstacle(Vector2i(1, 0)).current_hp == 2 and not breaker.statuses.has(CHARGE), "An attack on an obstacle deals 2 + 1 and spends the charge")


func _run_attack_type(suite: Node, fixture: Fixtures) -> void:
	var hero := fixture.unit(&"hero", PLAYER, Vector2i.ZERO)
	var enemy := fixture.unit(&"enemy", ENEMY, Vector2i(1, 0))
	hero.attack_damage_types.assign([&"physical", &"electric"])
	hero.melee_retaliation = true
	hero.retaliation_configured = true
	enemy.statuses[UnitStatusCatalog.WET] = 2
	var engine := BattleEngine.new(fixture.state(_cells(3), [hero, enemy]))
	var physical := ActionPreview.build(engine.fork_for_prediction(), engine, AttackCommand.new(hero.unit_id, enemy.unit_id))
	var electric := ActionPreview.build(engine.fork_for_prediction(), engine, AttackCommand.new(hero.unit_id, enemy.unit_id, &"electric"))
	suite.expect(physical.units[enemy.unit_id].health_after == 98 and electric.units[enemy.unit_id].health_after == 97, "The preview follows the chosen type: electric gains 1 on a wet target")
	suite.expect(hero.basic_attack_damage_type == &"physical", "A preview does not change the live unit's type")
	var rejected := engine.execute(AttackCommand.new(hero.unit_id, enemy.unit_id, &"fire"))
	suite.expect(not rejected.accepted and hero.turn.main_action_available and enemy.health.current == 100, "A type the unit cannot choose is rejected without spending the action")
	var result := engine.execute(AttackCommand.new(hero.unit_id, enemy.unit_id, &"electric"))
	var hit := _hit(result.events, enemy.unit_id)
	suite.expect(result.accepted and hit != null and hit.damage_type == &"electric" and enemy.health.current == 97, "The attack strikes with the chosen electric type")
	suite.expect(hero.basic_attack_damage_type == &"electric", "The chosen type stays the unit's attack type")

	# The opponent's turn: a type it has no choice of is rejected, its own type is accepted,
	# and the chosen electric type answers in the retaliation.
	suite.expect(engine.get_active_faction() == ENEMY and not engine.execute(AttackCommand.new(enemy.unit_id, hero.unit_id, &"electric")).accepted, "A unit without the choice cannot pick another type")
	result = engine.execute(AttackCommand.new(enemy.unit_id, hero.unit_id, &"physical"))
	var response := _hit(result.events, enemy.unit_id)
	suite.expect(result.accepted and hero.health.current == 98, "A unit may name its own type")
	suite.expect(response != null and response.damage_type == &"electric" and enemy.health.current == 94, "Retaliation strikes with the type of the unit's last attack")


func _run_ai(suite: Node, fixture: Fixtures) -> void:
	var striker := fixture.unit(&"striker", ENEMY, Vector2i.ZERO)
	var wet := fixture.unit(&"wet", PLAYER, Vector2i(1, 0))
	striker.attack_damage_types.assign([&"physical", &"electric"])
	wet.statuses[UnitStatusCatalog.WET] = 2
	var state := fixture.state(_cells(3), [striker, wet])
	var session := fixture.ai_session(state)
	var command := AICommandSource._attack_command(session, session.get_unit(striker.unit_id), session.get_unit(wet.unit_id))
	suite.expect(command.damage_type == &"electric", "The basic AI attacks a wet target with electricity")
	wet.statuses.clear()
	command = AICommandSource._attack_command(session, session.get_unit(striker.unit_id), session.get_unit(wet.unit_id))
	suite.expect(command.damage_type.is_empty(), "On equal damage the basic AI keeps its current type")
	wet.statuses[UnitStatusCatalog.ARMOR] = 1
	command = AICommandSource._attack_command(session, session.get_unit(striker.unit_id), session.get_unit(wet.unit_id))
	suite.expect(command.damage_type == &"electric", "The basic AI strikes armor with electricity")

	var engine := BattleEngine.new(state, false)
	var others: Dictionary[Vector2i, UnitState] = {wet.hex: wet}
	var types: Array[StringName] = []
	for action: BattleCommand in AILastActionPlanner.actions(engine, striker, state.hex_grid, others, {"reach": {}, "skipped": 0}):
		if action is AttackCommand:
			types.append(action.damage_type)
	suite.expect(types == [&"physical", &"electric"], "The planners forecast an attack of each type the unit may choose")


func _run_content(suite: Node, fixture: Fixtures) -> void:
	var skills := fixture.skills()
	for id: StringName in [IMMUNE_PUSH, ENGAGED_CHARGE, ATTACK_CHOICE]:
		var document: Dictionary = skills.builtin_documents().get(String(id), {})
		var reread: Dictionary = SkillLibrary.normalized(JSON.parse_string(JSON.stringify(document)))
		suite.expect(not document.is_empty() and skills.validate(reread).is_empty() and skills.is_builtin_default(reread), "The built-in passive %s survives a JSON round trip as its default document" % id)
		var text := AbilityDescription.render_passive(PassiveAbilityCatalog.DEFINITIONS[id])
		suite.expect(not text.is_empty() and not "{" in text, "The passive %s describes itself: %s" % [id, text])
		var renamed := document.duplicate(true)
		renamed.name = "Другое имя"
		var definition: Dictionary = SkillLibrary.passive_definitions({renamed.id: renamed})[id]
		var fixed := {IMMUNE_PUSH: "push_immunity", ENGAGED_CHARGE: "engaged_charge", ATTACK_CHOICE: "alternate_damage_type"}[id] as String
		suite.expect(definition.get(fixed) == PassiveAbilityCatalog.DEFINITIONS[id][fixed], "Renaming %s keeps its fixed effect" % id)
	suite.expect(ResourceLoader.exists("res://features/battle/ui/icons/status/attack_charge.svg"), "The charge has a status icon")


## The attack type switch in the HUD: shown for a unit with the choice, chosen before the attack.
func run_presentation(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var passives: Array[StringName] = [ATTACK_CHOICE]
	var screen := preload("res://features/battle/battle_screen.tscn").instantiate() as BattleScreen
	suite.expect(screen.setup(fixture.spear_request(passives)), "Attack choice battle setup accepted")
	suite.add_child(screen)
	var controller: BattleController = screen.get("_battle_controller")
	for _frame in range(600):
		await suite.get_tree().process_frame
		if not controller.get("_is_presenting"):
			break
	var selection: PlayerActionSelection = controller.get("_selection")
	var session: BattleSession = controller.get("_battle_session")
	var hud := screen.get_node("BattleMap/BattleUI") as BattleHUD
	var active := session.get_unit(session.get_active_unit_id())
	var button := hud.get("_attack_type_button") as Button
	suite.expect(active != null and active.attack_damage_types == [&"physical", &"electric"], "The battle's active unit has the attack choice")
	suite.expect(button != null and button.visible and not button.disabled and button.text.contains("физический"), "The HUD shows the attack type switch with the current type")
	if active == null or button == null:
		screen.queue_free()
		return
	button.pressed.emit()
	suite.expect(selection.attack_damage_type() == &"electric" and button.text.contains("электрический"), "The switch makes the next attack electric")
	suite.expect(session.get_unit(active.unit_id).basic_attack_damage_type == &"physical", "Switching changes nothing in the battle before the attack")
	var approach := _hex_next_to_opponent(session, active)
	if approach != active.hex:
		session.step(MoveCommand.new(active.unit_id, approach))
		active = session.get_unit(active.unit_id)
		selection.show_movement_and_attacks(active)
	var targets := session.get_attackable_targets(active.unit_id)
	suite.expect(not targets.is_empty(), "The unit with the choice reaches an opponent")
	if not targets.is_empty():
		var command := selection.command_at(active, targets[0].hex) as AttackCommand
		suite.expect(command != null and command.damage_type == &"electric", "After a move, clicking an opponent attacks with the chosen type")
		var result := session.step(command)
		var hit := _hit(result.events, targets[0].unit_id)
		suite.expect(result.accepted and hit != null and hit.damage_type == &"electric" and session.get_unit(active.unit_id).basic_attack_damage_type == &"electric", "The attack strikes electric and the unit keeps the type")
	var no_choice: Array[StringName] = []
	hud.show_attack_type(no_choice, &"", true)
	suite.expect(not button.visible, "A unit without the choice has no switch")
	screen.queue_free()
	await suite.get_tree().process_frame


## Charge levels a «Я здесь» unit at the origin has after the battle starts among `others`.
func _granted(fixture: Fixtures, others: Array) -> int:
	var hero := fixture.unit(&"hero", PLAYER, Vector2i.ZERO)
	hero.engaged_charge = 1
	var units: Array[UnitState] = [hero]
	units.append_array(others)
	BattleEngine.new(fixture.state(_cells(3), units))
	return int(hero.statuses.get(CHARGE, 0))


static func _create(ids: Array[StringName]) -> UnitState:
	var definition := UnitDefinition.new()
	definition.base_stats = UnitStatsDefinition.new()
	definition.base_stats.basic_attack_damage = 3
	definition.passive_ability_ids.assign(ids)
	var spawn := UnitSpawnData.new(&"test:unit", &"test:placement", &"test:definition", definition, &"test:side", PLAYER, BattleControlSource.Value.PLAYER, &"", null, Vector2i.ZERO)
	return UnitStateFactory.create(spawn)


static func _hit(events: Array[BattleEvent], target_id: StringName) -> UnitDamagedEvent:
	for event: BattleEvent in events:
		if event is UnitDamagedEvent and event.target_id == target_id:
			return event
	return null


static func _hex_next_to_opponent(session: BattleSession, active: UnitSnapshot) -> Vector2i:
	var reachable := session.get_movement_search(active.unit_id).get_reachable_cells()
	reachable.sort()
	for opponent: UnitSnapshot in session.get_living_opponents(active.faction):
		if HexGrid.get_distance(active.hex, opponent.hex) <= active.basic_attack_range:
			return active.hex
		for hex: Vector2i in reachable:
			if session.get_unit_at(hex) == null and HexGrid.get_distance(hex, opponent.hex) <= active.basic_attack_range:
				return hex
	return active.hex


static func _cells(radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		for r in range(maxi(-radius, -q - radius), mini(radius, radius - q) + 1):
			cells.append(Vector2i(q, r))
	return cells
