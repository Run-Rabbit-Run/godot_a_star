class_name HexStateService
extends RefCounted
## Rules of the two hex layers: applying a liquid or an energy, reactions, spreading,
## exposure of the occupant and the lifetime of each layer.


## Statuses of the liquid, then of the energy; then each layer's own damage.
static func expose(unit: UnitState, grid: HexGrid, events: Array[BattleEvent]) -> void:
	if unit == null or unit.health.is_defeated():
		return
	var layers: Array[StringName] = [grid.get_liquid(unit.hex), grid.get_energy(unit.hex)]
	for id: StringName in layers:
		var effects := HexStateCatalog.get_statuses(id)
		for status: StringName in effects:
			UnitStatusService.apply(unit, status, int(effects[status]), events)
	for id: StringName in layers:
		UnitStatusService.damage(unit, HexStateCatalog.get_damage(id), HexStateCatalog.get_damage_type(id), events, &"", id)


## Direct damage both layers of the hex deal to an occupant.
static func damage_at(grid: HexGrid, hex: Vector2i) -> int:
	return HexStateCatalog.get_damage(grid.get_liquid(hex)) + HexStateCatalog.get_damage(grid.get_energy(hex))


## Applies one liquid or energy by the layer rules; "" clears both layers.
static func apply_to_grid(grid: HexGrid, hex: Vector2i, incoming: StringName, events: Array[BattleEvent]) -> void:
	if not grid.has_cell(hex) or grid.has_obstacle(hex):
		return
	if incoming.is_empty():
		if grid.has_layers(hex):
			grid.set_liquid(hex, &"")
			grid.set_energy(hex, &"")
			_emit_state(grid, hex, events, true)
		return
	if HexStateCatalog.is_liquid(incoming):
		_apply_liquid(grid, hex, incoming, events)
	else:
		_apply_energy(grid, hex, incoming, events)


## Same-hex reactions of layers stored together, as an authored map may hold them.
static func settle(grid: HexGrid, events: Array[BattleEvent]) -> void:
	var cells := grid.get_cells()
	cells.sort()
	for hex: Vector2i in cells:
		if grid.get_liquid(hex) == &"core:water" and grid.get_energy(hex) == &"core:fire":
			grid.set_liquid(hex, &"core:steam")
			grid.set_energy(hex, &"")
			_emit_state(grid, hex, events, true)


## Returns "" or the defect. The built-in rule gives a cell each energy at most once, so a
## cell receives spreading at most twice; exceeding that bound means the rule cannot settle
## and the caller must discard the grid it propagated on.
static func propagate(grid: HexGrid, seeds: Array[Vector2i], events: Array[BattleEvent], rule: Callable = HexStateCatalog.spreading_energy) -> String:
	var pending: Array[Vector2i] = []
	pending.assign(seeds)
	pending.sort()
	var spreads_left := grid.get_cells().size() * 2
	var index := 0
	while index < pending.size():
		var hex := pending[index]
		index += 1
		for direction: Vector2i in HexGrid.DIRECTIONS:
			var neighbor := hex + direction
			if not grid.has_cell(neighbor) or grid.has_obstacle(neighbor):
				continue
			var energy: StringName = rule.call(grid.get_liquid(hex), grid.get_energy(hex), grid.get_liquid(neighbor), grid.get_energy(neighbor))
			if energy.is_empty():
				continue
			if spreads_left <= 0:
				return "Hex state propagation did not settle: the spreading rule never stops."
			spreads_left -= 1
			_apply_energy(grid, neighbor, energy, events)
			pending.append(neighbor)
	return ""


## One tick per completed round, before any exposure in the next round. Each layer
## expires on its own.
static func end_round(state: BattleState, events: Array[BattleEvent]) -> void:
	var changed := false
	var cells := state.hex_grid.get_cells()
	cells.sort()
	var grid := state.hex_grid
	for hex: Vector2i in cells:
		if not grid.has_layers(hex):
			continue
		changed = true
		var cleared := false
		var liquid_turns := grid.get_liquid_turns(hex)
		if liquid_turns == 1:
			grid.set_liquid(hex, &"")
			cleared = true
		elif liquid_turns > 1:
			grid.set_liquid_turns(hex, liquid_turns - 1)
		var energy_turns := grid.get_energy_turns(hex)
		if energy_turns == 1:
			grid.set_energy(hex, &"")
			cleared = true
		elif energy_turns > 1:
			grid.set_energy_turns(hex, energy_turns - 1)
		_emit_state(grid, hex, events, cleared)
	if changed:
		state.map_revision += 1
		state.state_revision += 1


## A new liquid displaces the old one; water meeting fire evaporates into steam.
static func _apply_liquid(grid: HexGrid, hex: Vector2i, liquid: StringName, events: Array[BattleEvent]) -> void:
	if liquid == &"core:water" and grid.get_energy(hex) == &"core:fire":
		grid.set_liquid(hex, &"core:steam")
		grid.set_energy(hex, &"")
		_emit_state(grid, hex, events, true)
		return
	if grid.get_liquid(hex) == liquid:
		_refresh(grid, hex, events, true)
		return
	grid.set_liquid(hex, liquid)
	_emit_state(grid, hex, events, true)


## Energies combine into plasma; fire meeting water evaporates both into steam.
static func _apply_energy(grid: HexGrid, hex: Vector2i, incoming: StringName, events: Array[BattleEvent]) -> void:
	if incoming == &"core:fire" and grid.get_liquid(hex) == &"core:water":
		grid.set_liquid(hex, &"core:steam")
		_emit_state(grid, hex, events, true)
		return
	var existing := grid.get_energy(hex)
	var result := HexStateCatalog.combine_energy(existing, incoming)
	if result == existing:
		_refresh(grid, hex, events, false)
		return
	grid.set_energy(hex, result)
	_emit_state(grid, hex, events, true)


## Repeating a layer's value restores its full lifetime without a new exposure.
static func _refresh(grid: HexGrid, hex: Vector2i, events: Array[BattleEvent], liquid: bool) -> void:
	var turns := grid.get_liquid_turns(hex) if liquid else grid.get_energy_turns(hex)
	if turns >= HexStateCatalog.LIFETIME:
		return
	if liquid:
		grid.set_liquid_turns(hex, HexStateCatalog.LIFETIME)
	else:
		grid.set_energy_turns(hex, HexStateCatalog.LIFETIME)
	_emit_state(grid, hex, events, false)


static func _emit_state(grid: HexGrid, hex: Vector2i, events: Array[BattleEvent], changed: bool) -> void:
	var event := MapMutationEvent.new(MapMutationKind.Value.APPLY_HEX_STATE, hex, grid.get_terrain_id(hex), grid.is_traversable(hex), grid.get_configured_movement_cost(hex))
	event.liquid_id = grid.get_liquid(hex)
	event.liquid_turns = grid.get_liquid_turns(hex)
	event.energy_id = grid.get_energy(hex)
	event.energy_turns = grid.get_energy_turns(hex)
	event.hex_state_changed = changed
	events.append(event)
