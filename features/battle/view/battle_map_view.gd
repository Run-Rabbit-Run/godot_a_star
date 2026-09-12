class_name BattleMapView
extends Node2D


@onready var _terrain_layer: TileMapLayer = %TerrainLayer
@onready var _reachable_layer: TileMapLayer = %ReachableLayer
@onready var _path_layer: TileMapLayer = %PathLayer
@onready var _targetable_layer: TileMapLayer = %TargetableLayer
@onready var _selection_layer: TileMapLayer = %SelectionLayer
@onready var _highlight_layer: TileMapLayer = %HighlightLayer
@onready var _input_router: BattleInputRouter = %BattleInputRouter

var _default_source_id := -1
var _default_atlas_coords := Vector2i.ZERO
var _default_alternative_tile := 0


func _ready() -> void:
	_input_router.hex_hovered.connect(_show_hover)
	_input_router.hex_hover_exited.connect(_clear_hover)
	_capture_default_terrain_tile()


func render_grid(grid: HexGrid) -> void:
	if grid == null:
		return

	if _default_source_id == -1:
		_capture_default_terrain_tile()

	_terrain_layer.clear()
	clear_overlays()

	if _default_source_id == -1:
		return

	for hex: Vector2i in grid.get_cells():
		var map_cell := HexCoordinateMapper.axial_to_offset(hex)
		_terrain_layer.set_cell(
			map_cell,
			_default_source_id,
			_default_atlas_coords,
			_default_alternative_tile
		)


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

func apply_map_event(event: MapMutationEvent) -> void:
	if event == null:
		return

	clear_overlays()
	var map_cell := HexCoordinateMapper.axial_to_offset(event.hex)

	if event.kind == MapMutationKind.Value.REMOVE_HEX:
		_terrain_layer.erase_cell(map_cell)
		return

	if event.kind == MapMutationKind.Value.ADD_HEX:
		if _default_source_id == -1:
			push_warning("No terrain tile is available for AddHex presentation.")
			return

		_terrain_layer.set_cell(
			map_cell,
			_default_source_id,
			_default_atlas_coords,
			_default_alternative_tile
		)


func _capture_default_terrain_tile() -> void:
	var used_cells := _terrain_layer.get_used_cells()

	if used_cells.is_empty():
		return

	var sample: Vector2i = used_cells[0]
	_default_source_id = _terrain_layer.get_cell_source_id(sample)
	_default_atlas_coords = _terrain_layer.get_cell_atlas_coords(sample)
	_default_alternative_tile = _terrain_layer.get_cell_alternative_tile(sample)

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
