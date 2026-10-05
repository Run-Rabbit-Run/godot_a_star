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
	var previous := grid.get_hex_state_id(hex)
	var result := HexStateCatalog.combine(previous, incoming)
	if previous == result:
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
	var index := 0
	while index < pending.size():
		var hex := pending[index]
		index += 1
		var rules := HexStateCatalog.propagation(grid.get_hex_state_id(hex))
		for direction: Vector2i in HexGrid.DIRECTIONS:
			var neighbor := hex + direction
			if not grid.has_cell(neighbor):
				continue
			var previous := grid.get_hex_state_id(neighbor)
			if rules.has(previous):
				_set_state(grid, neighbor, rules[previous], events)
				pending.append(neighbor)

static func _set_state(grid: HexGrid, hex: Vector2i, id: StringName, events: Array[BattleEvent]) -> void:
	grid.set_hex_state(hex, id)
	var event := MapMutationEvent.new(MapMutationKind.Value.APPLY_HEX_STATE, hex, grid.get_terrain_id(hex), grid.is_traversable(hex), grid.get_configured_movement_cost(hex))
	event.hex_state_id = id
	events.append(event)
