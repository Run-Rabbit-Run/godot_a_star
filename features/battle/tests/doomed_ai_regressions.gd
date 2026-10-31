extends RefCounted
## The doomed planner reuses and skips speculative actions; its plan must stay equal to an
## exhaustive search that runs every action from every reached position on its own fork.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")

const ACTOR_HEX := Vector2i(1, 2)
const STATES: Array[StringName] = [&"core:water", &"core:oil", &"core:fire", &"core:electricity", &"core:acid"]
## Seeds 56, 82, 95 and 99 place the actor in water that a shock would electrify.
const SEEDS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 56, 82, 95, 99]


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	_check_grid_copies(suite)
	_check_prediction_engines(suite, fixture)
	_check_skip_rules(suite, fixture)
	_check_random_scenarios(suite, fixture)
	_check_reaction_reaching_actor(suite, fixture)
	_check_simulation_budget(suite, fixture)


func _check_grid_copies(suite: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var cells: Array[Vector2i] = []
	for q in range(-6, 7):
		for r in range(-5, 6):
			if rng.randf() > 0.2:
				cells.append(Vector2i(q, r))
	var grid := HexGrid.new(cells)
	grid.set_hex_state(cells[3], &"core:fire")
	grid.set_traversal(cells[5], false, 2)
	grid.change_terrain(cells[6], &"core:sand")
	var obstacle := BattleObstacleDefinition.new()
	obstacle.id = &"rock"
	obstacle.hexes = [cells[8]]
	obstacle.destructible = true
	grid.add_obstacle(obstacle)
	var copy := grid.duplicate_grid()
	var same := copy.get_cells() == grid.get_cells()
	for cell: Vector2i in cells:
		same = same and copy.get_terrain_id(cell) == grid.get_terrain_id(cell) and copy.is_traversable(cell) == grid.is_traversable(cell) and copy.get_configured_movement_cost(cell) == grid.get_configured_movement_cost(cell) and copy.get_hex_state_id(cell) == grid.get_hex_state_id(cell) and copy.get_hex_state_turns(cell) == grid.get_hex_state_turns(cell) and copy.has_obstacle(cell) == grid.has_obstacle(cell)
	suite.expect(same, "Grid copy keeps cell order, terrain, traversal, costs, states and obstacles")
	copy.damage_obstacle(cells[8], 3)
	copy.set_hex_state(cells[4], &"core:water")
	suite.expect(grid.get_obstacle(cells[8]).current_hp == 10 and grid.get_hex_state_id(cells[4]).is_empty(), "Changing a grid copy leaves the original intact")
	var equal := true
	for center: Vector2i in cells:
		for radius in range(0, 5):
			var expected: Array[Vector2i] = []
			for cell: Vector2i in cells:
				if HexGrid.get_distance(center, cell) <= radius:
					expected.append(cell)
			var actual := grid.get_cells_in_range(center, radius)
			expected.sort()
			actual.sort()
			equal = equal and actual == expected
	suite.expect(equal, "Small-radius range enumeration returns exactly the cells a full scan finds, holes included")


func _check_prediction_engines(suite: Node, fixture: Fixtures) -> void:
	var cells: Array[Vector2i] = []
	for q in range(0, 5):
		cells.append(Vector2i(q, 0))
	var mover: UnitState = fixture.unit(&"mover", BattleFaction.Value.PLAYER, Vector2i.ZERO, 10, 3)
	var blast: AbilityDefinition = fixture.ability(&"core:blast", AbilityDefinition.TargetMode.HEX)
	mover.abilities[blast.id] = blast
	mover.ability_cooldowns[blast.id] = 0
	var enemy: UnitState = fixture.unit(&"enemy", BattleFaction.Value.ENEMY, Vector2i(4, 0))
	var state: BattleState = fixture.state(cells, [mover, enemy])
	state.turn_service.start()
	var live := BattleEngine.new(state, false)
	var forecast := live.fork_for_prediction()
	suite.expect(forecast.get_unit(mover.unit_id).get_ability(blast.id) == blast, "Forecast copies share read-only ability definitions")
	forecast.get_unit(mover.unit_id).ability_cooldowns[blast.id] = 3
	suite.expect(mover.ability_cooldowns[blast.id] == 0, "Forecast cooldowns stay detached from live state")
	var first := forecast.get_movement_search(mover.unit_id)
	suite.expect(forecast.fork_for_prediction().get_movement_search(mover.unit_id) == first, "A fork at the same revision reuses the forecast search")
	forecast.execute(MoveCommand.new(mover.unit_id, Vector2i(1, 0)))
	var after := forecast.get_movement_search(mover.unit_id)
	suite.expect(after != first and after.get_cost(Vector2i(3, 0)) == 2, "A command invalidates the forecast search")
	var before := live.get_movement_search(mover.unit_id)
	state.hex_grid.set_traversal(Vector2i(2, 0), false, 1)
	suite.expect(before.get_cost(Vector2i(3, 0)) == 3 and live.get_movement_search(mover.unit_id).get_cost(Vector2i(3, 0)) == -1, "The live engine never serves a stored search")


## Rare combinations that seeded maps do not reach: each skip must stay sound.
func _check_skip_rules(suite: Node, fixture: Fixtures) -> void:
	var cells: Array[Vector2i] = []
	for q in range(-3, 4):
		for r in range(-3, 4):
			cells.append(Vector2i(q, r))
	var actor: UnitState = fixture.unit(&"actor", BattleFaction.Value.ENEMY, Vector2i.ZERO)
	var ally: UnitState = fixture.unit(&"ally", BattleFaction.Value.ENEMY, Vector2i(-3, 3))
	var enemy: UnitState = fixture.unit(&"enemy", BattleFaction.Value.PLAYER, Vector2i(0, 1), 20)
	var punch: AbilityDefinition = fixture.ability(&"core:punch", AbilityDefinition.TargetMode.HEX, 1)
	var burn: AbilityDefinition = fixture.ability(&"core:burn", AbilityDefinition.TargetMode.HEX, 1)
	burn.effects[0].parameters = {"amount": 3, "damage_type": "fire"}
	var field: AbilityDefinition = fixture.ability(&"core:field", AbilityDefinition.TargetMode.HEX)
	field.effects[0].effect_type_id = &"core:hex_state"
	field.effects[0].parameters = {"state_id": "core:fire"}
	var sweep: AbilityDefinition = fixture.ability(&"core:sweep", AbilityDefinition.TargetMode.SELF, 1)
	sweep.range = 1
	sweep.melee_attack = true
	for ability: AbilityDefinition in [punch, burn, field, sweep]:
		actor.abilities[ability.id] = ability
		actor.ability_cooldowns[ability.id] = 0
	var state: BattleState = fixture.state(cells, [actor, ally, enemy])
	state.turn_service.start()
	var position := BattleEngine.new(state, false)
	var grid := state.hex_grid
	var own: Dictionary[Vector2i, UnitState] = {ally.hex: ally}
	var memo := {"outcomes": {}, "reach": {}, "simulations": 0, "skipped": 0}
	suite.expect(AILastActionPlanner._misses_opponents(punch, actor, grid, own, Vector2i(3, -3), memo), "Skip: an area without units")
	suite.expect(AILastActionPlanner._misses_opponents(punch, actor, grid, own, ally.hex, memo), "Skip: a physical hit on an own unit")
	suite.expect(not AILastActionPlanner._misses_opponents(burn, actor, grid, own, ally.hex, {"outcomes": {}, "reach": {}}), "Evaluate: an elemental hit on an own unit may start a reaction")
	suite.expect(not AILastActionPlanner._misses_opponents(sweep, actor, grid, {Vector2i(1, 0): ally} as Dictionary[Vector2i, UnitState], actor.hex, memo), "Evaluate: a melee hit on an own unit lets it retaliate with its damage type")
	suite.expect(not AILastActionPlanner._misses_opponents(field, actor, grid, own, Vector2i(3, -3), memo), "Evaluate: terrain effects in an empty area may spread")
	var others: Dictionary[Vector2i, UnitState] = {ally.hex: ally, enemy.hex: enemy}
	var best := {"enemy_damage": 5, "cost": 0}
	var outcomes := [[punch, Vector2i(0, 1)], [burn, Vector2i(0, 1)], [sweep, actor.hex]]
	for entry: Array in outcomes:
		var ability: AbilityDefinition = entry[0]
		var area := AbilityExecutor.get_affected_hexes(grid, actor.hex, ability, entry[1])
		var changed: Dictionary[Vector2i, bool] = {}
		memo.outcomes[AILastActionPlanner._outcome_key(ability, grid, others, area, entry[1])] = {"enemy_damage": 1, "friendly_damage": 0, "changed": changed}
	var physical := AILastActionPlanner._score(position, actor, grid, others, UseAbilityCommand.at_hex(actor.unit_id, Vector2i(0, 1), punch.id), 0, best, memo)
	suite.expect(physical.get("skipped", "") == "cannot_improve_plan" and memo.simulations == 0, "A physical hit on the actor cannot raise opponent damage above the stored outcome")
	var elemental := AILastActionPlanner._score(position, actor, grid, others, UseAbilityCommand.at_hex(actor.unit_id, Vector2i(0, 1), burn.id), 0, best, memo)
	suite.expect(not elemental.has("skipped") and memo.simulations == 1, "An elemental hit on the actor is simulated: its own hex may react")
	var melee := AILastActionPlanner._score(position, actor, grid, others, UseAbilityCommand.at_hex(actor.unit_id, actor.hex, sweep.id), 0, best, memo)
	suite.expect(not melee.has("reused") and memo.simulations == 2 and melee.enemy_damage == 3, "A melee ability is always simulated because retaliation depends on adjacency")


## Small seeded maps with hazards, reactions, armor, retaliation, allies and obstacles.
func _check_random_scenarios(suite: Node, fixture: Fixtures) -> void:
	var equal := 0
	var maximum_damage := 0
	var reused := 0
	var skipped := 0
	var dominated := 0
	var mismatches: Array[String] = []
	for seed: int in SEEDS:
		var session := _session(_scenario(fixture, seed))
		var before := JSON.stringify(BattleLogSerializer.encode(session.get_diagnostic_state()))
		var trace := {}
		var plan := AILastActionPlanner.plan(session, trace)
		var reference := _exhaustive_plan(session)
		if _summary(plan) == _summary(reference) and before == JSON.stringify(BattleLogSerializer.encode(session.get_diagnostic_state())):
			equal += 1
		else:
			mismatches.append("seed %d: %s != %s" % [seed, _summary(plan), _summary(reference)])
		if plan.get("reason", "") == "doomed_maximum_damage":
			maximum_damage += 1
		if trace.has("last_action"):
			skipped += trace.last_action.skipped_without_opponents
			for candidate: Dictionary in trace.last_action.candidates:
				for record: Dictionary in candidate.actions:
					reused += int(record.has("reused"))
					dominated += int(record.get("skipped", "") == "cannot_improve_plan")
	suite.expect(equal == SEEDS.size(), "Pruned doomed planner equals exhaustive search on every seeded map: %s" % ", ".join(mismatches))
	suite.expect(maximum_damage >= SEEDS.size() / 2, "Seeded maps mostly end in maximum-damage plans (%d)" % maximum_damage)
	suite.expect(reused > 0 and skipped > 0 and dominated > 0, "Seeded maps exercise reuse, empty-area skips and dominated actor hits (%d/%d/%d)" % [reused, skipped, dominated])


## Electricity spreads through one water body: from inside it the actor would shock itself.
func _check_reaction_reaching_actor(suite: Node, fixture: Fixtures) -> void:
	var cells: Array[Vector2i] = []
	for q in range(0, 8):
		for r in range(0, 3):
			cells.append(Vector2i(q, r))
	var actor: UnitState = fixture.unit(&"doomed", BattleFaction.Value.ENEMY, Vector2i(1, 1), 1, 2)
	actor.statuses[&"core:electrified"] = 2
	var field: AbilityDefinition = fixture.ability(&"core:shock_field", AbilityDefinition.TargetMode.HEX)
	field.range = 3
	field.effects[0].effect_type_id = &"core:hex_state"
	field.effects[0].parameters = {"state_id": "core:electricity"}
	actor.abilities[field.id] = field
	actor.ability_cooldowns[field.id] = 0
	var target: UnitState = fixture.unit(&"target", BattleFaction.Value.PLAYER, Vector2i(7, 1), 20)
	var state: BattleState = fixture.state(cells, [actor, target])
	for q in range(2, 8):
		state.hex_grid.set_hex_state(Vector2i(q, 0), &"core:water")
	state.hex_grid.set_hex_state(Vector2i(7, 1), &"core:water")
	var session := _session(state)
	var trace := {}
	var plan := AILastActionPlanner.plan(session, trace)
	var reused_outside := 0
	var shocks_from_water := 0
	var reused_in_water := 0
	for candidate: Dictionary in trace.last_action.candidates:
		var in_water := state.hex_grid.get_hex_state_id(candidate.reached_hex) == &"core:water"
		for record: Dictionary in candidate.actions:
			if not record.command is UseAbilityCommand or state.hex_grid.get_hex_state_id(record.command.target_hex) != &"core:water":
				continue
			if in_water:
				shocks_from_water += 1
				reused_in_water += int(record.has("reused"))
			else:
				reused_outside += int(record.has("reused"))
	suite.expect(_summary(plan) == _summary(_exhaustive_plan(session)), "Distant shock through connected water matches exhaustive search")
	suite.expect(plan.get("reason", "") == "doomed_maximum_damage" and state.hex_grid.get_hex_state_id(plan.get("hex", Vector2i.ZERO)) != &"core:water", "Doomed actor shocks the distant target from outside the water")
	suite.expect(reused_outside > 0 and shocks_from_water > 0 and reused_in_water == 0, "Shocking connected water is simulated again from inside it (%d/%d/%d)" % [reused_outside, shocks_from_water, reused_in_water])


## The realistic case that froze the battle for six seconds: 18×12 map, grenade and spear throw.
func _check_simulation_budget(suite: Node, fixture: Fixtures) -> void:
	var cells: Array[Vector2i] = []
	for r in range(12):
		for column in range(18):
			cells.append(Vector2i(column - (r >> 1), r))
	var actor: UnitState = fixture.unit(&"doomed", BattleFaction.Value.ENEMY, Vector2i(4, 6), 1, 4)
	actor.statuses[&"core:electrified"] = 4
	var grenade: AbilityDefinition = fixture.ability(&"core:grenade_test", AbilityDefinition.TargetMode.HEX, 1)
	grenade.range = 3
	var throw: AbilityDefinition = fixture.ability(&"core:throw_test", AbilityDefinition.TargetMode.PATH)
	throw.range = 4
	for ability: AbilityDefinition in [grenade, throw]:
		actor.abilities[ability.id] = ability
		actor.ability_cooldowns[ability.id] = 0
	var units: Array[UnitState] = [actor]
	for index in range(6):
		units.append(fixture.unit(StringName("p%d" % index), BattleFaction.Value.PLAYER, Vector2i(6 + index, 3 + index % 3), 20))
	var trace := {}
	var plan := AILastActionPlanner.plan(_session(fixture.state(cells, units)), trace)
	# Every action from every position would take about 6000 forecast forks.
	suite.expect(plan.get("reason", "") == "doomed_maximum_damage" and plan.enemy_damage == 9 and trace.last_action.simulations <= 150, "Realistic doomed plan needs few forecast simulations (%d)" % trace.last_action.simulations)


func _session(state: BattleState) -> BattleSession:
	state.turn_service.start()
	var setup := BattleSetup.new(state.battle_id, state.hex_grid, [], [], BattleObjectiveDefinition.new(), BattleFaction.Value.PLAYER, state.deterministic_seed)
	return BattleSession.new(setup, state, BattleEngine.new(state, false), null)


func _scenario(fixture: Fixtures, seed: int) -> BattleState:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var cells: Array[Vector2i] = []
	for r in range(5):
		for column in range(6):
			var hex := Vector2i(column - (r >> 1), r)
			if hex == ACTOR_HEX or rng.randf() > 0.08:
				cells.append(hex)
	var free := cells.duplicate()
	free.erase(ACTOR_HEX)
	for index in range(free.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var swap: Vector2i = free[index]
		free[index] = free[other]
		free[other] = swap
	var actor: UnitState = fixture.unit(&"doomed", BattleFaction.Value.ENEMY, ACTOR_HEX, 1, rng.randi_range(2, 3))
	actor.statuses[&"core:electrified"] = 3
	actor.basic_attack_damage = rng.randi_range(1, 4)
	actor.basic_attack_range = rng.randi_range(1, 2)
	actor.basic_attack_damage_type = [&"physical", &"fire", &"electric"][rng.randi_range(0, 2)]
	var pool := _ability_pool(fixture)
	for index in range(rng.randi_range(2, 3)):
		var ability: AbilityDefinition = pool[rng.randi_range(0, pool.size() - 1)]
		actor.abilities[ability.id] = ability
		actor.ability_cooldowns[ability.id] = 0
	var units: Array[UnitState] = [actor]
	var opponents := rng.randi_range(2, 4)
	for index in range(opponents + rng.randi_range(0, 2)):
		var faction := BattleFaction.Value.PLAYER if index < opponents else BattleFaction.Value.ENEMY
		var unit: UnitState = fixture.unit(StringName("u%d" % index), faction, free.pop_back(), rng.randi_range(2, 8))
		unit.basic_attack_damage_type = [&"physical", &"fire", &"electric"][rng.randi_range(0, 2)]
		if rng.randf() < 0.4:
			unit.melee_retaliation = true
			unit.retaliation_configured = true
		for status: StringName in [&"core:armor", &"core:wet", &"core:sticky_oil"]:
			if rng.randf() < 0.25:
				unit.statuses[status] = rng.randi_range(1, 2)
		units.append(unit)
	var state: BattleState = fixture.state(cells, units)
	for hex: Vector2i in cells:
		if rng.randf() < 0.35:
			state.hex_grid.set_hex_state(hex, STATES[rng.randi_range(0, STATES.size() - 1)])
	if rng.randf() < 0.5:
		for hex: Vector2i in free:
			if state.hex_grid.get_hex_state_id(hex).is_empty():
				var obstacle := BattleObstacleDefinition.new()
				obstacle.id = &"rock"
				obstacle.hexes = [hex]
				obstacle.destructible = true
				obstacle.max_hp = rng.randi_range(1, 4)
				state.hex_grid.add_obstacle(obstacle)
				break
	return state


func _ability_pool(fixture: Fixtures) -> Array[AbilityDefinition]:
	var grenade := fixture.ability(&"core:pool_grenade", AbilityDefinition.TargetMode.HEX, 1)
	grenade.range = 3
	grenade.effects[0].parameters = {"amount": 3, "secondary_amount": 2}
	var fireball := fixture.ability(&"core:pool_fireball", AbilityDefinition.TargetMode.HEX, 1)
	fireball.range = 2
	fireball.effects[0].parameters = {"amount": 2, "damage_type": "fire"}
	var field := fixture.ability(&"core:pool_field", AbilityDefinition.TargetMode.HEX, 1)
	field.range = 3
	field.effects[0].effect_type_id = &"core:hex_state"
	field.effects[0].parameters = {"state_id": "core:electricity"}
	var spear := fixture.ability(&"core:pool_spear", AbilityDefinition.TargetMode.PATH)
	spear.range = 3
	var beam := fixture.ability(&"core:pool_beam", AbilityDefinition.TargetMode.LINE)
	beam.range = 4
	beam.effects[0].parameters = {"amount": 2, "damage_type": "electric"}
	var sweep := fixture.ability(&"core:pool_sweep", AbilityDefinition.TargetMode.SELF, 1)
	sweep.range = 1
	sweep.melee_attack = true
	sweep.effects[0].parameters = {"amount": 2}
	var brand := fixture.ability(&"core:pool_brand", AbilityDefinition.TargetMode.ENEMY)
	brand.range = 2
	brand.effects[0].parameters = {"amount": 1}
	var burning := AbilityEffectDefinition.new()
	burning.effect_type_id = &"core:unit_status"
	burning.parameters = {"status_id": &"core:burning", "levels": 1}
	brand.effects.append(burning)
	var splash := fixture.ability(&"core:pool_splash", AbilityDefinition.TargetMode.HEX, 1)
	splash.range = 2
	splash.effects[0].parameters = {"amount": 1, "damage_type": "water"}
	var water := AbilityEffectDefinition.new()
	water.effect_type_id = &"core:hex_state"
	water.parameters = {"state_id": "core:water"}
	splash.effects.append(water)
	return [grenade, fireball, field, spear, beam, sweep, brand, splash]


func _summary(plan: Dictionary) -> String:
	if plan.is_empty():
		return "{}"
	return JSON.stringify(BattleLogSerializer.encode({"reason": plan.reason, "command": plan.command, "followup": plan.get("followup_command"), "damage": plan.get("enemy_damage", 0)}))


## The planner before reuse and skipping: every action from every reached position runs
## on its own fork. Kept as the specification the optimized search must reproduce.
func _exhaustive_plan(session: BattleSession) -> Dictionary:
	var active := session.get_unit(session.get_active_unit_id())
	var grid := session.get_hex_grid()
	if not MovementImpactForecast.evaluate(active, grid, [active.hex]).lethal:
		return {}
	var search := session.get_movement_search(active.unit_id)
	var cells := search.get_reachable_cells()
	cells.sort()
	for cell: Vector2i in cells:
		var forecast := MovementImpactForecast.evaluate(active, grid, search.build_path(cell))
		if forecast.reached and not forecast.lethal:
			return {}
	var base := session.create_prediction_engine()
	var opponents := session.get_living_opponents(active.faction)
	var approach_costs: Array[Dictionary] = []
	for opponent: UnitSnapshot in opponents:
		approach_costs.append(EnemyBrain.get_approach_costs(grid, opponent.hex, active.basic_attack_range))
	var start_approach := AILastActionPlanner._approach(active.hex, opponents, approach_costs)
	var best: Dictionary = {}
	var advance: Dictionary = {}
	if not cells.has(active.hex):
		cells.append(active.hex)
		cells.sort()
	for cell: Vector2i in cells:
		var position := base.fork_for_prediction()
		var move: MoveCommand
		if cell != active.hex:
			move = MoveCommand.new(active.unit_id, cell)
			var moved := position.execute(move)
			if not moved.accepted or not moved.terminal_error.is_empty():
				continue
		var actor := position.get_unit(active.unit_id)
		var cost := search.get_cost(cell)
		var approach := AILastActionPlanner._approach(actor.hex, opponents, approach_costs)
		if move != null and actor.hex != active.hex and approach < start_approach:
			var entry := {"command": move, "approach": approach, "alive": not actor.health.is_defeated(), "cost": cost}
			if advance.is_empty() or AILastActionPlanner._better_advance(entry, advance):
				advance = entry
		if actor.health.is_defeated() or position.get_active_unit_id() != active.unit_id or actor.statuses.get(&"core:paralysis", 0) > 0 or not actor.turn.main_action_available:
			continue
		for command: BattleCommand in _all_actions(position, actor):
			var resolution := position.fork_for_prediction().execute(command)
			if not resolution.accepted or not resolution.terminal_error.is_empty():
				continue
			var enemy_damage := 0
			var friendly_damage := 0
			for event: BattleEvent in resolution.events:
				if event is TurnEndedEvent:
					break
				if event is UnitDamagedEvent:
					var victim := position.get_unit(event.target_id)
					if victim == null:
						continue
					if victim.faction != active.faction:
						enemy_damage += event.damage
					elif victim.unit_id != active.unit_id or event.source_status_id.is_empty():
						friendly_damage += event.damage
			if enemy_damage <= 0 or friendly_damage > 0:
				continue
			if best.is_empty() or enemy_damage > best.enemy_damage or (enemy_damage == best.enemy_damage and cost < best.cost):
				best = {"command": command if move == null else move, "followup_command": command, "enemy_damage": enemy_damage, "cost": cost}
	if not best.is_empty():
		best["reason"] = "doomed_maximum_damage"
		return best
	if not advance.is_empty():
		advance["reason"] = "doomed_advance_toward_enemy"
		return advance
	return {"command": EndTurnCommand.new(active.unit_id), "reason": "doomed_no_reachable_progress"}


func _all_actions(engine: BattleEngine, actor: UnitState) -> Array[BattleCommand]:
	var commands: Array[BattleCommand] = []
	for target: UnitState in engine.get_attackable_targets(actor.unit_id):
		commands.append(AttackCommand.new(actor.unit_id, target.unit_id))
	var ids: Array = actor.abilities.keys()
	ids.sort()
	for id: StringName in ids:
		var ability := actor.get_ability(id)
		if not AILastActionPlanner._supports_prediction(ability) or not engine.supports_ability_prediction(ability):
			continue
		var directions: Dictionary = {}
		for hex: Vector2i in engine.get_ability_target_hexes(actor.unit_id, id):
			if ability.targets_hex():
				if ability.target_mode == AbilityDefinition.TargetMode.LINE:
					var direction := AbilityExecutor.get_line_direction(actor.hex, hex)
					if directions.has(direction):
						continue
					directions[direction] = true
				commands.append(UseAbilityCommand.at_hex(actor.unit_id, hex, id))
			else:
				var target := engine.get_unit_at(hex)
				if target != null:
					commands.append(UseAbilityCommand.new(actor.unit_id, target.unit_id, id))
	return commands
