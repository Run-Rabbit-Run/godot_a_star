class_name BattleMapFactory
extends RefCounted


## Создаёт логическую сетку только из данных карты, без SceneTree и TileMapLayer.
static func create_hex_grid(
    definition: BattleMapDefinition
) -> HexGrid:
    if definition == null:
        push_error("BattleMapDefinition must not be null.")
        return null

    var axial_cells: Array[Vector2i] = []
    var movement_costs: Dictionary[Vector2i, int] = {}

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

        axial_cells.append(cell_definition.hex)
        movement_costs[cell_definition.hex] = cell_definition.movement_cost

    return HexGrid.new(axial_cells, movement_costs)
