class_name BattleMapView
extends Node2D


const BATTLE_BACKDROP := preload(
	"res://features/battle/art/fungal_mire_battlefield_v2.png"
)
const BATTLEFIELD_OFFSET := Vector2(350.0, 80.0)
const BATTLEFIELD_SCALE := Vector2(1.15, 1.15)


@onready var _background_layer: TileMapLayer = $BackgroundLayer
@onready var _terrain_layer: TileMapLayer = %TerrainLayer
@onready var _reachable_layer: TileMapLayer = %ReachableLayer
@onready var _path_layer: TileMapLayer = %PathLayer
@onready var _targetable_layer: TileMapLayer = %TargetableLayer
@onready var _ability_area_layer: TileMapLayer = %AbilityAreaLayer
@onready var _selection_layer: TileMapLayer = %SelectionLayer
@onready var _highlight_layer: TileMapLayer = %HighlightLayer
@onready var _input_router: BattleInputRouter = %BattleInputRouter

var _default_source_id := -1
var _default_atlas_coords := Vector2i.ZERO
var _default_alternative_tile := 0
var _terrain_tiles_by_movement_cost: Dictionary = {}
var _battle_backdrop: TextureRect


func _enter_tree() -> void:
	_mount_battle_backdrop()
	_fit_battle_backdrop()

	if not get_viewport().size_changed.is_connected(_fit_battle_backdrop):
		get_viewport().size_changed.connect(_fit_battle_backdrop)


func _ready() -> void:
	position = BATTLEFIELD_OFFSET
	scale = BATTLEFIELD_SCALE
	_apply_visual_profile()
	_input_router.hex_hovered.connect(_show_hover)
	_input_router.hex_hover_exited.connect(_clear_hover)
	_capture_terrain_tiles()


func _mount_battle_backdrop() -> void:
	var backdrop_layer := CanvasLayer.new()
	backdrop_layer.name = "BattleBackdropLayer"
	backdrop_layer.layer = -20
	add_child(backdrop_layer)

	_battle_backdrop = TextureRect.new()
	_battle_backdrop.name = "BattleBackdrop"
	_battle_backdrop.texture = BATTLE_BACKDROP
	_battle_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_battle_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_battle_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop_layer.add_child(_battle_backdrop)


func _fit_battle_backdrop() -> void:
	if _battle_backdrop == null:
		return

	_battle_backdrop.position = Vector2.ZERO
	_battle_backdrop.size = get_viewport().get_visible_rect().size


func _apply_visual_profile() -> void:
	# Цвет не кодирует правила: он только делает слои читаемыми на живописном фоне.
	_background_layer.modulate = Color(0.64, 0.70, 0.67, 0.18)
	_reachable_layer.modulate = Color(0.83, 0.79, 0.61, 0.46)
	_path_layer.modulate = Color(0.86, 0.72, 0.40, 0.64)
	_targetable_layer.modulate = Color(0.66, 0.25, 0.20, 0.58)
	_ability_area_layer.modulate = Color(0.92, 0.25, 0.18, 0.66)
	_selection_layer.modulate = Color(0.91, 0.86, 0.67, 0.72)
	_highlight_layer.modulate = Color(0.72, 0.73, 0.63, 0.48)


func render_grid(grid: HexGrid) -> void:
	if grid == null:
		return

	if _default_source_id == -1:
		_capture_terrain_tiles()

	_terrain_layer.clear()
	clear_overlays()

	if _default_source_id == -1:
		return

	for hex: Vector2i in grid.get_cells():
		var map_cell := HexCoordinateMapper.axial_to_offset(hex)
		var tile := _get_terrain_tile(
			grid.get_configured_movement_cost(hex)
		)
		_terrain_layer.set_cell(
			map_cell,
			tile["source_id"],
			tile["atlas_coords"],
			tile["alternative_tile"]
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


func show_ability_area(cells: Array[Vector2i]) -> void:
	_ability_area_layer.clear()

	for cell in cells:
		_paint_cell_on_layer(cell, _ability_area_layer)


func clear_ability_area() -> void:
	_ability_area_layer.clear()


func clear_path() -> void:
	_path_layer.clear()


func clear_overlays() -> void:
	_reachable_layer.clear()
	_path_layer.clear()
	_targetable_layer.clear()
	_ability_area_layer.clear()
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

		var tile := _get_terrain_tile(event.movement_cost)
		_terrain_layer.set_cell(
			map_cell,
			tile["source_id"],
			tile["atlas_coords"],
			tile["alternative_tile"]
		)


func _capture_terrain_tiles() -> void:
	var used_cells := _terrain_layer.get_used_cells()

	if used_cells.is_empty():
		return

	var sample: Vector2i = used_cells[0]
	_default_source_id = _terrain_layer.get_cell_source_id(sample)
	_default_atlas_coords = _terrain_layer.get_cell_atlas_coords(sample)
	_default_alternative_tile = _terrain_layer.get_cell_alternative_tile(sample)

	for map_cell: Vector2i in used_cells:
		var tile_data := _terrain_layer.get_cell_tile_data(map_cell)
		var movement_cost := 1

		if tile_data != null and tile_data.has_custom_data("movement_cost"):
			movement_cost = int(tile_data.get_custom_data("movement_cost"))

		if _terrain_tiles_by_movement_cost.has(movement_cost):
			continue

		_terrain_tiles_by_movement_cost[movement_cost] = {
			"source_id": _terrain_layer.get_cell_source_id(map_cell),
			"atlas_coords": _terrain_layer.get_cell_atlas_coords(map_cell),
			"alternative_tile": _terrain_layer.get_cell_alternative_tile(map_cell),
		}


func _get_terrain_tile(movement_cost: int) -> Dictionary:
	return _terrain_tiles_by_movement_cost.get(
		movement_cost,
		{
			"source_id": _default_source_id,
			"atlas_coords": _default_atlas_coords,
			"alternative_tile": _default_alternative_tile,
		}
	)

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
