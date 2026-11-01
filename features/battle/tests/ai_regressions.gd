extends RefCounted
## Battle AI: action choice and forecasts, the plan of a doomed unit.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")


func run_ai_and_forecast(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var request := fixture.request()
	if request == null:
		return
	var session := BattleSessionFactory.create(request).session
	var copied_setup := session.setup
	copied_setup.unit_spawns.clear()
	copied_setup.sides[0].side_id = &"changed"
	suite.expect(not session.setup.unit_spawns.is_empty() and session.setup.sides[0].side_id != &"changed", "Session setup does not expose internal spawns or sides")
	var active := session.get_unit(session.get_active_unit_id())
	var opponent := session.get_living_opponents(active.faction)[0]
	var ability := fixture.ability(&"core:hex_only", AbilityDefinition.TargetMode.HEX)
	ability.range = 99
	# Synthetic query snapshot isolates the previously wrong command constructor.
	var state: BattleState = session.get("_state")
	state.unit_states[active.unit_id].abilities[ability.id] = ability
	active.ability_ids = [ability.id]
	active.abilities[ability.id] = AbilitySnapshot.new(ability, state.unit_states[active.unit_id])
	var source := AICommandSource.new(load("res://features/battle/definitions/debug_basic_enemy_ai.tres"))
	var command := source._choose_ability_command(session, active, [opponent])
	suite.expect(command is UseAbilityCommand and command.targets_hex, "AI emits hex command for zero-radius HEX ability")
	if command != null:
		suite.expect(session.step(command).accepted, "Engine accepts AI zero-radius hex command")
	var p := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO, 2)
	p.statuses[&"core:wet"] = 6
	var grid := HexGrid.new([Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)])
	grid.set_hex_state(Vector2i(1, 0), &"core:electricity")
	var forecast := MovementImpactForecast.evaluate(UnitSnapshot.new(p), grid, [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)])
	suite.expect(forecast.lethal and not forecast.reached, "Forecast sees wet lethal electric crossing")
	suite.expect(p.health.current == 2 and p.statuses[&"core:wet"] == 6, "Forecast does not mutate actual unit")
	p = fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO, 100, 3)
	grid.set_hex_state(Vector2i(1, 0), &"core:oil")
	forecast = MovementImpactForecast.evaluate(UnitSnapshot.new(p), grid, [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)])
	suite.expect(not forecast.reached, "Forecast sees oil shortening route")
	p = fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO, 1, 1)
	p.status_immunities.append(&"core:burning")
	p.statuses[&"core:wet"] = 4
	grid.set_hex_state(Vector2i(1, 0), &"core:fire")
	var search := MovementService.search(grid, p.hex, 1, {})
	var chosen := EnemyBrain.choose_move(p.unit_id, p.hex, Vector2i(2, 0), search, grid, 1, 1, UnitSnapshot.new(p))
	suite.expect(chosen != null and chosen.destination == Vector2i(1, 0), "AI accepts fire crossing protected by wet and burning immunity")


func run_doomed_ai(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]
	var enemy := fixture.unit(&"doomed", BattleFaction.Value.ENEMY, Vector2i.ZERO, 1, 3)
	enemy.statuses[&"core:electrified"] = 4
	var player := fixture.unit(&"player", BattleFaction.Value.PLAYER, Vector2i(3, 0), 20)
	var session := fixture.ai_session(fixture.state(cells, [enemy, player]))
	var source := AICommandSource.new(null)
	source.decision_trace = {}
	var before := JSON.stringify(BattleLogSerializer.encode(session.get_diagnostic_state()))
	var command := source.next_command(session)
	suite.expect(command is MoveCommand and command.destination == Vector2i(2, 0), "Doomed unit moves into attack range before end-of-turn death")
	suite.expect(source.decision_trace.reason == "doomed_maximum_damage", "Doomed damage plan is explained in AI trace")
	suite.expect(before == JSON.stringify(BattleLogSerializer.encode(session.get_diagnostic_state())), "Speculative actions do not mutate live units, map, turns, revisions or RNG")
	suite.expect(session.step(command).accepted and enemy.health.current == 1, "Doomed movement survives until action")
	command = source.next_command(session)
	suite.expect(command is AttackCommand and command.target_id == player.unit_id, "Doomed unit attacks after approaching")
	var resolution := session.step(command)
	suite.expect(resolution.accepted and player.health.current == 18 and enemy.health.is_defeated(), "Attack damages opponent before actor dies at end of turn")

	# Maximize actual HP removed, even if a nearer target is already attackable.
	enemy = fixture.unit(&"doomed", BattleFaction.Value.ENEMY, Vector2i.ZERO, 1, 4)
	enemy.basic_attack_damage = 7
	enemy.statuses[&"core:electrified"] = 4
	var armored := fixture.unit(&"armor", BattleFaction.Value.PLAYER, Vector2i(1, 0), 20)
	armored.statuses[&"core:armor"] = 6
	player = fixture.unit(&"player", BattleFaction.Value.PLAYER, Vector2i(3, 0), 20)
	var detour: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 0), Vector2i(3, 0)]
	session = fixture.ai_session(fixture.state(detour, [enemy, armored, player]))
	var plan := AILastActionPlanner.plan(session)
	suite.expect(plan.command is MoveCommand and plan.enemy_damage == 7 and plan.followup_command is AttackCommand and plan.followup_command.target_id == player.unit_id, "Doomed AI prefers 7 damage after movement over 1 damage to adjacent armor")

	# Abilities compete with ordinary attacks using the real executor and cooldown legality.
	var blast := fixture.ability(&"core:last_blast", AbilityDefinition.TargetMode.HEX, 0)
	blast.effects[0].parameters.amount = 9
	enemy.abilities[blast.id] = blast
	enemy.ability_cooldowns[blast.id] = 0
	plan = AILastActionPlanner.plan(session)
	suite.expect(plan.command is UseAbilityCommand and plan.enemy_damage == 9, "Doomed AI chooses a damaging ability over weaker ordinary attack")
	enemy.ability_cooldowns[blast.id] = 2
	plan = AILastActionPlanner.plan(session)
	suite.expect(plan.enemy_damage == 7 and plan.followup_command is AttackCommand, "Last-action planner respects ability cooldown")
	enemy.ability_cooldowns[blast.id] = 0
	enemy.abilities.erase(blast.id)
	var ignition := fixture.ability(&"core:ignite_oil", AbilityDefinition.TargetMode.HEX)
	ignition.effects[0].effect_type_id = &"core:unit_status"
	ignition.effects[0].parameters = {"status_id": &"core:burning", "levels": 1}
	enemy.abilities[ignition.id] = ignition
	player.statuses[&"core:sticky_oil"] = 9
	plan = AILastActionPlanner.plan(session)
	suite.expect(plan.command is UseAbilityCommand and plan.enemy_damage == 10, "Status-only ignition competes via real immediate oil explosion damage")
	player.statuses.clear()
	enemy.abilities.erase(ignition.id)
	blast.area_radius = 10
	enemy.abilities[blast.id] = blast
	var ally := fixture.unit(&"ally", BattleFaction.Value.ENEMY, Vector2i(3, -1), 20)
	session.get("_state").unit_states[ally.unit_id] = ally
	session.get("_state").hex_grid.add_cell(ally.hex, &"core:default", 1, true)
	plan = AILastActionPlanner.plan(session)
	suite.expect(plan.followup_command is AttackCommand, "Doomed planner rejects stronger area attack hitting a living ally")
	enemy.abilities.erase(blast.id)

	# No action is in reach: advance instead of dying in place.
	enemy = fixture.unit(&"doomed", BattleFaction.Value.ENEMY, Vector2i.ZERO, 1, 1)
	enemy.statuses[&"core:electrified"] = 4
	player = fixture.unit(&"player", BattleFaction.Value.PLAYER, Vector2i(4, 0), 20)
	session = fixture.ai_session(fixture.state(cells, [enemy, player]))
	plan = AILastActionPlanner.plan(session)
	suite.expect(plan.command is MoveCommand and plan.command.destination == Vector2i(1, 0) and plan.reason == "doomed_advance_toward_enemy", "Doomed AI advances when no damage can be dealt this turn")
	suite.expect(session.step(plan.command).accepted, "Desperate approach is a legal command")

	# A safe option keeps normal survival policy, while route death cannot promise an attack.
	enemy.statuses.clear()
	suite.expect(AILastActionPlanner.plan(session).is_empty(), "Living unit does not enter desperate policy")
	enemy.statuses[&"core:electrified"] = 4
	var state: BattleState = session.get("_state")
	state.hex_grid.set_hex_state(Vector2i(2, 0), &"core:fire")
	plan = AILastActionPlanner.plan(session)
	suite.expect(plan.command is EndTurnCommand, "No movement is issued when no reachable progress remains")

	# A lethal crossing is excluded from maximum-damage plans.
	enemy = fixture.unit(&"doomed", BattleFaction.Value.ENEMY, Vector2i.ZERO, 1, 3)
	enemy.statuses[&"core:electrified"] = 2
	player = fixture.unit(&"player", BattleFaction.Value.PLAYER, Vector2i(3, 0), 20)
	state = fixture.state(cells, [enemy, player])
	state.hex_grid.set_hex_state(Vector2i(1, 0), &"core:acid")
	session = fixture.ai_session(state)
	plan = AILastActionPlanner.plan(session)
	suite.expect(plan.reason != "doomed_maximum_damage", "Unit dying on route is never scored as reaching an attack")
	var predicted := session.create_prediction_engine()
	predicted.get_unit(enemy.unit_id).statuses.clear()
	predicted.get_unit(enemy.unit_id).abilities.clear()
	suite.expect(enemy.statuses.get(&"core:electrified", 0) == 2, "Forecast runtime collections are independent")

	# A fire victim can save itself in water: desperate mode must not override that option.
	enemy = fixture.unit(&"doomed", BattleFaction.Value.ENEMY, Vector2i.ZERO, 1, 1)
	enemy.statuses[&"core:burning"] = 2
	player = fixture.unit(&"player", BattleFaction.Value.PLAYER, Vector2i(4, 0), 20)
	state = fixture.state(cells, [enemy, player])
	state.hex_grid.set_hex_state(Vector2i(1, 0), &"core:water")
	session = fixture.ai_session(state)
	suite.expect(AILastActionPlanner.plan(session).is_empty(), "Reachable water survival preserves ordinary safe movement policy")
	command = source.next_command(session)
	suite.expect(command is MoveCommand and command.destination == Vector2i(1, 0), "Normal policy uses the safe water route")

	# Reuse record 43 geometry/statuses with 1 HP to retain lethal fixed-damage coverage.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://features/battle/tests/fixtures/chudishcherog_doomed_state.json"))
	var participants: Dictionary[StringName, UnitState] = {}
	var order: Array[StringName] = []
	var map_cells: Array[Vector2i] = []
	for cell: Dictionary in data.grid.cells:
		map_cells.append(Vector2i(int(cell.hex.x), int(cell.hex.y)))
	for unit: Dictionary in data.units:
		var value := fixture.unit(StringName(unit.unit_id), int(unit.faction) as BattleFaction.Value, Vector2i(int(unit.hex.x), int(unit.hex.y)), int(unit.health.maximum), int(unit.turn.movement_max))
		value.health.current = int(unit.health.current)
		value.turn.movement_remaining = int(unit.turn.movement_remaining)
		value.turn.main_action_available = bool(unit.turn.main_action_available)
		value.turns_started = int(unit.turns_started)
		value.basic_attack_damage = int(unit.basic_attack_damage)
		value.basic_attack_range = int(unit.basic_attack_range)
		value.basic_attack_damage_type = StringName(unit.basic_attack_damage_type)
		for id: String in unit.statuses:
			value.statuses[StringName(id)] = int(unit.statuses[id])
		for id: String in unit.basic_attack_statuses:
			value.basic_attack_statuses[StringName(id)] = int(unit.basic_attack_statuses[id])
		for id: String in unit.status_immunities:
			value.status_immunities.append(StringName(id))
		participants[value.unit_id] = value
	for id: String in data.turn_order:
		order.append(StringName(id))
	state = BattleState.new(&"core:logged_doom", HexGrid.new(map_cells), participants, order, ObjectiveSystem.new(EliminateFactionObjective.new(BattleFaction.Value.ENEMY, "Defeat enemies"), BattleFaction.Value.PLAYER), 1)
	for cell: Dictionary in data.grid.cells:
		var hex := Vector2i(int(cell.hex.x), int(cell.hex.y))
		state.hex_grid.set_hex_state(hex, StringName(cell.state_id))
		state.hex_grid.set_traversal(hex, bool(cell.traversable), int(cell.movement_cost))
	session = fixture.ai_session(state)
	while state.turn_service.get_round_number() != int(data.round) or state.turn_service.get_active_unit_id() != StringName(data.active_unit_id):
		state.turn_service.advance_turn()
	state.random.state = int(data.rng_state)
	participants[StringName(data.active_unit_id)].health.current = 1
	source.decision_trace = {}
	command = source.next_command(session)
	suite.expect(command is MoveCommand and source.decision_trace.reason == "doomed_maximum_damage", "Recorded Chudishcherog state now produces a last attack approach instead of EndTurn")
	suite.expect(session.step(command).accepted, "Recorded last attack approach executes legally")
	command = source.next_command(session)
	suite.expect(command is AttackCommand and command.target_id == &"plateau:battle:author:placement_1", "Recorded Chudishcherog reaches Tesla for an attack")
	resolution = session.step(command)
	suite.expect(resolution.accepted and participants[&"plateau:battle:author:placement_1"].health.current == 0, "Recorded Chudishcherog deals remaining 3 HP of damage to Tesla before dying")
	suite.expect(participants[&"plateau:battle:author:placement_4"].health.is_defeated(), "Recorded Chudishcherog still obeys lethal end-of-turn status rules")
