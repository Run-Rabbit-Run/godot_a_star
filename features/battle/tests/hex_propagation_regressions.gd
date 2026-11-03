extends RefCounted
## Hex state propagation that never settles is a rules defect. It must never leave a
## half-updated map: the batch is rejected whole, and whoever owns the larger operation
## either discards it (ability, external batch) or stops the battle (landed hit, start).
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")

## Water spreading into water "converts" it forever: the smallest table that cannot settle.
const NEVER_SETTLES := {&"core:water": {&"core:water": &"core:water"}}
const DEFECT := "did not settle"


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	_check_catalog_is_acyclic(suite)
	_check_propagation_reports_defect(suite)
	_check_external_batch(suite, fixture)
	_check_ability(suite, fixture)
	_check_landed_hit(suite, fixture)
	_check_retaliation(suite, fixture)
	_check_battle_start(suite, fixture)


## Each conversion moves a cell along base -> result; without a cycle a cell converts at
## most once per state, which is exactly the bound propagation enforces.
func _check_catalog_is_acyclic(suite: Node) -> void:
	var edges: Dictionary = {}
	for spreading: StringName in HexStateCatalog.PROPAGATION:
		var rules: Dictionary = HexStateCatalog.PROPAGATION[spreading]
		for base: StringName in rules:
			var targets: Array = edges.get(base, [])
			targets.append(rules[base])
			edges[base] = targets
	var cycle := ""
	for start: StringName in edges:
		var stack: Array = [[start, [start]]]
		while not stack.is_empty() and cycle.is_empty():
			var entry: Array = stack.pop_back()
			for next: StringName in edges.get(entry[0], []):
				if next in entry[1]:
					cycle = str(entry[1] + [next])
					break
				stack.append([next, entry[1] + [next]])
	suite.expect(cycle.is_empty(), "Built-in hex state propagation has no conversion cycle: %s" % cycle)
	for spreading: StringName in HexStateCatalog.PROPAGATION:
		for base: StringName in HexStateCatalog.PROPAGATION[spreading]:
			suite.expect(HexStateCatalog.has_state(base) and HexStateCatalog.has_state(HexStateCatalog.PROPAGATION[spreading][base]), "Propagation of %s uses known states" % spreading)


func _check_propagation_reports_defect(suite: Node) -> void:
	var grid := HexGrid.new([Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)])
	for hex: Vector2i in grid.get_cells():
		grid.set_hex_state(hex, &"core:water")
	var events: Array[BattleEvent] = []
	var seeds: Array[Vector2i] = [Vector2i.ZERO]
	var error := HexStateService.propagate(grid, seeds, events, NEVER_SETTLES)
	suite.expect(DEFECT in error, "Propagation that never settles reports the defect instead of logging it")
	suite.expect(events.size() <= grid.get_cells().size() * HexStateCatalog.RULES.size(), "A defective table stops within the conversion bound")
	events.clear()
	suite.expect(HexStateService.propagate(grid, seeds, events).is_empty(), "The built-in table settles on the same map")


func _check_external_batch(suite: Node, fixture: Fixtures) -> void:
	var state := _pool_state(fixture)
	var engine := _engine(state)
	var before := _fingerprint(state)
	var resolution := engine.apply_map_mutations([MapMutation.apply_hex_state(Vector2i(1, 0), &"core:water")])
	suite.expect(not resolution.accepted and DEFECT in resolution.rejection_reason and resolution.terminal_error.is_empty(), "An external batch that never settles is rejected")
	suite.expect(_fingerprint(state) == before and engine.execute(EndTurnCommand.new(&"user")).accepted, "A rejected batch leaves the map untouched and the battle playable")


func _check_ability(suite: Node, fixture: Fixtures) -> void:
	var state := _pool_state(fixture)
	var user: UnitState = state.unit_states[&"user"]
	var flood: AbilityDefinition = fixture.ability(&"core:flood", AbilityDefinition.TargetMode.HEX)
	flood.range = 4
	flood.effects[0].effect_type_id = &"core:hex_state"
	flood.effects[0].parameters = {"state_id": "core:water"}
	user.abilities[flood.id] = flood
	user.ability_cooldowns[flood.id] = 0
	var engine := _engine(state)
	var before := _fingerprint(state)
	var resolution := engine.execute(UseAbilityCommand.at_hex(user.unit_id, Vector2i(2, 0), flood.id))
	suite.expect(not resolution.accepted and DEFECT in resolution.rejection_reason, "An ability whose terrain never settles is rejected as a failed effect")
	suite.expect(_fingerprint(state) == before and user.turn.main_action_available and engine.execute(EndTurnCommand.new(user.unit_id)).accepted, "The rejected ability changes nothing and the battle continues")

	# A water hit on a unit in the pool reacts with its hex inside the ability's damage.
	state = _pool_state(fixture)
	user = state.unit_states[&"user"]
	var splash: AbilityDefinition = fixture.ability(&"core:splash", AbilityDefinition.TargetMode.HEX)
	splash.range = 4
	splash.effects[0].parameters = {"amount": 2, "damage_type": "water"}
	user.abilities[splash.id] = splash
	user.ability_cooldowns[splash.id] = 0
	engine = _engine(state)
	before = _fingerprint(state)
	resolution = engine.execute(UseAbilityCommand.at_hex(user.unit_id, Vector2i(2, 0), splash.id))
	suite.expect(not resolution.accepted and DEFECT in resolution.rejection_reason and _fingerprint(state) == before, "A damage reaction that never settles rejects the whole ability, damage included")

	# A melee ability lets the defender answer with water onto the attacker's pool.
	state = _pool_state(fixture)
	user = state.unit_states[&"user"]
	var enemy: UnitState = state.unit_states[&"enemy"]
	state.hex_grid.set_hex_state(enemy.hex, &"")
	state.hex_grid.set_hex_state(Vector2i.ZERO, &"core:water")
	user.hex = Vector2i(1, 0)
	enemy.melee_retaliation = true
	enemy.retaliation_configured = true
	enemy.basic_attack_damage_type = &"water"
	var sweep: AbilityDefinition = fixture.ability(&"core:sweep", AbilityDefinition.TargetMode.SELF, 1)
	sweep.range = 1
	sweep.melee_attack = true
	user.abilities[sweep.id] = sweep
	user.ability_cooldowns[sweep.id] = 0
	engine = _engine(state)
	before = _fingerprint(state)
	resolution = engine.execute(UseAbilityCommand.at_hex(user.unit_id, user.hex, sweep.id))
	suite.expect(not resolution.accepted and DEFECT in resolution.rejection_reason and _fingerprint(state) == before, "A retaliation reaction that never settles rejects the melee ability whole")


func _check_landed_hit(suite: Node, fixture: Fixtures) -> void:
	var state := _pool_state(fixture)
	var user: UnitState = state.unit_states[&"user"]
	var enemy: UnitState = state.unit_states[&"enemy"]
	user.basic_attack_damage_type = &"water"
	var engine := _engine(state)
	var map_before := _encode(state.hex_grid)
	var resolution := engine.execute(AttackCommand.new(user.unit_id, enemy.unit_id))
	var hit := false
	for event: BattleEvent in resolution.events:
		hit = hit or (event is UnitDamagedEvent and event.target_id == enemy.unit_id and event.damage > 0)
	suite.expect(resolution.accepted and DEFECT in resolution.terminal_error and hit, "A landed hit whose reaction never settles stops the battle and keeps the hit")
	suite.expect(_encode(state.hex_grid) == map_before and engine.get_active_unit_id() == user.unit_id, "The failed reaction leaves the map untouched and no further rules run")
	suite.expect(not engine.execute(EndTurnCommand.new(user.unit_id)).accepted, "A battle stopped by a reaction defect rejects further commands")


func _check_retaliation(suite: Node, fixture: Fixtures) -> void:
	var state := _pool_state(fixture)
	var user: UnitState = state.unit_states[&"user"]
	var enemy: UnitState = state.unit_states[&"enemy"]
	# The attacker strikes physically; the defender answers with water onto the attacker's pool.
	state.hex_grid.set_hex_state(enemy.hex, &"")
	state.hex_grid.set_hex_state(Vector2i.ZERO, &"core:water")
	user.hex = Vector2i(1, 0)
	user.basic_attack_range = 1
	enemy.melee_retaliation = true
	enemy.retaliation_configured = true
	enemy.basic_attack_damage_type = &"water"
	var engine := _engine(state)
	var resolution := engine.execute(AttackCommand.new(user.unit_id, enemy.unit_id))
	suite.expect(resolution.accepted and DEFECT in resolution.terminal_error, "A retaliation whose reaction never settles stops the battle")


func _check_battle_start(suite: Node, fixture: Fixtures) -> void:
	var state := _pool_state(fixture)
	var enemy: UnitState = state.unit_states[&"enemy"]
	var map_before := _encode(state.hex_grid)
	var engine := BattleEngine.new(state)
	var start := engine.get_initial_resolution()
	suite.expect(DEFECT in start.terminal_error and start.events.is_empty(), "Starting terrain that never settles stops the battle before the first turn")
	suite.expect(_encode(state.hex_grid) == map_before and enemy.health.current == 20, "The start keeps the authored map and exposes nobody")
	suite.expect(not engine.execute(EndTurnCommand.new(engine.get_active_unit_id())).accepted, "A battle that could not start rejects commands")


## Three water cells in a row with the enemy standing in the pool; the table never settles.
func _pool_state(fixture: Fixtures) -> BattleState:
	var cells: Array[Vector2i] = []
	for q in range(0, 5):
		cells.append(Vector2i(q, 0))
	var user: UnitState = fixture.unit(&"user", BattleFaction.Value.PLAYER, Vector2i.ZERO, 20, 3)
	var enemy: UnitState = fixture.unit(&"enemy", BattleFaction.Value.ENEMY, Vector2i(2, 0), 20)
	user.basic_attack_range = 2
	var units: Array[UnitState] = [user, enemy]
	var state: BattleState = fixture.state(cells, units)
	for hex: Vector2i in [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]:
		state.hex_grid.set_hex_state(hex, &"core:water")
	state.hex_propagation = NEVER_SETTLES
	return state


func _engine(state: BattleState) -> BattleEngine:
	Fixtures.start_turns(state)
	return BattleEngine.new(state, false)


func _fingerprint(state: BattleState) -> String:
	var ids := state.unit_states.keys()
	ids.sort()
	var units: Array = []
	for id: StringName in ids:
		units.append(state.unit_states[id])
	return _encode({"units": units, "grid": state.hex_grid, "revisions": [state.state_revision, state.map_revision], "rng": str(state.random.state)})


func _encode(value: Variant) -> String:
	return JSON.stringify(BattleLogSerializer.encode(value))
