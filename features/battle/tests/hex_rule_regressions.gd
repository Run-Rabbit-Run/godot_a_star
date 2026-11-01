extends RefCounted
## Hex grid rules: geometry, movement search on random maps, terrain reactions and hex state lifetime.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")


func run_geometry(suite: Node) -> void:
	for q in range(-4, 5):
		for r in range(-4, 5):
			var hex := Vector2i(q, r)
			suite.expect(HexCoordinateMapper.offset_to_axial(HexCoordinateMapper.axial_to_offset(hex)) == hex, "Coordinates round-trip %s" % hex)
	var grid := HexGrid.new([Vector2i.ZERO, Vector2i(1, 0), Vector2i(3, 0)])
	suite.expect(not grid.has_cell(Vector2i(2, 0)), "Holes remain absent")
	suite.expect(not MovementService.search(grid, Vector2i.ZERO, 10, {}).get_reachable_cells().has(Vector2i(3, 0)), "Movement cannot jump holes")
	grid.set_traversal(Vector2i(1, 0), false, 1)
	suite.expect(grid.has_cell(Vector2i(1, 0)) and not grid.is_traversable(Vector2i(1, 0)), "Blocked cell differs from a hole")
	var copy := grid.duplicate_grid()
	copy.remove_cell(Vector2i.ZERO)
	suite.expect(grid.has_cell(Vector2i.ZERO), "Grid copies are detached")


func run_terrain_reactions(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var a := Vector2i.ZERO
	var b := Vector2i(1, 0)
	var state := fixture.state([a, b])
	state.hex_grid.set_hex_state(a, &"core:electrified_water")
	var application := MapMutationService.apply(state, [MapMutation.apply_hex_state(b, &"core:water")])
	suite.expect(application.accepted and state.hex_grid.get_hex_state_id(b) == &"core:electrified_water", "Existing electrified water transforms newly created neighbor water")
	var final_states: Array[String] = []
	for reversed in [false, true]:
		var cells: Array[Vector2i] = []
		cells.assign([b, a] if reversed else [a, b])
		state = fixture.state(cells)
		state.hex_grid.set_hex_state(a, &"core:fire")
		state.hex_grid.set_hex_state(b, &"core:fire")
		var mutations: Array[MapMutation] = []
		for hex: Vector2i in cells:
			mutations.append(MapMutation.apply_hex_state(hex, &"core:electricity"))
		application = MapMutationService.apply(state, mutations)
		suite.expect(application.accepted, "Area reaction accepted")
		final_states.append("%s/%s" % [state.hex_grid.get_hex_state_id(a), state.hex_grid.get_hex_state_id(b)])
	suite.expect(final_states[0] == final_states[1] and final_states[0] == "core:plasma/core:plasma", "Area reactions independent of cell insertion and mutation order")
	state = fixture.state([a, b])
	application = MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:fire"), MapMutation.remove_hex(Vector2i(9, 9))])
	suite.expect(not application.accepted and state.hex_grid.get_hex_state_id(a).is_empty() and state.state_revision == 0, "Invalid batch commits neither terrain nor revisions")
	var occupant := fixture.unit(&"p", BattleFaction.Value.PLAYER, a)
	state = fixture.state([a, b], [occupant])
	suite.expect(not MapMutationService.apply(state, [MapMutation.remove_hex(a)]).accepted, "Cannot remove living occupant cell")
	suite.expect(not MapMutationService.apply(state, [MapMutation.set_traversal(a, false)]).accepted, "Cannot block living occupant cell")
	state.hex_grid.set_hex_state(a, &"core:water")
	var first := MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:electricity")])
	var levels := int(occupant.statuses.get(&"core:electrified", 0))
	var hp := occupant.health.current
	MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:electrified_water")])
	suite.expect(not first.events.is_empty() and levels == 3, "Changed terrain exposes occupant once")
	suite.expect(occupant.health.current == hp and occupant.statuses.get(&"core:electrified", 0) == levels, "No-op terrain does not repeat exposure")


func run_properties(suite: Node) -> void:
	for seed in range(30):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var cells: Array[Vector2i] = []
		var costs: Dictionary[Vector2i, int] = {}
		for q in range(-2, 3):
			for r in range(-2, 3):
				var hex := Vector2i(q, r)
				if hex == Vector2i.ZERO or rng.randf() > 0.2:
					cells.append(hex)
					costs[hex] = rng.randi_range(1, 4)
		var grid := HexGrid.new(cells, costs)
		var budget := rng.randi_range(1, 10)
		var movement := MovementService.search(grid, Vector2i.ZERO, budget, {})
		for destination: Vector2i in movement.get_reachable_cells():
			var path := movement.build_path(destination)
			var paid := 0
			var connected: bool = not path.is_empty() and path[0] == Vector2i.ZERO and path.back() == destination
			for index in range(1, path.size()):
				connected = connected and grid.has_cell(path[index]) and HexGrid.get_distance(path[index - 1], path[index]) == 1
				paid += grid.get_movement_cost(path[index])
			suite.expect(connected and paid <= budget and paid == movement.get_cost(destination), "Seed %d: reachable route obeys geometry and weighted budget" % seed)


func run_hex_lifetime(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var a := Vector2i.ZERO
	var b := Vector2i(1, 0)
	for id: StringName in HexStateCatalog.RULES:
		var state := fixture.state([a])
		MapMutationService.apply(state, [MapMutation.apply_hex_state(a, id)])
		suite.expect(state.hex_grid.get_hex_state_turns(a) == 3, "Every hex state starts with three rounds: %s" % id)
		var events: Array[BattleEvent] = []
		HexStateService.end_round(state, events)
		HexStateService.end_round(state, events)
		suite.expect(state.hex_grid.get_hex_state_id(a) == id and state.hex_grid.get_hex_state_turns(a) == 1, "Hex state persists for first two round boundaries: %s" % id)
		HexStateService.end_round(state, events)
		suite.expect(state.hex_grid.has_cell(a) and state.hex_grid.get_hex_state_id(a).is_empty() and state.hex_grid.get_hex_state_turns(a) == 0 and state.hex_grid.get_configured_movement_cost(a) == 1, "Third boundary clears only hex state and resets cost: %s" % id)
	var occupant := fixture.unit(&"p", BattleFaction.Value.PLAYER, a)
	var state := fixture.state([a, b], [occupant])
	MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:electricity")])
	var events: Array[BattleEvent] = []
	HexStateService.end_round(state, events)
	var copy := state.hex_grid.duplicate_grid()
	copy.set_hex_state_turns(a, 1)
	suite.expect(state.hex_grid.get_hex_state_turns(a) == 2 and copy.get_hex_state_turns(a) == 1, "Grid copy keeps remaining duration detached")
	var prediction := state.duplicate_for_prediction()
	HexStateService.end_round(prediction, events)
	suite.expect(state.hex_grid.get_hex_state_turns(a) == 2 and prediction.hex_grid.get_hex_state_turns(a) == 1, "Prediction ticks its own map duration")
	var hp := occupant.health.current
	var statuses := occupant.statuses.duplicate()
	var revision := state.map_revision
	var application := MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:electricity")])
	suite.expect(application.accepted and state.hex_grid.get_hex_state_turns(a) == 3 and state.map_revision == revision + 1, "Same-state application refreshes duration and revision")
	suite.expect(occupant.health.current == hp and occupant.statuses == statuses and application.events.size() == 1 and not application.events[0].hex_state_changed, "Refresh emits duration without repeat exposure")
	HexStateService.end_round(state, events)
	application = MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:electricity"), MapMutation.remove_hex(Vector2i(99, 99))])
	suite.expect(not application.accepted and state.hex_grid.get_hex_state_turns(a) == 2, "Rejected batch does not refresh live duration")
	MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:fire")])
	suite.expect(state.hex_grid.get_hex_state_id(a) == &"core:plasma" and state.hex_grid.get_hex_state_turns(a) == 3, "Reaction begins new three-round lifetime")
	state.hex_grid.set_hex_state(a, &"core:water")
	state.hex_grid.set_hex_state_turns(a, 1)
	state.hex_grid.set_hex_state(b, &"core:water")
	state.hex_grid.set_hex_state_turns(b, 1)
	MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:electricity")])
	suite.expect(state.hex_grid.get_hex_state_id(b) == &"core:electrified_water" and state.hex_grid.get_hex_state_turns(b) == 3, "Propagation gives converted neighbor a fresh duration")
	state.hex_grid.remove_cell(b)
	state.hex_grid.add_cell(b, &"core:default", 1, true)
	suite.expect(state.hex_grid.get_hex_state_turns(b) == 0, "Removed hex does not leak duration to its replacement")
	# Count one round, not one acting unit; expire before next-round exposure.
	var p := fixture.unit(&"p", BattleFaction.Value.PLAYER, a)
	var e := fixture.unit(&"e", BattleFaction.Value.ENEMY, b)
	state = fixture.state([a, b], [p, e])
	state.hex_grid.set_hex_state(a, &"core:oil")
	var engine := BattleEngine.new(state)
	for round_index: int in range(3):
		engine.execute(EndTurnCommand.new(p.unit_id))
		suite.expect(state.hex_grid.get_hex_state_turns(a) == 3 - round_index, "Individual unit turn does not age the map: %d" % round_index)
		var result := engine.execute(EndTurnCommand.new(e.unit_id))
		suite.expect(result.accepted and state.hex_grid.get_hex_state_turns(a) == 2 - round_index and engine.get_round_number() == round_index + 2, "Whole round ages map exactly once: %d" % round_index)
	suite.expect(p.statuses.get(&"core:sticky_oil", 0) == 3 and p.turn.movement_remaining == 7, "Expired state cannot reapply at next turn; existing unit status remains")
	var corpse := fixture.unit(&"dead", BattleFaction.Value.ENEMY, Vector2i(2, 0))
	corpse.health.current = 0
	p.statuses.clear()
	e.statuses.assign({&"core:paralysis": 1})
	state = fixture.state([a, b, corpse.hex], [p, e, corpse])
	state.hex_grid.set_hex_state(a, &"core:water")
	engine = BattleEngine.new(state)
	engine.execute(EndTurnCommand.new(p.unit_id))
	suite.expect(engine.get_active_unit_id() == p.unit_id and state.hex_grid.get_hex_state_turns(a) == 2, "Skipped and defeated participants still produce one round tick")
