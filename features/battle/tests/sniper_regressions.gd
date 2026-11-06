extends RefCounted
## The «Снайперский выстрел» passive: a shot only before the unit spends movement points in its
## turn; a neighbor is still struck in melee, and pushes or slowing statuses spend no points.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")
const SNIPER := &"core:sniper_shot"
const PLAYER := BattleFaction.Value.PLAYER
const ENEMY := BattleFaction.Value.ENEMY
const MOVED_REASON := "Снайперский выстрел невозможен после перемещения."


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	_run_factory(suite)
	_run_turn_state(suite, fixture)
	_run_shot(suite, fixture)
	_run_free_movement(suite, fixture)
	_run_obstacle(suite, fixture)
	_run_reach(suite, fixture)
	_run_ai(suite, fixture)
	_run_content(suite, fixture)


func _run_factory(suite: Node) -> void:
	var state := _create([SNIPER])
	suite.expect(state != null and state.sniper_shot, "The factory turns «Снайперский выстрел» into the unit's state")
	if state != null:
		state.turn.spend_movement(2)
		var copy := state.duplicate_state()
		var snapshot := UnitSnapshot.new(state)
		suite.expect(copy.sniper_shot and copy.turn.movement_spent == 2, "A prediction copy keeps the sniper and its spent movement")
		suite.expect(snapshot.sniper_shot and snapshot.turn.movement_spent == 2, "The unit snapshot shows the sniper and its spent movement")
	var plain := _create([])
	suite.expect(plain != null and not plain.sniper_shot, "A unit without the passive is no sniper")
	var typed: Array[StringName] = [SNIPER, &"core:electric_attack"]
	suite.expect(PassiveAbilityCatalog.validate(typed).is_empty(), "The sniper shot is no attack type passive: it joins a damage type passive")


func _run_turn_state(suite: Node, fixture: Fixtures) -> void:
	var turn := TurnState.new(4)
	suite.expect(turn.movement_spent == 0, "A turn starts with no movement spent")
	turn.spend_movement(1)
	turn.spend_movement(2)
	suite.expect(turn.movement_spent == 3 and turn.movement_remaining == 1, "Spent movement adds up over the moves of a turn")
	suite.expect(not turn.spend_movement(2) and turn.movement_spent == 3, "A refused step spends nothing")
	turn.start_turn()
	suite.expect(turn.movement_spent == 0 and turn.movement_remaining == 4, "A new turn forgets the spent movement")

	# A move counts what it actually spent on the way.
	var sniper := _sniper(fixture, &"sniper", PLAYER, Vector2i.ZERO)
	var engine := BattleEngine.new(fixture.state(_line(-3, 8), [sniper, fixture.unit(&"enemy", ENEMY, Vector2i(8, 0))]))
	suite.expect(engine.execute(MoveCommand.new(sniper.unit_id, Vector2i(2, 0))).accepted and sniper.turn.movement_spent == 2, "A move of two hexes spends two movement points")


func _run_shot(suite: Node, fixture: Fixtures) -> void:
	var sniper := _sniper(fixture, &"sniper", PLAYER, Vector2i.ZERO)
	var enemy := fixture.unit(&"enemy", ENEMY, Vector2i(3, 0))
	var engine := BattleEngine.new(fixture.state(_line(-3, 8), [sniper, enemy]))
	var shot := AttackCommand.new(sniper.unit_id, enemy.unit_id)
	suite.expect(_target_ids(engine, sniper) == [enemy.unit_id], "A sniper that has not moved may shoot a target in range")
	var preview := ActionPreview.build(engine.fork_for_prediction(), engine, shot)
	suite.expect(preview.accepted and preview.units[enemy.unit_id].health_after == 95, "The preview of a shot before moving deals full damage")

	suite.expect(engine.execute(MoveCommand.new(sniper.unit_id, Vector2i(1, 0))).accepted, "The sniper moves one hex")
	suite.expect(_target_ids(engine, sniper).is_empty(), "After moving the sniper has no target past its neighbors")
	var rejected := engine.execute(shot)
	suite.expect(not rejected.accepted and sniper.turn.main_action_available and enemy.health.current == 100, "A shot after moving is rejected without spending the action")
	suite.expect(not ActionPreview.build(engine.fork_for_prediction(), engine, shot).accepted, "The preview refuses the shot after moving as well")

	# A neighbor is still struck in melee, at half damage.
	suite.expect(engine.execute(MoveCommand.new(sniper.unit_id, Vector2i(2, 0))).accepted, "The sniper steps next to the opponent")
	suite.expect(_target_ids(engine, sniper) == [enemy.unit_id], "After moving the sniper may strike its neighbor")
	var strike := engine.execute(shot)
	var hit := _hit(strike.events, enemy.unit_id)
	suite.expect(strike.accepted and enemy.health.current == 98 and hit != null and not hit.ranged_attack, "After moving the sniper strikes a neighbor in melee for half damage")

	# Standing still, the sniper shoots for full damage.
	sniper = _sniper(fixture, &"sniper", PLAYER, Vector2i.ZERO)
	enemy = fixture.unit(&"enemy", ENEMY, Vector2i(3, 0))
	engine = BattleEngine.new(fixture.state(_line(-3, 8), [sniper, enemy]))
	var fired := engine.execute(AttackCommand.new(sniper.unit_id, enemy.unit_id))
	hit = _hit(fired.events, enemy.unit_id)
	suite.expect(fired.accepted and enemy.health.current == 95 and hit != null and hit.ranged_attack, "A sniper that has not moved shoots for full damage")

	# A shooter without the passive still shoots after moving.
	var shooter := _sniper(fixture, &"shooter", PLAYER, Vector2i.ZERO)
	shooter.sniper_shot = false
	enemy = fixture.unit(&"enemy", ENEMY, Vector2i(3, 0))
	engine = BattleEngine.new(fixture.state(_line(-3, 8), [shooter, enemy]))
	engine.execute(MoveCommand.new(shooter.unit_id, Vector2i(1, 0)))
	suite.expect(engine.execute(AttackCommand.new(shooter.unit_id, enemy.unit_id)).accepted and enemy.health.current == 95, "A shooter without the passive shoots after moving")

	# The next own turn forgets the move.
	sniper = _sniper(fixture, &"sniper", PLAYER, Vector2i.ZERO)
	enemy = fixture.unit(&"enemy", ENEMY, Vector2i(4, 0))
	engine = BattleEngine.new(fixture.state(_line(-3, 8), [sniper, enemy]))
	engine.execute(MoveCommand.new(sniper.unit_id, Vector2i(1, 0)))
	# Phase ends raise no shields that would swallow the shot.
	engine.execute(EndPhaseCommand.new(PLAYER))
	engine.execute(EndPhaseCommand.new(ENEMY))
	suite.expect(engine.get_active_faction() == PLAYER and sniper.turn.movement_spent == 0, "The sniper's next turn starts with no movement spent")
	suite.expect(engine.execute(AttackCommand.new(sniper.unit_id, enemy.unit_id)).accepted and enemy.health.current == 95, "In its next turn the sniper shoots from where it moved")


func _run_free_movement(suite: Node, fixture: Fixtures) -> void:
	# A slowing status takes movement points but spends none.
	var sniper := _sniper(fixture, &"sniper", PLAYER, Vector2i.ZERO)
	sniper.statuses[UnitStatusCatalog.STICKY_OIL] = 1
	var enemy := fixture.unit(&"enemy", ENEMY, Vector2i(3, 0))
	var engine := BattleEngine.new(fixture.state(_line(-3, 8), [sniper, enemy]))
	suite.expect(sniper.turn.movement_remaining == 7 and sniper.turn.movement_spent == 0, "Oil takes a movement point without spending it")
	suite.expect(engine.execute(AttackCommand.new(sniper.unit_id, enemy.unit_id)).accepted and enemy.health.current == 95, "A slowed sniper that has not moved still shoots")

	# A push moves the sniper without its movement points.
	sniper = _sniper(fixture, &"sniper", PLAYER, Vector2i.ZERO)
	var pusher := fixture.unit(&"pusher", ENEMY, Vector2i(-1, 0))
	enemy = fixture.unit(&"enemy", ENEMY, Vector2i(4, 0))
	var state := fixture.state(_line(-3, 8), [sniper, pusher, enemy])
	engine = BattleEngine.new(state)
	BattleEffectContext.new(state, &"test:push").push(pusher.unit_id, sniper.unit_id, 1)
	suite.expect(sniper.hex == Vector2i(1, 0) and sniper.turn.movement_spent == 0, "A push spends none of the sniper's movement")
	suite.expect(engine.execute(AttackCommand.new(sniper.unit_id, enemy.unit_id)).accepted and enemy.health.current == 95, "A pushed sniper still shoots")


func _run_obstacle(suite: Node, fixture: Fixtures) -> void:
	var sniper := _sniper(fixture, &"sniper", PLAYER, Vector2i.ZERO)
	var state := fixture.state(_line(-3, 8), [sniper, fixture.unit(&"enemy", ENEMY, Vector2i(8, 0))])
	state.hex_grid.add_obstacle(_obstacle(Vector2i(3, 0)))
	var engine := BattleEngine.new(state)
	suite.expect(engine.get_attackable_obstacle_hexes(sniper.unit_id) == [Vector2i(3, 0)], "A sniper that has not moved may shoot an obstacle")
	engine.execute(MoveCommand.new(sniper.unit_id, Vector2i(1, 0)))
	suite.expect(engine.get_attackable_obstacle_hexes(sniper.unit_id).is_empty(), "After moving the sniper cannot shoot an obstacle")
	var rejected := engine.execute(AttackObstacleCommand.new(sniper.unit_id, Vector2i(3, 0)))
	suite.expect(not rejected.accepted and rejected.rejection_reason == MOVED_REASON and sniper.turn.main_action_available, "The obstacle shot after moving is rejected with the sniper reason")
	engine.execute(MoveCommand.new(sniper.unit_id, Vector2i(2, 0)))
	var strike := engine.execute(AttackObstacleCommand.new(sniper.unit_id, Vector2i(3, 0)))
	suite.expect(strike.accepted and state.hex_grid.get_obstacle(Vector2i(3, 0)).current_hp == 8, "After moving the sniper strikes an adjacent obstacle for half damage")


func _run_reach(suite: Node, fixture: Fixtures) -> void:
	var sniper := _sniper(fixture, &"sniper", ENEMY, Vector2i.ZERO, 1)
	var shooter := _sniper(fixture, &"shooter", ENEMY, Vector2i(0, -5), 1)
	shooter.sniper_shot = false
	var engine := BattleEngine.new(fixture.state(_disk(6), [fixture.unit(&"player", PLAYER, Vector2i(-6, 0)), sniper, shooter]))
	var sniper_reach: Array = engine.get_reach(sniper.unit_id).attack
	var shooter_reach: Array = engine.get_reach(shooter.unit_id).attack
	suite.expect(sniper_reach.has(Vector2i(3, 0)) and sniper_reach.has(Vector2i(-3, 0)), "The sniper threatens its whole range from where it stands")
	suite.expect(not sniper_reach.has(Vector2i(4, 0)) and not sniper_reach.has(Vector2i(3, 1)), "The sniper threatens no shot from a hex it would have to move to")
	suite.expect(shooter_reach.has(Vector2i(4, -5)), "A shooter without the passive threatens a shot after its move")


func _run_ai(suite: Node, fixture: Fixtures) -> void:
	# Engaged, a sniper cannot shoot after a step away, so it strikes where it stands.
	var sniper := _sniper(fixture, &"ai_sniper", ENEMY, Vector2i.ZERO)
	var player := fixture.unit(&"player", PLAYER, Vector2i(1, 0))
	var session := fixture.ai_session(fixture.state(_line(-3, 3), [sniper, player]))
	var source := AICommandSource.new(null)
	source.decision_trace = {}
	var command := source.next_command(session)
	suite.expect(command is AttackCommand and command.target_id == player.unit_id, "An engaged AI sniper strikes in melee instead of stepping away")

	# Out of range, the sniper moves into position and does not shoot in the same turn.
	sniper = _sniper(fixture, &"ai_sniper", ENEMY, Vector2i.ZERO)
	player = fixture.unit(&"player", PLAYER, Vector2i(6, 0))
	session = fixture.ai_session(fixture.state(_line(-3, 8), [sniper, player]))
	command = source.next_command(session)
	suite.expect(command is MoveCommand and session.step(command).accepted, "An AI sniper out of range moves closer")
	command = source.next_command(session)
	suite.expect(not command is AttackCommand and player.health.current == 100, "After moving the AI sniper does not shoot in the same turn")


func _run_content(suite: Node, fixture: Fixtures) -> void:
	var skills := fixture.skills()
	var document: Dictionary = skills.builtin_documents().get(String(SNIPER), {})
	var reread: Dictionary = SkillLibrary.normalized(JSON.parse_string(JSON.stringify(document)))
	suite.expect(not document.is_empty() and skills.validate(reread).is_empty() and skills.is_builtin_default(reread), "The built-in sniper passive survives a JSON round trip as its default document")
	var text := AbilityDescription.render_passive(PassiveAbilityCatalog.DEFINITIONS[SNIPER])
	suite.expect(text.contains("не тратил очки передвижения") and not "{" in text, "The sniper passive describes itself: %s" % text)
	var renamed := document.duplicate(true)
	renamed.name = "Другое имя"
	var definition: Dictionary = SkillLibrary.passive_definitions({renamed.id: renamed})[SNIPER]
	suite.expect(definition.get("sniper_shot", false) == true, "Renaming the sniper passive keeps its fixed effect")


## The attack button of a sniper: named a sniper shot until the unit moves.
func run_presentation(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var screen := preload("res://features/battle/battle_screen.tscn").instantiate() as BattleScreen
	suite.expect(screen.setup(fixture.spear_request()), "Sniper HUD battle setup accepted")
	suite.add_child(screen)
	var controller: BattleController = screen.get("_battle_controller")
	for _frame in range(600):
		await suite.get_tree().process_frame
		if not controller.get("_is_presenting"):
			break
	var session: BattleSession = controller.get("_battle_session")
	var presenter: ActiveUnitHudPresenter = controller.get("_active_unit_hud")
	var hud := screen.get_node("BattleMap/BattleUI") as BattleHUD
	var button := hud.get("_basic_attack_button") as Button
	var active := session.get_unit(session.get_active_unit_id())
	suite.expect(active != null and button != null, "The battle shows an active unit and its attack button")
	if active == null or button == null:
		screen.queue_free()
		return
	var opponent_hexes: Array[Vector2i] = []
	for opponent: UnitSnapshot in session.get_living_opponents(active.faction):
		opponent_hexes.append(opponent.hex)
	var engaged := BasicAttackRules.is_engaged(active.hex, opponent_hexes)
	# The shown snapshot stands for a sniper; the battle itself is not changed.
	active.basic_attack_range = 3
	active.sniper_shot = true
	active.turn.movement_spent = 0
	presenter.show(active)
	suite.expect(button.text == ("Атака" if engaged else "Снайперский выстрел"), "A sniper that has not moved names its attack a sniper shot: %s" % button.text)
	suite.expect(button.tooltip_text.contains("не перемещался"), "The sniper's attack button explains when the shot is lost")
	active.turn.movement_spent = 2
	presenter.show(active)
	suite.expect(button.text == "Атака", "After moving the sniper's button names the melee strike")
	active.sniper_shot = false
	presenter.show(active)
	suite.expect(button.text == ("Атака" if engaged else "Выстрел") and button.tooltip_text == button.text, "A shooter without the passive keeps its shot after moving")
	screen.queue_free()
	await suite.get_tree().process_frame


static func _create(ids: Array[StringName]) -> UnitState:
	var definition := UnitDefinition.new()
	definition.base_stats = UnitStatsDefinition.new()
	definition.base_stats.basic_attack_damage = 3
	definition.base_stats.basic_attack_range = 3
	definition.base_stats.movement_points = 4
	definition.passive_ability_ids.assign(ids)
	var spawn := UnitSpawnData.new(&"test:unit", &"test:placement", &"test:definition", definition, &"test:side", PLAYER, BattleControlSource.Value.PLAYER, &"", null, Vector2i.ZERO)
	return UnitStateFactory.create(spawn)


## A sniper with range 3 and attack 5.
static func _sniper(fixture: Fixtures, id: StringName, faction: BattleFaction.Value, hex: Vector2i, movement := 8) -> UnitState:
	var unit := fixture.unit(id, faction, hex, 100, movement)
	unit.basic_attack_range = 3
	unit.basic_attack_damage = 5
	unit.sniper_shot = true
	return unit


static func _target_ids(engine: BattleEngine, unit: UnitState) -> Array[StringName]:
	var ids: Array[StringName] = []
	for target: UnitState in engine.get_attackable_targets(unit.unit_id):
		ids.append(target.unit_id)
	return ids


static func _hit(events: Array[BattleEvent], target_id: StringName) -> UnitDamagedEvent:
	for event: BattleEvent in events:
		if event is UnitDamagedEvent and event.target_id == target_id:
			return event
	return null


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


static func _disk(radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		for r in range(maxi(-radius, -q - radius), mini(radius, radius - q) + 1):
			cells.append(Vector2i(q, r))
	return cells
