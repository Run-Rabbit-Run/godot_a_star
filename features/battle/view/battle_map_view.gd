class_name BattleMapView
extends Node2D


const BATTLE_BACKDROP := preload(
	"res://features/battle/art/plateau.png"
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
enum CursorMode { DEFAULT, MELEE, RANGED }
const GRID_TILE_SIZE := Vector2(56.0, 64.0)


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
var _ability_target_visuals: Node2D
var _ability_area_visuals: Node2D
var _reachable_visuals: Node2D
var _ranged_attack_visuals: Node2D
var _selection_visuals: Node2D
var _hover_visuals: Node2D
var _hex_state_visuals: HexStateRenderer
var _cursor_mode := CursorMode.DEFAULT
var _grid_rulers: Node2D
var _terrain_property_visuals: Node2D
var _terrain_property_nodes: Dictionary[Vector2i, Node2D] = {}
var _displayed_properties: Dictionary[Vector2i, Dictionary] = {}

var _presentation_frame := Vector2i.ZERO


func set_map_presentation(definition: BattleMapDefinition) -> void:
	_presentation_frame = definition.presentation_frame
	_battle_backdrop.texture = BattleBackdrops.texture(definition.background_id)
	_fit_battlefield_to_viewport()


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
	_mount_path_visuals()
	_mount_ability_visuals()
	_mount_interaction_visuals()
	_terrain_property_visuals = Node2D.new()
	_terrain_property_visuals.name = "TerrainProperties"
	# Same layer as hex-state art but added later, so blocked/cost markers stay visible
	# above it while corpses (6) and tactical overlays (8+) still cover them.
	_terrain_property_visuals.z_index = 5
	add_child(_terrain_property_visuals)
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
	_battle_backdrop.modulate = Color.WHITE
	_battle_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_battle_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_battle_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop_layer.add_child(_battle_backdrop)


func _mount_hex_state_visuals() -> void:
	_hex_state_visuals = HexStateRenderer.new()
	_hex_state_visuals.name = "HexStateVisuals"
	_hex_state_visuals.z_index = 5
	add_child(_hex_state_visuals)
	_hex_state_visuals.setup(_terrain_layer)

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


func _mount_ability_visuals() -> void:
	_ability_target_visuals = Node2D.new()
	_ability_target_visuals.name = "AbilityTargetVisuals"
	_ability_target_visuals.z_index = 10
	add_child(_ability_target_visuals)

	_ability_area_visuals = Node2D.new()
	_ability_area_visuals.name = "AbilityAreaVisuals"
	_ability_area_visuals.z_index = 14
	add_child(_ability_area_visuals)


func _mount_interaction_visuals() -> void:
	_reachable_visuals = Node2D.new()
	_reachable_visuals.name = "ReachableVisuals"
	_reachable_visuals.z_index = 8
	add_child(_reachable_visuals)

	_ranged_attack_visuals = Node2D.new()
	_ranged_attack_visuals.name = "RangedAttackVisuals"
	_ranged_attack_visuals.z_index = 9
	add_child(_ranged_attack_visuals)

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
	# Match the reference's 94 x 78 projected hexes at 1920 x 1080.
	var screen_scale := minf(viewport_size.x / 1920.0, viewport_size.y / 1080.0)
	var available_size := Vector2(1739.0, 721.5) * screen_scale
	scale = available_size / _grid_local_bounds.size
	position = viewport_size * 0.5 + Vector2(0, -21.25) * screen_scale - _grid_local_bounds.get_center() * scale
	# Figures stay upright, independent of the board's perspective compression.
	var units := get_node_or_null("Units") as Node2D
	if units != null:
		for actor: Node2D in units.get_children():
			actor.scale = Vector2.ONE * screen_scale / scale
	_rebuild_grid_rulers(screen_scale)
	# Marker text depends on the board scale, which has just changed.
	_refresh_terrain_properties()


func _rebuild_grid_rulers(screen_scale: float) -> void:
	if _grid_rulers == null:
		_grid_rulers = Node2D.new()
		_grid_rulers.name = "GridRulers"
		add_child(_grid_rulers)
	_clear_hex_visuals(_grid_rulers)
	var bounds := _terrain_layer.get_used_rect()
	if _presentation_frame.x > 0 and _presentation_frame.y > 0:
		bounds = Rect2i(Vector2i.ZERO, _presentation_frame)
	var label_scale := Vector2.ONE * screen_scale / scale
	for column in range(bounds.position.x, bounds.end.x):
		var center := _terrain_layer.map_to_local(Vector2i(column, bounds.position.y))
		_add_grid_number(column - bounds.position.x + 1, center + Vector2(0, -42), label_scale)
	for row in range(bounds.position.y, bounds.end.y):
		var center := _terrain_layer.map_to_local(Vector2i(bounds.position.x, row))
		center.x = _grid_local_bounds.position.x - 8
		_add_grid_number(row - bounds.position.y + 1, center, label_scale)


func _add_grid_number(number: int, center: Vector2, label_scale: Vector2) -> void:
	var label := Label.new()
	label.text = "%02d" % number
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color("463831"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size = Vector2(24, 18)
	label.scale = label_scale
	label.position = center - label.size * label_scale * 0.5
	_grid_rulers.add_child(label)



func _calculate_grid_local_bounds() -> Rect2:
	var used_cells := _terrain_layer.get_used_cells()
	if _presentation_frame.x > 0 and _presentation_frame.y > 0:
		used_cells.clear()
		for row in range(_presentation_frame.y):
			for column in range(_presentation_frame.x):
				used_cells.append(Vector2i(column, row))

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
	_background_layer.visible = false
	_terrain_layer.modulate = Color.WHITE
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
	_displayed_properties.clear()
	_clear_hex_visuals(_terrain_property_visuals)
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

	for hex: Vector2i in grid.get_cells():
		_displayed_properties[hex] = {"terrain": grid.get_terrain_id(hex), "traversable": grid.is_traversable(hex), "cost": grid.get_configured_movement_cost(hex)}
	_refresh_terrain_properties()
	_hex_state_visuals.render(grid)
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
		_add_hex_visual(
			_reachable_visuals,
			cell,
			Color(0.51, 0.75, 0.75, 0.20),
			Color(0.67, 0.86, 0.86, 0.70),
			1.05
		)


func show_path(cells: Array[Vector2i]) -> void:
	clear_path()

	for cell in cells:
		_paint_cell_on_layer(cell, _path_layer)

	_show_path_polyline(cells)


func show_targetable_cells(cells: Array[Vector2i]) -> void:
	_targetable_layer.clear()
	_clear_hex_visuals(_ability_target_visuals)

	for cell in cells:
		_paint_cell_on_layer(cell, _targetable_layer)


func show_ranged_attack_cells(
	cells: Array[Vector2i],
	enemy_cells: Array[Vector2i]
) -> void:
	clear_ranged_attack_cells()
	var region: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in cells:
		region[cell] = true
	var corners := PackedVector2Array([
		Vector2(0, -32), Vector2(28, -16), Vector2(28, 16),
		Vector2(0, 32), Vector2(-28, 16), Vector2(-28, -16),
	])
	# Neighbour across each edge, clockwise from the upper-right edge.
	var neighbours: Array[Vector2i] = [
		Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1),
		Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1),
	]

	for cell: Vector2i in cells:
		var map_cell := HexCoordinateMapper.axial_to_offset(cell)
		if _terrain_layer.get_cell_source_id(map_cell) == -1:
			continue
		var center := to_local(hex_to_global_position(cell))
		if enemy_cells.has(cell):
			var fill := Polygon2D.new()
			fill.position = center
			fill.polygon = corners
			fill.color = Color(0.92, 0.20, 0.16, 0.20)
			_ranged_attack_visuals.add_child(fill)
		for edge in range(6):
			if region.has(cell + neighbours[edge]):
				continue
			_add_attack_boundary_edge(center + corners[edge], center + corners[(edge + 1) % 6])


func _add_attack_boundary_edge(start: Vector2, end: Vector2) -> void:
	var length := start.distance_to(end)
	var direction := (end - start).normalized()
	var offset := 0.0
	while offset < length:
		var dash := Line2D.new()
		dash.points = PackedVector2Array([
			start + direction * offset,
			start + direction * minf(offset + 7.0, length),
		])
		dash.width = 1.8
		dash.default_color = Color(1.0, 0.56, 0.16, 0.90)
		dash.antialiased = true
		_ranged_attack_visuals.add_child(dash)
		offset += 11.0


func clear_ranged_attack_cells() -> void:
	_clear_hex_visuals(_ranged_attack_visuals)


func show_ability_targets(cells: Array[Vector2i]) -> void:
	_clear_hex_visuals(_ability_target_visuals)

	for cell in cells:
		_add_hex_visual(
			_ability_target_visuals,
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
			_ability_area_visuals,
			cell,
			Color(0.96, 0.21, 0.10, 0.36),
			Color(1.0, 0.75, 0.30, 0.98),
			2.8
		)


func clear_ability_area() -> void:
	_ability_area_layer.clear()
	_clear_hex_visuals(_ability_area_visuals)


func clear_path() -> void:
	_path_layer.clear()

	if _path_shadow != null:
		_path_shadow.clear_points()

	if _path_stroke != null:
		_path_stroke.clear_points()


func clear_overlays() -> void:
	clear_ranged_attack_cells()
	_reachable_layer.clear()
	_clear_hex_visuals(_reachable_visuals)
	clear_path()
	_targetable_layer.clear()
	_clear_hex_visuals(_ability_target_visuals)
	clear_ability_area()
	_selection_layer.clear()
	_clear_hex_visuals(_selection_visuals)
	_highlight_layer.clear()
	_clear_hex_visuals(_hover_visuals)

func apply_map_event(event: MapMutationEvent) -> void:
	if event == null:
		return

	clear_overlays()
	if event.kind == MapMutationKind.Value.REMOVE_HEX:
		_displayed_properties.erase(event.hex)
	else:
		_displayed_properties[event.hex] = {"terrain": event.terrain_id, "traversable": event.traversable, "cost": event.movement_cost}
	if event.kind == MapMutationKind.Value.APPLY_HEX_STATE:
		_hex_state_visuals.set_hex_state(event.hex, event.hex_state_id)
		_update_terrain_properties(event.hex)
		return
	var map_cell := HexCoordinateMapper.axial_to_offset(event.hex)

	if event.kind == MapMutationKind.Value.REMOVE_HEX:
		_terrain_layer.erase_cell(map_cell)
		_hex_state_visuals.remove_hex(event.hex)
		_update_terrain_properties(event.hex)
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

	_update_terrain_properties(event.hex)


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
		Vector2(0, -32),
		Vector2(28, -16),
		Vector2(28, 16),
		Vector2(0, 32),
		Vector2(-28, 16),
		Vector2(-28, -16),
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


func _refresh_terrain_properties() -> void:
	if _terrain_property_visuals == null:
		return
	_clear_hex_visuals(_terrain_property_visuals)
	_terrain_property_nodes.clear()
	for hex: Vector2i in _displayed_properties:
		_update_terrain_properties(hex)


func _update_terrain_properties(hex: Vector2i) -> void:
	if _terrain_property_visuals == null:
		return
	var previous := _terrain_property_nodes.get(hex) as Node2D
	if is_instance_valid(previous):
		_terrain_property_visuals.remove_child(previous)
		previous.queue_free()
	_terrain_property_nodes.erase(hex)
	if not _displayed_properties.has(hex):
		return
	var properties: Dictionary = _displayed_properties[hex]
	var blocked: bool = not properties.traversable
	var custom_terrain: bool = properties.terrain != &"core:default"
	var costly := int(properties.cost) > 1
	if not blocked and not custom_terrain and not costly:
		return
	var container := Node2D.new()
	_terrain_property_visuals.add_child(container)
	_terrain_property_nodes[hex] = container
	var center := to_local(hex_to_global_position(hex))
	if blocked:
		_add_hex_visual(container, hex, Color(0.12, 0.13, 0.16, 0.72), Color(0.85, 0.4, 0.35, 0.8), 2.0)
		container.add_child(_create_marker_label("×", 22, center))
	elif custom_terrain:
		var hue := float(absi(String(properties.terrain).hash()) % 360) / 360.0
		_add_hex_visual(container, hex, Color.from_hsv(hue, 0.35, 0.55, 0.17), Color.from_hsv(hue, 0.25, 0.75, 0.3), 1.0)
	if costly:
		container.add_child(_create_marker_label(str(properties.cost), 11, center + Vector2(15, 17)))


## The board is scaled unevenly for perspective; marker text keeps upright screen proportions.
func _create_marker_label(text: String, font_size: int, center: Vector2) -> Label:
	var viewport_size := get_viewport().get_visible_rect().size
	var screen_scale := minf(viewport_size.x / 1920.0, viewport_size.y / 1080.0)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size = Vector2.ONE * font_size * 1.6
	label.scale = Vector2.ONE * screen_scale / scale
	label.position = center - label.size * label.scale * 0.5
	return label
