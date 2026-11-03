class_name BattleMapFactory
extends RefCounted


static func create_hex_grid(
	definition: BattleMapDefinition
) -> HexGrid:
	if definition == null:
		push_error("BattleMapDefinition must not be null.")
		return null

	var axial_cells: Array[Vector2i] = []
	var movement_costs: Dictionary[Vector2i, int] = {}
	var terrain_ids: Dictionary[Vector2i, StringName] = {}
	var traversal: Dictionary[Vector2i, bool] = {}
	var liquids: Dictionary[Vector2i, StringName] = {}
	var energies: Dictionary[Vector2i, StringName] = {}

	for cell_definition: BattleMapCellDefinition in definition.cells:
		if cell_definition == null:
			push_error("BattleMapDefinition contains a null cell.")
			return null

		if movement_costs.has(cell_definition.hex):
			push_error(
				"BattleMapDefinition contains duplicate hex %s."
				% cell_definition.hex
			)
			return null

		if cell_definition.movement_cost < 1:
			push_error(
				"Battle map movement cost must be at least 1 for hex %s."
				% cell_definition.hex
			)
			return null

		if cell_definition.terrain_id.is_empty():
			push_error(
				"Battle map terrain id must not be empty for hex %s."
				% cell_definition.hex
			)
			return null

		var liquid := cell_definition.liquid_id
		var energy := cell_definition.energy_id
		if (not liquid.is_empty() and not HexStateCatalog.is_liquid(liquid)) or (not energy.is_empty() and not HexStateCatalog.is_energy(energy)):
			push_error("Unknown hex layer %s / %s at %s." % [liquid, energy, cell_definition.hex])
			return null

		if not liquid.is_empty() and cell_definition.movement_cost != HexStateCatalog.get_movement_cost(liquid):
			push_error("Hex state movement cost mismatch at %s." % cell_definition.hex)
			return null

		axial_cells.append(cell_definition.hex)
		movement_costs[cell_definition.hex] = cell_definition.movement_cost
		terrain_ids[cell_definition.hex] = cell_definition.terrain_id
		traversal[cell_definition.hex] = cell_definition.traversable
		liquids[cell_definition.hex] = liquid
		energies[cell_definition.hex] = energy

	var grid := HexGrid.new(
		axial_cells,
		movement_costs,
		terrain_ids,
		traversal,
		liquids,
		energies
	)
	for obstacle: BattleObstacleDefinition in definition.obstacles:
		if not grid.add_obstacle(obstacle):
			push_error("Invalid obstacle: missing/overlapping cells, hex state, ID, footprint or HP.")
			return null
	return grid
