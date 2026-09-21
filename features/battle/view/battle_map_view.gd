class_name BattleMapView
extends Node2D


const BATTLE_BACKDROP := preload(
	"res://features/battle/art/forest_outskirts_battlefield_v1.png"
)
const CURSOR_DEFAULT := preload(
	"res://features/battle/ui/icons/cursor_default.svg"
)
const CURSOR_MELEE := preload(
	"res://features/battle/ui/icons/cursor_melee.svg"
)
const CURSOR_RANGED := preload(
	"res://features/battle/ui/icons/cursor_ranged.svg"
)
const HEX_STATE_MANIFEST_PATH := "res://features/battle/art/hex_states/manifest.json"
const HEX_STATE_TEXTURES := {
	&"core:electricity": preload("res://features/battle/art/hex_states/01-electricity.png"),
	&"core:water": preload("res://features/battle/art/hex_states/02-water.png"),
	&"core:fire": preload("res://features/battle/art/hex_states/03-fire.png"),
	&"core:oil": preload("res://features/battle/art/hex_states/04-oil.png"),
	&"core:acid": preload("res://features/battle/art/hex_states/05-acid.png"),
	&"core:electrified_water": preload("res://features/battle/art/hex_states/06-electrified-water.png"),
	&"core:plasma": preload("res://features/battle/art/hex_states/07-plasma.png"),
	&"core:electrified_acid": preload("res://features/battle/art/hex_states/08-electrified-acid.png"),
	&"core:steam": preload("res://features/battle/art/hex_states/09-steam.png"),
	&"core:boiling_acid": preload("res://features/battle/art/hex_states/10-boiling-acid.png"),
	&"core:burning_oil": preload("res://features/battle/art/hex_states/11-burning-oil.png"),
	&"core:acid_vapour": preload("res://features/battle/art/hex_states/12-acid-vapour.png"),
}
const HEX_STATE_ASSET_IDS := {
	&"core:electricity": "01-electricity",
	&"core:water": "02-water",
	&"core:fire": "03-fire",
	&"core:oil": "04-oil",
	&"core:acid": "05-acid",
	&"core:electrified_water": "06-electrified-water",
	&"core:plasma": "07-plasma",
	&"core:electrified_acid": "08-electrified-acid",
	&"core:steam": "09-steam",
	&"core:boiling_acid": "10-boiling-acid",
	&"core:burning_oil": "11-burning-oil",
	&"core:acid_vapour": "12-acid-vapour",
}
enum CursorMode { DEFAULT, MELEE, RANGED }
const GRID_TILE_SIZE := Vector2(56.0, 64.0)
const SAFE_SIDE_MARGIN := 270.0
const SAFE_TOP_MARGIN := 112.0
const SAFE_BOTTOM_MARGIN := 168.0
const MAX_BATTLEFIELD_SCALE := 1.15


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
var _grid_local_bounds := Rect2()
var _path_shadow: Line2D
var _path_stroke: Line2D
var _grenade_target_visuals: Node2D
var _grenade_area_visuals: Node2D
var _reachable_visuals: Node2D
var _selection_visuals: Node2D
var _hover_visuals: Node2D
var _hex_state_visuals: Node2D
var _hex_state_placements: Dictionary = {}
var _cursor_mode := CursorMode.DEFAULT


func _enter_tree() -> void:
	_mount_battle_backdrop()
	_fit_battle_backdrop()

	if not get_viewport().size_changed.is_connected(_fit_battle_backdrop):
		get_viewport().size_changed.connect(_fit_battle_backdrop)


func _ready() -> void:
	_apply_visual_profile()
	_input_router.hex_hovered.connect(_show_hover)
	_input_router.hex_hover_exited.connect(_clear_hover)
	_capture_terrain_tiles()
	_mount_hex_state_visuals()
	_load_hex_state_placements()
	_mount_path_visuals()
	_mount_grenade_visuals()
	_mount_interaction_visuals()
	set_cursor_mode(CursorMode.DEFAULT)
	_fit_battlefield_to_viewport()

	if not get_viewport().size_changed.is_connected(
		_fit_battlefield_to_viewport
	):
		get_viewport().size_changed.connect(_fit_battlefield_to_viewport)


func _exit_tree() -> void:
	if DisplayServer.get_name() != "headless":
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)


func set_cursor_mode(mode: CursorMode) -> void:
	_cursor_mode = mode

	if DisplayServer.get_name() == "headless":
		return

	match mode:
		CursorMode.MELEE:
			Input.set_custom_mouse_cursor(
				CURSOR_MELEE,
				Input.CURSOR_ARROW,
				Vector2(24, 24)
			)
		CursorMode.RANGED:
			Input.set_custom_mouse_cursor(
				CURSOR_RANGED,
				Input.CURSOR_ARROW,
				Vector2(24, 24)
			)
		_:
			Input.set_custom_mouse_cursor(
				CURSOR_DEFAULT,
				Input.CURSOR_ARROW,
				Vector2(5, 3)
			)


func _mount_battle_backdrop() -> void:
	var backdrop_layer := CanvasLayer.new()
	backdrop_layer.name = "BattleBackdropLayer"
	backdrop_layer.layer = -20
	add_child(backdrop_layer)

	_battle_backdrop = TextureRect.new()
	_battle_backdrop.name = "BattleBackdrop"
	_battle_backdrop.texture = BATTLE_BACKDROP
	_battle_backdrop.modulate = Color(0.96, 0.97, 0.95)
	_battle_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_battle_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_battle_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop_layer.add_child(_battle_backdrop)


func _mount_hex_state_visuals() -> void:
	_hex_state_visuals = Node2D.new()
	_hex_state_visuals.name = "HexStateVisuals"
	_hex_state_visuals.z_index = 5
	add_child(_hex_state_visuals)


func _load_hex_state_placements() -> void:
	var file := FileAccess.open(HEX_STATE_MANIFEST_PATH, FileAccess.READ)

	if file == null:
		push_error("Hex state visual manifest could not be opened.")
		return

	var manifest := JSON.parse_string(file.get_as_text()) as Dictionary

	if manifest == null:
		push_error("Hex state visual manifest is invalid JSON.")
		return

	for item: Variant in manifest.get("assets", []):
		if item is not Dictionary:
			continue

		var entry := item as Dictionary
		_hex_state_placements[String(entry.get("id", ""))] = entry


func _render_hex_states(grid: HexGrid) -> void:
	for child: Node in _hex_state_visuals.get_children():
		_hex_state_visuals.remove_child(child)
		child.queue_free()

	for hex: Vector2i in grid.get_cells():
		var state_id := grid.get_hex_state_id(hex)

		if state_id.is_empty():
			continue

		var texture := HEX_STATE_TEXTURES.get(state_id) as Texture2D
		var asset_id := String(HEX_STATE_ASSET_IDS.get(state_id, ""))
		var placement := _hex_state_placements.get(asset_id) as Dictionary

		if texture == null or placement == null:
			push_warning("Hex state visual is missing for %s." % state_id)
			continue

		var anchor_values: Array = placement.get("anchor_px", [])

		if anchor_values.size() != 2:
			push_warning("Hex state anchor is invalid for %s." % state_id)
			continue

		var sprite := Sprite2D.new()
		var sprite_scale := float(placement.get("sprite_scale_for_local_hex_56x64", 0.0))

		if sprite_scale <= 0.0:
			push_warning("Hex state scale is invalid for %s." % state_id)
			continue

		sprite.name = "HexState_%d_%d" % [hex.x, hex.y]
		sprite.texture = texture
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.scale = Vector2.ONE * sprite_scale
		var center := to_local(
			_terrain_layer.to_global(
				_terrain_layer.map_to_local(HexCoordinateMapper.axial_to_offset(hex))
			)
		)
		var anchor := Vector2(float(anchor_values[0]), float(anchor_values[1]))
		sprite.position = center - anchor * sprite_scale
		_hex_state_visuals.add_child(sprite)

func _mount_path_visuals() -> void:
	_path_shadow = Line2D.new()
	_path_shadow.name = "PathShadow"
	_path_shadow.width = 9.0
	_path_shadow.default_color = Color(0.08, 0.09, 0.085, 0.80)
	_path_shadow.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_path_shadow.end_cap_mode = Line2D.LINE_CAP_ROUND
	_path_shadow.joint_mode = Line2D.LINE_JOINT_ROUND
	_path_shadow.antialiased = true
	_path_shadow.z_index = 1
	_path_layer.add_child(_path_shadow)

	_path_stroke = Line2D.new()
	_path_stroke.name = "PathStroke"
	_path_stroke.width = 4.5
	_path_stroke.default_color = Color(0.88, 0.86, 0.75, 0.96)
	_path_stroke.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_path_stroke.end_cap_mode = Line2D.LINE_CAP_ROUND
	_path_stroke.joint_mode = Line2D.LINE_JOINT_ROUND
	_path_stroke.antialiased = true
	_path_stroke.z_index = 2
	_path_layer.add_child(_path_stroke)


func _mount_grenade_visuals() -> void:
	_grenade_target_visuals = Node2D.new()
	_grenade_target_visuals.name = "GrenadeTargetVisuals"
	_grenade_target_visuals.z_index = 10
	add_child(_grenade_target_visuals)

	_grenade_area_visuals = Node2D.new()
	_grenade_area_visuals.name = "GrenadeAreaVisuals"
	_grenade_area_visuals.z_index = 14
	add_child(_grenade_area_visuals)


func _mount_interaction_visuals() -> void:
	_reachable_visuals = Node2D.new()
	_reachable_visuals.name = "ReachableVisuals"
	_reachable_visuals.z_index = 8
	add_child(_reachable_visuals)

	_selection_visuals = Node2D.new()
	_selection_visuals.name = "SelectionVisuals"
	_selection_visuals.z_index = 12
	add_child(_selection_visuals)

	_hover_visuals = Node2D.new()
	_hover_visuals.name = "HoverVisuals"
	_hover_visuals.z_index = 13
	add_child(_hover_visuals)

func _fit_battle_backdrop() -> void:
	if _battle_backdrop == null:
		return

	_battle_backdrop.position = Vector2.ZERO
	_battle_backdrop.size = get_viewport().get_visible_rect().size


func _fit_battlefield_to_viewport() -> void:
	if not is_node_ready():
		return

	_grid_local_bounds = _calculate_grid_local_bounds()

	if _grid_local_bounds.size == Vector2.ZERO:
		return

	var viewport_size := get_viewport().get_visible_rect().size
	var available_size := Vector2(
		maxf(viewport_size.x - SAFE_SIDE_MARGIN * 2.0, 1.0),
		maxf(
			viewport_size.y - SAFE_TOP_MARGIN - SAFE_BOTTOM_MARGIN,
			1.0
		)
	)
	var fitted_scale := minf(
		MAX_BATTLEFIELD_SCALE,
		minf(
			available_size.x / _grid_local_bounds.size.x,
			available_size.y / _grid_local_bounds.size.y
		)
	)
	var safe_center := Vector2(
		viewport_size.x * 0.5,
		SAFE_TOP_MARGIN + available_size.y * 0.5
	)

	scale = Vector2.ONE * fitted_scale
	position = (
		safe_center
		- _grid_local_bounds.get_center() * fitted_scale
	)


func _calculate_grid_local_bounds() -> Rect2:
	var used_cells := _terrain_layer.get_used_cells()

	if used_cells.is_empty():
		return Rect2()

	var first_center := _terrain_layer.map_to_local(used_cells[0])
	var minimum := first_center
	var maximum := first_center

	for map_cell: Vector2i in used_cells:
		var cell_center := _terrain_layer.map_to_local(map_cell)
		minimum.x = minf(minimum.x, cell_center.x)
		minimum.y = minf(minimum.y, cell_center.y)
		maximum.x = maxf(maximum.x, cell_center.x)
		maximum.y = maxf(maximum.y, cell_center.y)

	return Rect2(
		minimum - GRID_TILE_SIZE * 0.5,
		maximum - minimum + GRID_TILE_SIZE
	)


func _apply_visual_profile() -> void:
	# Цвет не кодирует правила: он только делает слои читаемыми на живописном фоне.
	_background_layer.modulate = Color(0.68, 0.69, 0.64, 0.035)
	_terrain_layer.modulate = Color(0.92, 0.93, 0.89, 0.46)
	_reachable_layer.modulate = Color(0.90, 0.88, 0.76, 0.44)
	_path_layer.modulate = Color(0.92, 0.90, 0.79, 0.82)
	_targetable_layer.modulate = Color(0.55, 0.20, 0.18, 0.50)
	_ability_area_layer.modulate = Color(0.74, 0.25, 0.17, 0.62)
	_selection_layer.modulate = Color(0.92, 0.90, 0.75, 0.66)
	_highlight_layer.modulate = Color(0.82, 0.82, 0.73, 0.34)


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

	_render_hex_states(grid)
	_fit_battlefield_to_viewport()


func get_grid_global_bounds() -> Rect2:
	if _grid_local_bounds.size == Vector2.ZERO:
		_grid_local_bounds = _calculate_grid_local_bounds()

	if _grid_local_bounds.size == Vector2.ZERO:
		return Rect2()

	var top_left := _terrain_layer.to_global(_grid_local_bounds.position)
	var bottom_right := _terrain_layer.to_global(_grid_local_bounds.end)
	return Rect2(top_left, bottom_right - top_left)


func hex_to_global_position(axial_cell: Vector2i) -> Vector2:
	var map_cell := HexCoordinateMapper.axial_to_offset(axial_cell)
	var local_position := _terrain_layer.map_to_local(map_cell)

	return _terrain_layer.to_global(local_position)


func show_selected_hex(axial_cell: Vector2i) -> void:
	_selection_layer.clear()
	_clear_hex_visuals(_selection_visuals)
	_paint_cell_on_layer(axial_cell, _selection_layer)
	_add_hex_visual(
		_selection_visuals,
		axial_cell,
		Color(0.92, 0.90, 0.75, 0.10),
		Color(0.94, 0.92, 0.78, 0.88),
		1.7
	)


func show_reachable_cells(cells: Array[Vector2i]) -> void:
	_reachable_layer.clear()
	_clear_hex_visuals(_reachable_visuals)

	for cell in cells:
		_paint_cell_on_layer(cell, _reachable_layer)
		_add_hex_visual(
			_reachable_visuals,
			cell,
			Color(0.86, 0.85, 0.76, 0.035),
			Color(0.88, 0.87, 0.78, 0.42),
			1.05
		)


func show_path(cells: Array[Vector2i]) -> void:
	clear_path()

	for cell in cells:
		_paint_cell_on_layer(cell, _path_layer)

	_show_path_polyline(cells)


func show_targetable_cells(cells: Array[Vector2i]) -> void:
	_targetable_layer.clear()
	_clear_hex_visuals(_grenade_target_visuals)

	for cell in cells:
		_paint_cell_on_layer(cell, _targetable_layer)


func show_grenade_targets(cells: Array[Vector2i]) -> void:
	_clear_hex_visuals(_grenade_target_visuals)

	for cell in cells:
		_add_hex_visual(
			_grenade_target_visuals,
			cell,
			Color(0.92, 0.38, 0.12, 0.16),
			Color(1.0, 0.62, 0.25, 0.72),
			1.4
		)


func show_ability_area(cells: Array[Vector2i]) -> void:
	clear_ability_area()

	for cell in cells:
		_paint_cell_on_layer(cell, _ability_area_layer)
		_add_hex_visual(
			_grenade_area_visuals,
			cell,
			Color(0.96, 0.21, 0.10, 0.36),
			Color(1.0, 0.75, 0.30, 0.98),
			2.8
		)


func clear_ability_area() -> void:
	_ability_area_layer.clear()
	_clear_hex_visuals(_grenade_area_visuals)


func clear_path() -> void:
	_path_layer.clear()

	if _path_shadow != null:
		_path_shadow.clear_points()

	if _path_stroke != null:
		_path_stroke.clear_points()


func clear_overlays() -> void:
	_reachable_layer.clear()
	_clear_hex_visuals(_reachable_visuals)
	clear_path()
	_targetable_layer.clear()
	_clear_hex_visuals(_grenade_target_visuals)
	clear_ability_area()
	_selection_layer.clear()
	_clear_hex_visuals(_selection_visuals)
	_highlight_layer.clear()
	_clear_hex_visuals(_hover_visuals)

func apply_map_event(event: MapMutationEvent) -> void:
	if event == null:
		return

	clear_overlays()
	var map_cell := HexCoordinateMapper.axial_to_offset(event.hex)

	if event.kind == MapMutationKind.Value.REMOVE_HEX:
		_terrain_layer.erase_cell(map_cell)
		var state_sprite := _hex_state_visuals.get_node_or_null(
			"HexState_%d_%d" % [event.hex.x, event.hex.y]
		)
		if state_sprite != null:
			state_sprite.queue_free()
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


func _get_terrain_tile(_movement_cost: int) -> Dictionary:
	return _terrain_tiles_by_movement_cost.get(
		1,
		{
			"source_id": _default_source_id,
			"atlas_coords": _default_atlas_coords,
			"alternative_tile": _default_alternative_tile,
		}
	)

func _show_hover(axial_cell: Vector2i) -> void:
	_highlight_layer.clear()
	_clear_hex_visuals(_hover_visuals)
	_paint_cell_on_layer(axial_cell, _highlight_layer)
	_add_hex_visual(
		_hover_visuals,
		axial_cell,
		Color(0.84, 0.84, 0.76, 0.045),
		Color(0.91, 0.90, 0.81, 0.52),
		1.2
	)


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


func _clear_hex_visuals(container: Node2D) -> void:
	if container == null:
		return

	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _add_hex_visual(
	container: Node2D,
	axial_cell: Vector2i,
	fill_color: Color,
	outline_color: Color,
	outline_width: float
) -> void:
	if container == null:
		return

	var map_cell := HexCoordinateMapper.axial_to_offset(axial_cell)

	if _terrain_layer.get_cell_source_id(map_cell) == -1:
		return

	var center := to_local(
		_terrain_layer.to_global(_terrain_layer.map_to_local(map_cell))
	)
	var corners := PackedVector2Array([
		Vector2(0, -31),
		Vector2(27, -15.5),
		Vector2(27, 15.5),
		Vector2(0, 31),
		Vector2(-27, 15.5),
		Vector2(-27, -15.5),
	])

	var fill := Polygon2D.new()
	fill.position = center
	fill.polygon = corners
	fill.color = fill_color
	container.add_child(fill)

	var outline := Line2D.new()
	outline.position = center
	outline.points = PackedVector2Array([
		corners[0],
		corners[1],
		corners[2],
		corners[3],
		corners[4],
		corners[5],
		corners[0],
	])
	outline.width = outline_width
	outline.default_color = outline_color
	outline.joint_mode = Line2D.LINE_JOINT_ROUND
	outline.antialiased = true
	container.add_child(outline)


func _show_path_polyline(cells: Array[Vector2i]) -> void:
	if _path_shadow == null or _path_stroke == null:
		return

	var points := PackedVector2Array()

	for axial_cell: Vector2i in cells:
		var map_cell := HexCoordinateMapper.axial_to_offset(axial_cell)

		if _terrain_layer.get_cell_source_id(map_cell) == -1:
			continue

		points.append(_terrain_layer.map_to_local(map_cell))

	_path_shadow.points = points
	_path_stroke.points = points


func _clear_hover() -> void:
	_highlight_layer.clear()
	_clear_hex_visuals(_hover_visuals)
