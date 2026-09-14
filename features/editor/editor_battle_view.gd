class_name EditorBattleView
extends Node2D


signal hex_activated(hex: Vector2i)
signal placement_selected(placement_id: StringName)
signal hovered_hex_changed(hex: Vector2i, is_inside: bool)


enum Tool {
	SELECT,
	ADD_HEX,
	REMOVE_HEX,
	PAINT_TERRAIN,
	PAINT_COST,
	PAINT_OBSTACLE,
	PLACE_UNIT,
}


const HEX_SIZE := 34.0
const MIN_ZOOM := 0.45
const MAX_ZOOM := 2.2
const DEFAULT_CELL_COLOR := Color(0.18, 0.24, 0.28, 1.0)
const ASH_CELL_COLOR := Color(0.38, 0.25, 0.16, 1.0)
const GRID_COLOR := Color(0.52, 0.62, 0.68, 1.0)
const SELECTED_COLOR := Color(0.96, 0.78, 0.23, 1.0)
const HOVER_COLOR := Color(0.2, 0.82, 0.9, 0.85)


var document: EditorDocument
var selected_placement_id: StringName
var selected_hex := Vector2i.ZERO
var has_selected_hex := false
var active_tool: Tool = Tool.SELECT
var _hovered_hex := Vector2i.ZERO
var _has_hovered_hex := false
var _is_panning := false
var _is_painting := false
var _last_painted_hex := Vector2i(999999, 999999)
var _zoom := 1.0


func setup(p_document: EditorDocument) -> void:
	document = p_document
	queue_redraw()


func refresh() -> void:
	queue_redraw()


func set_tool(tool: Tool) -> void:
	active_tool = tool
	_is_painting = false
	queue_redraw()


func select_placement(placement_id: StringName) -> void:
	selected_placement_id = placement_id
	has_selected_hex = false
	queue_redraw()


func select_hex(hex: Vector2i, selected: bool = true) -> void:
	selected_hex = hex
	has_selected_hex = selected
	selected_placement_id = StringName()
	queue_redraw()


func frame_document(view_size: Vector2) -> void:
	if document == null or document.map_definition.cells.is_empty():
		_zoom = 1.0
		scale = Vector2.ONE
		position = view_size * 0.5
		return

	var first := _hex_center(document.map_definition.cells[0].hex)
	var minimum := first
	var maximum := first

	for cell: BattleMapCellDefinition in document.map_definition.cells:
		var center := _hex_center(cell.hex)
		minimum.x = minf(minimum.x, center.x)
		minimum.y = minf(minimum.y, center.y)
		maximum.x = maxf(maximum.x, center.x)
		maximum.y = maxf(maximum.y, center.y)

	var map_size := maximum - minimum + Vector2(HEX_SIZE * 2.4, HEX_SIZE * 2.4)
	var available := Vector2(
		maxf(view_size.x - 80.0, 120.0),
		maxf(view_size.y - 80.0, 120.0)
	)
	_zoom = clampf(
		minf(available.x / map_size.x, available.y / map_size.y),
		MIN_ZOOM,
		1.35
	)
	scale = Vector2.ONE * _zoom
	position = view_size * 0.5 - (minimum + maximum) * 0.5 * _zoom


func get_zoom() -> float:
	return _zoom


func screen_position_to_hex(screen_position: Vector2) -> Vector2i:
	return _pixel_to_hex(to_local(screen_position))


func _draw() -> void:
	if document == null:
		return

	var existing_hexes: Dictionary[Vector2i, bool] = {}
	var occupancy: Dictionary[Vector2i, int] = {}

	for cell: BattleMapCellDefinition in document.map_definition.cells:
		existing_hexes[cell.hex] = true
		var center := _hex_center(cell.hex)
		var fill := _get_terrain_color(cell.terrain_id)

		if not cell.traversable:
			fill = Color(0.09, 0.1, 0.12, 1.0)
		elif cell.movement_cost > 1:
			fill = fill.lerp(Color(0.58, 0.34, 0.12, 1.0), 0.58)

		draw_colored_polygon(_hex_polygon(center), fill)
		draw_polyline(_closed_hex_polygon(center), GRID_COLOR, 2.0)

		if not cell.traversable:
			draw_line(
				center + Vector2(-13.0, -13.0),
				center + Vector2(13.0, 13.0),
				Color(0.92, 0.3, 0.24),
				3.0
			)
			draw_line(
				center + Vector2(13.0, -13.0),
				center + Vector2(-13.0, 13.0),
				Color(0.92, 0.3, 0.24),
				3.0
			)
		elif cell.movement_cost > 1:
			draw_string(
				ThemeDB.fallback_font,
				center + Vector2(-10.0, 6.0),
				"×%d" % cell.movement_cost,
				HORIZONTAL_ALIGNMENT_CENTER,
				20.0,
				13,
				Color(1.0, 0.88, 0.58)
			)

		if has_selected_hex and cell.hex == selected_hex:
			draw_polyline(
				_closed_hex_polygon(center),
				SELECTED_COLOR,
				4.0
			)

	for placement: UnitPlacementDefinition in document.battle_definition.unit_placements:
		occupancy[placement.start_hex] = occupancy.get(placement.start_hex, 0) + 1

	for placement: UnitPlacementDefinition in document.battle_definition.unit_placements:
		var center := _hex_center(placement.start_hex)
		var marker_color := _get_side_color(placement.side_id)
		var invalid: bool = (
			not existing_hexes.has(placement.start_hex)
			or occupancy.get(placement.start_hex, 0) > 1
		)

		if invalid:
			marker_color = Color(1.0, 0.1, 0.2)

		draw_circle(center, 14.0, marker_color)
		draw_arc(center, 15.0, 0.0, TAU, 24, Color.WHITE, 2.0)

		if placement.placement_id == selected_placement_id:
			draw_arc(center, 21.0, 0.0, TAU, 24, SELECTED_COLOR, 3.0)

		draw_string(
			ThemeDB.fallback_font,
			center + Vector2(-30.0, -21.0),
			_short_placement_name(placement.placement_id),
			HORIZONTAL_ALIGNMENT_CENTER,
			60.0,
			11,
			Color.WHITE
		)

	if _has_hovered_hex:
		var hover_center := _hex_center(_hovered_hex)
		var hover_color := HOVER_COLOR

		if active_tool == Tool.REMOVE_HEX or active_tool == Tool.PAINT_OBSTACLE:
			hover_color = Color(0.95, 0.3, 0.24, 0.9)
		elif active_tool == Tool.ADD_HEX:
			hover_color = Color(0.3, 0.9, 0.5, 0.9)

		draw_polyline(_closed_hex_polygon(hover_center), hover_color, 3.0)

		if active_tool == Tool.ADD_HEX and not existing_hexes.has(_hovered_hex):
			draw_colored_polygon(
				_hex_polygon(hover_center),
				Color(0.24, 0.72, 0.43, 0.25)
			)


func _input(event: InputEvent) -> void:
	if document == null or not is_visible_in_tree():
		return

	if event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
		return

	if not (event is InputEventMouseButton):
		return

	var mouse := event as InputEventMouseButton

	if mouse.button_index == MOUSE_BUTTON_MIDDLE:
		_is_panning = mouse.pressed and _is_pointer_in_workspace(mouse.position)
		if _is_panning:
			get_viewport().set_input_as_handled()
		return

	if mouse.button_index == MOUSE_BUTTON_LEFT and not mouse.pressed:
		_is_painting = false
		_last_painted_hex = Vector2i(999999, 999999)
		return

	if not mouse.pressed or not _is_pointer_in_workspace(mouse.position):
		return

	if mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_at(mouse.position, 1.12)
		get_viewport().set_input_as_handled()
		return

	if mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_at(mouse.position, 1.0 / 1.12)
		get_viewport().set_input_as_handled()
		return

	if mouse.button_index != MOUSE_BUTTON_LEFT:
		return

	var hex := screen_position_to_hex(mouse.position)

	if active_tool == Tool.SELECT:
		for placement: UnitPlacementDefinition in document.battle_definition.unit_placements:
			if to_local(mouse.position).distance_to(_hex_center(placement.start_hex)) <= 18.0:
				placement_selected.emit(placement.placement_id)
				get_viewport().set_input_as_handled()
				return

	hex_activated.emit(hex)
	_is_painting = _tool_supports_drag()
	_last_painted_hex = hex
	get_viewport().set_input_as_handled()


func _handle_mouse_motion(motion: InputEventMouseMotion) -> void:
	if _is_panning:
		position += motion.relative
		queue_redraw()
		get_viewport().set_input_as_handled()
		return

	if not _is_pointer_in_workspace(motion.position):
		if _has_hovered_hex:
			_has_hovered_hex = false
			hovered_hex_changed.emit(_hovered_hex, false)
			queue_redraw()
		return

	var hex := screen_position_to_hex(motion.position)

	if not _has_hovered_hex or hex != _hovered_hex:
		_hovered_hex = hex
		_has_hovered_hex = true
		hovered_hex_changed.emit(hex, true)
		queue_redraw()

	if (
		_is_painting
		and _tool_supports_drag()
		and hex != _last_painted_hex
	):
		_last_painted_hex = hex
		hex_activated.emit(hex)
		get_viewport().set_input_as_handled()


func _zoom_at(screen_position: Vector2, factor: float) -> void:
	var next_zoom := clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)

	if is_equal_approx(next_zoom, _zoom):
		return

	var local_before := to_local(screen_position)
	var parent_position: Vector2 = (
		get_parent().get_global_transform().affine_inverse()
		* screen_position
	)
	_zoom = next_zoom
	scale = Vector2.ONE * _zoom
	position = parent_position - local_before * _zoom
	queue_redraw()


func _tool_supports_drag() -> bool:
	return active_tool in [
		Tool.ADD_HEX,
		Tool.REMOVE_HEX,
		Tool.PAINT_TERRAIN,
		Tool.PAINT_COST,
		Tool.PAINT_OBSTACLE,
	]


func _is_pointer_in_workspace(screen_position: Vector2) -> bool:
	var workspace := get_parent() as Control
	return (
		workspace != null
		and workspace.get_global_rect().has_point(screen_position)
	)


func _pixel_to_hex(point: Vector2) -> Vector2i:
	var fractional_r := point.y / (HEX_SIZE * 1.5)
	var fractional_q := (
		point.x / (HEX_SIZE * sqrt(3.0))
		- fractional_r * 0.5
	)
	return _round_axial(fractional_q, fractional_r)


func _round_axial(q: float, r: float) -> Vector2i:
	var cube_x := q
	var cube_z := r
	var cube_y := -cube_x - cube_z
	var rounded_x := roundi(cube_x)
	var rounded_y := roundi(cube_y)
	var rounded_z := roundi(cube_z)
	var difference_x := absf(rounded_x - cube_x)
	var difference_y := absf(rounded_y - cube_y)
	var difference_z := absf(rounded_z - cube_z)

	if difference_x > difference_y and difference_x > difference_z:
		rounded_x = -rounded_y - rounded_z
	elif difference_y > difference_z:
		rounded_y = -rounded_x - rounded_z
	else:
		rounded_z = -rounded_x - rounded_y

	return Vector2i(rounded_x, rounded_z)


func _hex_center(hex: Vector2i) -> Vector2:
	return Vector2(
		HEX_SIZE * sqrt(3.0) * (hex.x + hex.y * 0.5),
		HEX_SIZE * 1.5 * hex.y
	)


func _hex_polygon(center: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()

	for index: int in range(6):
		var angle := deg_to_rad(60.0 * index - 30.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * HEX_SIZE)

	return points


func _closed_hex_polygon(center: Vector2) -> PackedVector2Array:
	var points := _hex_polygon(center)
	points.append(points[0])
	return points


func _get_terrain_color(terrain_id: StringName) -> Color:
	if terrain_id == &"ember_pack:ash":
		return ASH_CELL_COLOR
	if terrain_id == &"core:default":
		return DEFAULT_CELL_COLOR

	var hue := float(abs(String(terrain_id).hash()) % 360) / 360.0
	return Color.from_hsv(hue, 0.32, 0.34)


func _get_side_color(side_id: StringName) -> Color:
	for side: BattleSideDefinition in document.battle_definition.sides:
		if side.side_id != side_id:
			continue

		if side.faction == BattleFaction.Value.PLAYER:
			return Color(0.2, 0.65, 1.0)

		return Color(1.0, 0.35, 0.2)

	return Color.GRAY


func _short_placement_name(placement_id: StringName) -> String:
	var value := String(placement_id)
	var separator := value.rfind(":")
	return value.substr(separator + 1).left(10) if separator >= 0 else value.left(10)
