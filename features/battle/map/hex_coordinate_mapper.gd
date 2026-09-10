class_name HexCoordinateMapper
extends RefCounted


## Преобразует координату TileMapLayer в осевую координату (q, r).
## Раскладка: Stacked + Horizontal, нечётные строки смещены вправо.
static func offset_to_axial(map_cell: Vector2i) -> Vector2i:
	var q := map_cell.x - floori(map_cell.y / 2.0)
	return Vector2i(q, map_cell.y)


## Преобразует осевую координату (q, r) обратно в координату TileMapLayer.
static func axial_to_offset(hex: Vector2i) -> Vector2i:
	var column := hex.x + floori(hex.y / 2.0)
	return Vector2i(column, hex.y)
