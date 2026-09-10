class_name BattleMapAssembler
extends RefCounted


## Единственная точка, где визуальные тайлы превращаются в логическую сетку.
static func build_hex_grid(
	terrain_layer: TileMapLayer
) -> HexGrid:
	var axial_cells: Array[Vector2i] = []
	var movement_costs: Dictionary[Vector2i, int] = {}

	for map_cell in terrain_layer.get_used_cells():
		var axial_cell := HexCoordinateMapper.offset_to_axial(map_cell)
		var tile_data := terrain_layer.get_cell_tile_data(map_cell)
		var movement_cost := 1

		if tile_data != null:
			movement_cost = maxi(
				int(tile_data.get_custom_data("movement_cost")),
				1
			)

		axial_cells.append(axial_cell)
		movement_costs[axial_cell] = movement_cost

	return HexGrid.new(axial_cells, movement_costs)