class_name HexStateService
extends RefCounted

static func expose(unit: UnitState, grid: HexGrid, events: Array[BattleEvent]) -> void:
	if unit == null or unit.health.is_defeated():
		return
	var id := grid.get_hex_state_id(unit.hex)
	var effects: Dictionary = HexStateCatalog.EFFECTS.get(id, {})
	for status: StringName in effects:
		UnitStatusService.apply(unit, status, int(effects[status]), events)
	UnitStatusService.damage(unit, HexStateCatalog.get_damage(id), HexStateCatalog.get_damage_type(id), events, &"", id)

static func apply_to_grid(grid: HexGrid, hex: Vector2i, incoming: StringName, events: Array[BattleEvent], explosions: Array[Dictionary]) -> void:
	if not grid.has_cell(hex) or grid.has_obstacle(hex):
		return
	var previous := grid.get_hex_state_id(hex)
	var result := HexStateCatalog.combine(previous, incoming)
	if previous == result:
		if not result.is_empty() and grid.get_hex_state_turns(hex) < HexStateCatalog.LIFETIME:
			grid.set_hex_state_turns(hex, HexStateCatalog.LIFETIME)
			_emit_state(grid, hex, events, false)
		return
	_set_state(grid, hex, result, events)
	if result in [&"core:burning_oil", &"core:acid_vapour"] and previous != incoming:
		# Only the base-state matrix reactions explode.
		if previous in [&"core:fire", &"core:oil", &"core:acid"] and incoming in [&"core:fire", &"core:oil", &"core:acid"]:
			explosions.append({"hex": hex, "state_id": result})

static func propagate(grid: HexGrid, seeds: Array[Vector2i], events: Array[BattleEvent]) -> void:
	var pending: Array[Vector2i] = []
	pending.assign(seeds)
	pending.sort()
	# Without cycles in the catalog a cell changes at most once per state; a cycle is a rules bug.
	var conversions_left := grid.get_cells().size() * HexStateCatalog.RULES.size()
	var index := 0
	while index < pending.size():
		var hex := pending[index]
		index += 1
		var rules := HexStateCatalog.propagation(grid.get_hex_state_id(hex))
		for direction: Vector2i in HexGrid.DIRECTIONS:
			var neighbor := hex + direction
			if not grid.has_cell(neighbor) or grid.has_obstacle(neighbor):
				continue
			var previous := grid.get_hex_state_id(neighbor)
			if rules.has(previous):
				if conversions_left <= 0:
					push_error("Hex state propagation exceeded its limit; the propagation rules contain a cycle.")
					return
				conversions_left -= 1
				_set_state(grid, neighbor, rules[previous], events)
				pending.append(neighbor)

## One tick per completed round, before any exposure in the next round.
static func end_round(state: BattleState, events: Array[BattleEvent]) -> void:
	var changed := false
	var cells := state.hex_grid.get_cells()
	cells.sort()
	for hex: Vector2i in cells:
		var turns := state.hex_grid.get_hex_state_turns(hex)
		if turns <= 0:
			continue
		changed = true
		if turns == 1:
			_set_state(state.hex_grid, hex, &"", events)
		else:
			state.hex_grid.set_hex_state_turns(hex, turns - 1)
			_emit_state(state.hex_grid, hex, events, false)
	if changed:
		state.map_revision += 1
		state.state_revision += 1

static func _set_state(grid: HexGrid, hex: Vector2i, id: StringName, events: Array[BattleEvent]) -> void:
	grid.set_hex_state(hex, id)
	_emit_state(grid, hex, events, true)

static func _emit_state(grid: HexGrid, hex: Vector2i, events: Array[BattleEvent], changed: bool) -> void:
	var event := MapMutationEvent.new(MapMutationKind.Value.APPLY_HEX_STATE, hex, grid.get_terrain_id(hex), grid.is_traversable(hex), grid.get_configured_movement_cost(hex))
	event.hex_state_id = grid.get_hex_state_id(hex)
	event.hex_state_turns = grid.get_hex_state_turns(hex)
	event.hex_state_changed = changed
	events.append(event)
