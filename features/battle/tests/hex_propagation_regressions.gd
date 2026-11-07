extends RefCounted
## Hex state propagation that never settles is a rules defect. It must never leave a
## half-updated map: the batch is rejected whole, and whoever owns the larger operation
## either discards it (ability, external batch) or stops the battle (landed hit, start).
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")

const DEFECT := "did not settle"


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	_check_rule_settles(suite)
	_check_propagation_reports_defect(suite)
	_check_external_batch(suite, fixture)
	_check_ability(suite, fixture)
	_check_landed_hit(suite, fixture)
	_check_retaliation(suite, fixture)
	_check_battle_start(suite, fixture)


## Electricity keeps running into charged water: the smallest rule that cannot settle.
func _never_settles(_source_liquid: StringName, _source_energy: StringName, neighbor_liquid: StringName, _neighbor_energy: StringName) -> StringName:
	return &"core:electricity" if neighbor_liquid == &"core:water" else &""


## Every energy the built-in rule spreads is final for its receiver: the same source never
## spreads to it again, so a cell receives spreading at most twice.
func _check_rule_settles(suite: Node) -> void:
	var values: Array[StringName] = [&""]
	for id: StringName in HexStateCatalog.RULES:
		values.append(id)
	var source := Vector2i.ZERO
	var neighbor := Vector2i(1, 0)
	for source_liquid: StringName in values:
		for source_energy: StringName in values:
			for neighbor_liquid: StringName in values:
				for neighbor_energy: StringName in values:
					if not _fits(source_liquid, true) or not _fits(source_energy, false) or not _fits(neighbor_liquid, true) or not _fits(neighbor_energy, false):
						continue
					var energy := HexStateCatalog.spreading_energy(source_liquid, source_energy, neighbor_liquid, neighbor_energy)
					if energy.is_empty():
						continue
					var grid := HexGrid.new([source, neighbor])
					grid.set_liquid(neighbor, neighbor_liquid)
					grid.set_energy(neighbor, neighbor_energy)
					var events: Array[BattleEvent] = []
					HexStateService.apply_to_grid(grid, neighbor, energy, events)
					var again := HexStateCatalog.spreading_energy(source_liquid, source_energy, grid.get_liquid(neighbor), grid.get_energy(neighbor))
					suite.expect(again.is_empty(), "Spreading %s from %s/%s into %s/%s is final" % [energy, source_liquid, source_energy, neighbor_liquid, neighbor_energy])


static func _fits(id: StringName, liquid: bool) -> bool:
	return id.is_empty() or HexStateCatalog.is_liquid(id) == liquid


## The bound holds only while every reception is final; a rule that keeps spreading exceeds it.
func _check_propagation_reports_defect(suite: Node) -> void:
	var grid := HexGrid.new([Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)])
	for hex: Vector2i in grid.get_cells():
		grid.set_hex_state(hex, &"core:water")
	var events: Array[BattleEvent] = []
	var seeds: Array[Vector2i] = [Vector2i.ZERO]
	var error := HexStateService.propagate(grid, seeds, events, _never_settles)
	suite.expect(DEFECT in error, "Propagation that never settles reports the defect instead of logging it")
	suite.expect(events.size() <= grid.get_cells().size() * 2, "A defective rule stops within the spreading bound")
	events.clear()
	suite.expect(HexStateService.propagate(grid, seeds, events).is_empty(), "The built-in rule settles on the same map")


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


## Three water cells in a row with the enemy standing in the pool; the rule never settles.
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
	state.spread_rule = _never_settles
	return state


func _engine(state: BattleState) -> BattleEngine:
	Fixtures.start_turns(state)
	return BattleEngine.new(state, false)


func _fingerprint(state: BattleState) -> String:
	var ids := IdOrder.sorted(state.unit_states.keys())
	var units: Array = []
	for id: StringName in ids:
		units.append(state.unit_states[id])
	return _encode({"units": units, "grid": state.hex_grid, "revisions": [state.state_revision, state.map_revision], "rng": str(state.random.state)})


func _encode(value: Variant) -> String:
	return JSON.stringify(BattleLogSerializer.encode(value))
