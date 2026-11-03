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
	var c := Vector2i(2, 0)
	var d := Vector2i(3, 0)
	# Rule 1: a new liquid displaces the old one and sets the movement cost.
	var state := fixture.state([a, b])
	MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:water")])
	MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:oil")])
	suite.expect(_layers(state.hex_grid, a) == "core:oil/" and state.hex_grid.get_configured_movement_cost(a) == 2, "A new liquid displaces the old one; oil costs two")
	MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:acid")])
	suite.expect(_layers(state.hex_grid, a) == "core:acid/" and state.hex_grid.get_configured_movement_cost(a) == 1, "Acid displaces oil and the cost returns to one")
	MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:electricity")])
	suite.expect(_layers(state.hex_grid, a) == "core:acid/core:electricity", "An energy lies over a liquid without changing it")
	# Rule 2: fire and electricity make plasma, independent of cell and mutation order.
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
		suite.expect(MapMutationService.apply(state, mutations).accepted, "Area reaction accepted")
		final_states.append("%s|%s" % [_layers(state.hex_grid, a), _layers(state.hex_grid, b)])
	suite.expect(final_states[0] == final_states[1] and final_states[0] == "/core:plasma|/core:plasma", "Fire and electricity make plasma whatever the order")
	MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:fire")])
	suite.expect(_layers(state.hex_grid, a) == "/core:plasma", "Plasma absorbs more fire")
	# Rule 3: fire evaporates water into steam, whichever comes first.
	state = fixture.state([a, b])
	state.hex_grid.set_hex_state(a, &"core:water")
	state.hex_grid.set_hex_state(b, &"core:fire")
	MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:fire"), MapMutation.apply_hex_state(b, &"core:water")])
	suite.expect(_layers(state.hex_grid, a) == "core:steam/" and _layers(state.hex_grid, b) == "core:steam/", "Fire evaporates water into steam from either side")
	suite.expect(HexStateCatalog.ranged_reduction(state.hex_grid.get_liquid(a)) == 3, "Steam gives cover against shots")
	# Rule 4: fire runs through connected oil and stops where the oil ends.
	state = fixture.state([a, b, c, d])
	for hex: Vector2i in [a, b, c]:
		state.hex_grid.set_hex_state(hex, &"core:oil")
	MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:fire")])
	suite.expect(_layers(state.hex_grid, c) == "core:oil/core:fire" and not state.hex_grid.has_layers(d), "Fire runs through connected oil only")
	# Rule 5: electricity runs through water and acid of the same kind; oil does not conduct.
	state = fixture.state([a, b, c])
	state.hex_grid.set_hex_state(a, &"core:water")
	state.hex_grid.set_hex_state(b, &"core:water")
	state.hex_grid.set_hex_state(c, &"core:acid")
	MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:electricity")])
	suite.expect(_layers(state.hex_grid, b) == "core:water/core:electricity" and _layers(state.hex_grid, c) == "core:acid/", "Electricity runs to the same liquid, not to another")
	state = fixture.state([a, b])
	state.hex_grid.set_hex_state(a, &"core:water")
	state.hex_grid.set_hex_state(a, &"core:electricity")
	MapMutationService.apply(state, [MapMutation.apply_hex_state(b, &"core:water")])
	suite.expect(_layers(state.hex_grid, b) == "core:water/core:electricity", "New water next to charged water gets charged too")
	state = fixture.state([a, b])
	state.hex_grid.set_hex_state(a, &"core:oil")
	state.hex_grid.set_hex_state(b, &"core:oil")
	MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:electricity")])
	suite.expect(_layers(state.hex_grid, a) == "core:oil/core:electricity" and _layers(state.hex_grid, b) == "core:oil/", "Oil keeps electricity but does not conduct it")
	# Hits react only where a layer already lies.
	state = fixture.state([a, b])
	var events: Array[BattleEvent] = []
	suite.expect(DamageType.react(state, a, &"fire", events).is_empty() and not state.hex_grid.has_layers(a), "A hit leaves no layer on a clean hex")
	state.hex_grid.set_hex_state(a, &"core:water")
	DamageType.react(state, a, &"fire", events)
	suite.expect(_layers(state.hex_grid, a) == "core:steam/", "A fire hit on water follows the layer rules")
	# The battle start settles pairs stored together, as the editor may store them.
	var occupant := fixture.unit(&"p", BattleFaction.Value.PLAYER, b)
	state = fixture.state([a, b], [occupant])
	state.hex_grid.set_liquid(a, &"core:water")
	state.hex_grid.set_energy(a, &"core:fire")
	BattleEngine.new(state)
	suite.expect(_layers(state.hex_grid, a) == "core:steam/", "The battle start evaporates stored water and fire")
	suite.expect(HexStateCatalog.split(&"core:burning_oil") == [&"core:oil", &"core:fire"] and HexStateCatalog.split(&"core:boiling_acid") == [&"core:acid", &""] and HexStateCatalog.split(&"core:steam") == [&"core:steam", &""], "Former single states read as layers")
	# Fire on oil explodes the occupant through its statuses; the hex itself does not explode.
	occupant = fixture.unit(&"p", BattleFaction.Value.PLAYER, a)
	state = fixture.state([a, b], [occupant])
	state.hex_grid.set_hex_state(a, &"core:oil")
	MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:fire")])
	suite.expect(occupant.health.current == 95 and not occupant.statuses.has(&"core:sticky_oil"), "Oil and burning explode on the occupant for 4, then fire deals 1")
	state = fixture.state([a, b])
	var application := MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:fire"), MapMutation.remove_hex(Vector2i(9, 9))])
	suite.expect(not application.accepted and not state.hex_grid.has_layers(a) and state.state_revision == 0, "Invalid batch commits neither terrain nor revisions")
	occupant = fixture.unit(&"p", BattleFaction.Value.PLAYER, a)
	state = fixture.state([a, b], [occupant])
	suite.expect(not MapMutationService.apply(state, [MapMutation.remove_hex(a)]).accepted, "Cannot remove living occupant cell")
	suite.expect(not MapMutationService.apply(state, [MapMutation.set_traversal(a, false)]).accepted, "Cannot block living occupant cell")
	state.hex_grid.set_hex_state(a, &"core:water")
	var first := MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:electricity")])
	var levels := int(occupant.statuses.get(&"core:electrified", 0))
	var hp := occupant.health.current
	MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:electricity")])
	suite.expect(not first.events.is_empty() and levels == 2 and occupant.statuses.get(&"core:wet", 0) == 2, "Changed terrain exposes the occupant to both layers once")
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
		suite.expect(_layer_turns(state.hex_grid, a, id) == 3, "Every layer value starts with three rounds: %s" % id)
		var events: Array[BattleEvent] = []
		HexStateService.end_round(state, events)
		HexStateService.end_round(state, events)
		suite.expect(_layer_value(state.hex_grid, a, id) == id and _layer_turns(state.hex_grid, a, id) == 1, "A layer persists for its first two round boundaries: %s" % id)
		HexStateService.end_round(state, events)
		suite.expect(state.hex_grid.has_cell(a) and not state.hex_grid.has_layers(a) and state.hex_grid.get_configured_movement_cost(a) == 1, "The third boundary clears only the layer and resets the cost: %s" % id)
	# Each layer keeps its own lifetime.
	var state := fixture.state([a])
	var events: Array[BattleEvent] = []
	MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:acid")])
	HexStateService.end_round(state, events)
	MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:electricity")])
	suite.expect(state.hex_grid.get_liquid_turns(a) == 2 and state.hex_grid.get_energy_turns(a) == 3, "A new energy does not refresh the liquid under it")
	HexStateService.end_round(state, events)
	HexStateService.end_round(state, events)
	suite.expect(_layers(state.hex_grid, a) == "/core:electricity" and state.hex_grid.get_energy_turns(a) == 1, "The liquid expires first; the energy stays")
	var occupant := fixture.unit(&"p", BattleFaction.Value.PLAYER, a)
	state = fixture.state([a, b], [occupant])
	MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:electricity")])
	HexStateService.end_round(state, events)
	var copy := state.hex_grid.duplicate_grid()
	copy.set_energy_turns(a, 1)
	suite.expect(state.hex_grid.get_energy_turns(a) == 2 and copy.get_energy_turns(a) == 1, "Grid copy keeps remaining duration detached")
	var prediction := state.duplicate_for_prediction()
	HexStateService.end_round(prediction, events)
	suite.expect(state.hex_grid.get_energy_turns(a) == 2 and prediction.hex_grid.get_energy_turns(a) == 1, "Prediction ticks its own map duration")
	var hp := occupant.health.current
	var statuses := occupant.statuses.duplicate()
	var revision := state.map_revision
	var application := MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:electricity")])
	suite.expect(application.accepted and state.hex_grid.get_energy_turns(a) == 3 and state.map_revision == revision + 1, "Same-value application refreshes duration and revision")
	suite.expect(occupant.health.current == hp and occupant.statuses == statuses and application.events.size() == 1 and not application.events[0].hex_state_changed, "Refresh emits duration without repeat exposure")
	HexStateService.end_round(state, events)
	application = MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:electricity"), MapMutation.remove_hex(Vector2i(99, 99))])
	suite.expect(not application.accepted and state.hex_grid.get_energy_turns(a) == 2, "Rejected batch does not refresh live duration")
	MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:fire")])
	suite.expect(state.hex_grid.get_energy(a) == &"core:plasma" and state.hex_grid.get_energy_turns(a) == 3, "A reaction begins a new three-round lifetime")
	state.hex_grid.set_hex_state(a, &"")
	state.hex_grid.set_hex_state(a, &"core:water")
	state.hex_grid.set_liquid_turns(a, 1)
	state.hex_grid.set_hex_state(b, &"core:water")
	state.hex_grid.set_liquid_turns(b, 1)
	MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:electricity")])
	suite.expect(state.hex_grid.get_energy(b) == &"core:electricity" and state.hex_grid.get_energy_turns(b) == 3 and state.hex_grid.get_liquid_turns(b) == 1, "Spreading gives the neighbor a fresh energy, not a fresh liquid")
	state.hex_grid.remove_cell(b)
	state.hex_grid.add_cell(b, &"core:default", 1, true)
	suite.expect(state.hex_grid.get_liquid_turns(b) == 0 and state.hex_grid.get_energy_turns(b) == 0, "Removed hex does not leak duration to its replacement")
	# Count one round, not one acting unit; expire before next-round exposure.
	var p := fixture.unit(&"p", BattleFaction.Value.PLAYER, a)
	var e := fixture.unit(&"e", BattleFaction.Value.ENEMY, b)
	state = fixture.state([a, b], [p, e])
	state.hex_grid.set_hex_state(a, &"core:oil")
	var engine := BattleEngine.new(state)
	for round_index: int in range(3):
		engine.execute(EndTurnCommand.new(p.unit_id))
		suite.expect(state.hex_grid.get_liquid_turns(a) == 3 - round_index, "Individual unit turn does not age the map: %d" % round_index)
		var result := engine.execute(EndTurnCommand.new(e.unit_id))
		suite.expect(result.accepted and state.hex_grid.get_liquid_turns(a) == 2 - round_index and engine.get_round_number() == round_index + 2, "Whole round ages map exactly once: %d" % round_index)
	suite.expect(p.statuses.get(&"core:sticky_oil", 0) == 3 and p.turn.movement_remaining == 7, "Expired state cannot reapply at next turn; existing unit status remains")
	var corpse := fixture.unit(&"dead", BattleFaction.Value.ENEMY, Vector2i(2, 0))
	corpse.health.current = 0
	p.statuses.clear()
	e.statuses.assign({&"core:paralysis": 1})
	state = fixture.state([a, b, corpse.hex], [p, e, corpse])
	state.hex_grid.set_hex_state(a, &"core:water")
	engine = BattleEngine.new(state)
	engine.execute(EndTurnCommand.new(p.unit_id))
	suite.expect(engine.get_active_unit_id() == p.unit_id and state.hex_grid.get_liquid_turns(a) == 2, "Skipped and defeated participants still produce one round tick")


## "liquid/energy" of the hex, for compact expectations.
static func _layers(grid: HexGrid, hex: Vector2i) -> String:
	return "%s/%s" % [grid.get_liquid(hex), grid.get_energy(hex)]


static func _layer_value(grid: HexGrid, hex: Vector2i, id: StringName) -> StringName:
	return grid.get_liquid(hex) if HexStateCatalog.is_liquid(id) else grid.get_energy(hex)


static func _layer_turns(grid: HexGrid, hex: Vector2i, id: StringName) -> int:
	return grid.get_liquid_turns(hex) if HexStateCatalog.is_liquid(id) else grid.get_energy_turns(hex)
