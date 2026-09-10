class_name BattleMapView
extends Node2D


@onready var _terrain_layer: TileMapLayer = %TerrainLayer
@onready var _reachable_layer: TileMapLayer = %ReachableLayer
@onready var _path_layer: TileMapLayer = %PathLayer
@onready var _targetable_layer: TileMapLayer = %TargetableLayer
@onready var _selection_layer: TileMapLayer = %SelectionLayer
@onready var _highlight_layer: TileMapLayer = %HighlightLayer
@onready var _input_router: BattleInputRouter = %BattleInputRouter


func _ready() -> void:
	_input_router.hex_hovered.connect(_show_hover)
	_input_router.hex_hover_exited.connect(_clear_hover)


func hex_to_global_position(axial_cell: Vector2i) -> Vector2:
	var map_cell := HexCoordinateMapper.axial_to_offset(axial_cell)
	var local_position := _terrain_layer.map_to_local(map_cell)

	return _terrain_layer.to_global(local_position)


func show_selected_hex(axial_cell: Vector2i) -> void:
	_selection_layer.clear()
	_paint_cell_on_layer(axial_cell, _selection_layer)


func show_reachable_cells(cells: Array[Vector2i]) -> void:
	_reachable_layer.clear()

	for cell in cells:
		_paint_cell_on_layer(cell, _reachable_layer)


func show_path(cells: Array[Vector2i]) -> void:
	clear_path()

	for cell in cells:
		_paint_cell_on_layer(cell, _path_layer)


func show_targetable_cells(cells: Array[Vector2i]) -> void:
	_targetable_layer.clear()

	for cell in cells:
		_paint_cell_on_layer(cell, _targetable_layer)


func clear_path() -> void:
	_path_layer.clear()


func clear_overlays() -> void:
	_reachable_layer.clear()
	_path_layer.clear()
	_targetable_layer.clear()
	_selection_layer.clear()
	_highlight_layer.clear()


func _show_hover(axial_cell: Vector2i) -> void:
	_highlight_layer.clear()
	_paint_cell_on_layer(axial_cell, _highlight_layer)


## Слои представления копируют внешний вид TerrainLayer и не решают игровых правил.
func _paint_cell_on_layer(
	axial_cell: Vector2i,
	target_layer: TileMapLayer
) -> void:
	var map_cell := HexCoordinateMapper.axial_to_offset(axial_cell)
	var source_id := _terrain_layer.get_cell_source_id(map_cell)

	if source_id == -1:
		return

	target_layer.set_cell(
		map_cell,
		source_id,
		_terrain_layer.get_cell_atlas_coords(map_cell),
		_terrain_layer.get_cell_alternative_tile(map_cell)
	)


func _clear_hover() -> void:
	_highlight_layer.clear()
