class_name BattleMapAssembler
extends RefCounted


## Временный адаптер старой карты: визуальные тайлы становятся данными.
static func import_definition(
    terrain_layer: TileMapLayer,
    definition_id: StringName = &"legacy:battle_map"
) -> BattleMapDefinition:
    var definition := BattleMapDefinition.new()
    definition.id = definition_id

    for map_cell in terrain_layer.get_used_cells():
        var axial_cell := HexCoordinateMapper.offset_to_axial(map_cell)
        var tile_data := terrain_layer.get_cell_tile_data(map_cell)
        var movement_cost := 1

        if tile_data != null:
            movement_cost = maxi(
                int(tile_data.get_custom_data("movement_cost")),
                1
            )

        definition.cells.append(
            BattleMapCellDefinition.new(axial_cell, movement_cost)
        )

    return definition


## Сохраняет текущий API контроллера, но HexGrid уже создаётся из данных.
static func build_hex_grid(
    terrain_layer: TileMapLayer
) -> HexGrid:
    var definition := import_definition(terrain_layer)

    return BattleMapFactory.create_hex_grid(definition)
