class_name EditorBattleView
extends Node2D


signal hex_activated(hex: Vector2i)
signal hex_erased(hex: Vector2i)
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
	PAINT_STATE,
	ERASE_STATE,
}


const MIN_ZOOM := 0.15
const MAX_ZOOM := 2.2
const SELECTED_COLOR := Color(0.96, 0.78, 0.23, 1.0)
const HOVER_COLOR := Color(0.2, 0.82, 0.9, 0.85)


var snapshot: ContentSnapshot
var show_grid := true
var show_units := true
var document: BattleDocument
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


func setup(p_document: BattleDocument) -> void:
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
	_zoom = clampf(minf(view_size.x / 1920.0, view_size.y / 1080.0), MIN_ZOOM, MAX_ZOOM)
	scale = Vector2.ONE * _zoom
	position = (view_size - Vector2(1920, 1080) * _zoom) * 0.5


func get_zoom() -> float:
	return _zoom


func screen_position_to_hex(screen_position: Vector2) -> Vector2i:
	return _pixel_to_hex(to_local(screen_position))


func _draw() -> void:
	if document == null:
		return
	draw_texture_rect(BattleBackdrops.texture(document.map_definition.background_id), Rect2(0, 0, 1920, 1080), false)
	var existing: Dictionary[Vector2i, bool] = {}
	var occupancy: Dictionary[Vector2i, int] = {}
	for cell: BattleMapCellDefinition in document.map_definition.cells:
		existing[cell.hex] = true
		var center := _hex_center(cell.hex)
		var texture := HexStateArt.texture(cell.hex_state_id)
		if texture != null:
			draw_texture_rect(texture, Rect2(center - Vector2(45, 30), Vector2(90, 58)), false)
		if show_grid:
			draw_polyline(_closed_hex_polygon(center), Color(0.85, 0.84, 0.72, 0.5), 1.2, true)
		if not cell.traversable:
			draw_colored_polygon(_hex_polygon(center), Color(0.12, 0.09, 0.08, 0.65))
			draw_line(center - Vector2(13, 13), center + Vector2(13, 13), Color.SALMON, 3)
			draw_line(center + Vector2(13, -13), center + Vector2(-13, 13), Color.SALMON, 3)
		if has_selected_hex and cell.hex == selected_hex:
			draw_polyline(_closed_hex_polygon(center), SELECTED_COLOR, 3, true)
	# Missing cells remain recoverable but never become logical cells through drawing.
	for row in range(12):
		for column in range(18):
			var hex := HexCoordinateMapper.offset_to_axial(Vector2i(column, row))
			if not existing.has(hex):
				var center := _hex_center(hex)
				draw_colored_polygon(_hex_polygon(center), Color(0.025, 0.035, 0.03, 0.65))
				if active_tool == Tool.ADD_HEX:
					draw_polyline(_closed_hex_polygon(center), Color(0.5, 0.8, 0.6, 0.3), 1)
	if show_units:
		var placements := document.battle_definition.unit_placements.duplicate()
		placements.sort_custom(func(a: UnitPlacementDefinition, b: UnitPlacementDefinition) -> bool: return a.start_hex.y < b.start_hex.y)
		for placement: UnitPlacementDefinition in placements:
			occupancy[placement.start_hex] = occupancy.get(placement.start_hex, 0) + 1
		for placement: UnitPlacementDefinition in placements:
			_draw_unit(placement, not existing.has(placement.start_hex) or occupancy[placement.start_hex] > 1)
	if _has_hovered_hex and is_in_frame(_hovered_hex):
		draw_polyline(_closed_hex_polygon(_hex_center(_hovered_hex)), HOVER_COLOR, 3, true)


func _draw_unit(placement: UnitPlacementDefinition, invalid: bool) -> void:
	var center := _hex_center(placement.start_hex)
	var color := Color.RED if invalid else _get_side_color(placement.side_id)
	var presentation: UnitPresentationDefinition
	if snapshot != null:
		var definition := snapshot.get_unit_definition(placement.definition_id)
		if definition != null:
			presentation = snapshot.get_unit_presentation_definition(definition.presentation_id)
	draw_circle(center, 17, Color(0, 0, 0, 0.25))
	if presentation != null and presentation.actor_texture != null:
		var texture := presentation.actor_texture
		var dimensions := texture.get_size() * presentation.texture_scale()
		draw_texture_rect(texture, Rect2(center - dimensions * presentation.actor_foot_anchor, dimensions), false, presentation.actor_color)
	else:
		draw_circle(center, 14, color)
		draw_string(ThemeDB.fallback_font, center + Vector2(-30, -23), _short_placement_name(placement.definition_id), HORIZONTAL_ALIGNMENT_CENTER, 60, 13)
	draw_line(center + Vector2(-13, 10), center + Vector2(13, 10), color, 3)
	if placement.placement_id == selected_placement_id:
		draw_polyline(_closed_hex_polygon(center), SELECTED_COLOR, 3, true)


static func is_in_frame(hex: Vector2i) -> bool:
	var offset := HexCoordinateMapper.axial_to_offset(hex)
	return offset.x >= 0 and offset.x < 18 and offset.y >= 0 and offset.y < 12


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

	if mouse.button_index == MOUSE_BUTTON_RIGHT:
		var erased := screen_position_to_hex(mouse.position)
		if is_in_frame(erased):
			hex_erased.emit(erased)
		get_viewport().set_input_as_handled()
		return

	if mouse.button_index != MOUSE_BUTTON_LEFT:
		return

	var hex := screen_position_to_hex(mouse.position)

	if not is_in_frame(hex):
		return

	if active_tool == Tool.SELECT and show_units:
		for placement: UnitPlacementDefinition in document.battle_definition.unit_placements:
			if placement.start_hex == hex:
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
		hovered_hex_changed.emit(hex, is_in_frame(hex))
		queue_redraw()

	if (
		_is_painting
		and _tool_supports_drag()
		and is_in_frame(hex)
		and hex != _last_painted_hex
	):
		_last_painted_hex = hex
		hex_activated.emit(hex)
		get_viewport().set_input_as_handled()


func _tool_supports_drag() -> bool:
	return active_tool in [
		Tool.PAINT_STATE,
		Tool.ERASE_STATE,
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
	# Test the projected polygon, including the sloping shared edges.
	var row_guess := roundi((point.y - 197.0) / 58.5)
	for row in range(row_guess - 1, row_guess + 2):
		var column := roundi((point.x - 137.0 - posmod(row, 2) * 47.0) / 94.0)
		var hex := HexCoordinateMapper.offset_to_axial(Vector2i(column, row))
		var delta := (point - _hex_center(hex)).abs()
		if delta.x <= 47.0 and delta.y <= 39.0 - delta.x * 19.5 / 47.0:
			return hex
	return Vector2i(999999, 999999)


func _hex_center(hex: Vector2i) -> Vector2:
	return Vector2(137.0 + (hex.x + hex.y * 0.5) * 94.0, 197.0 + hex.y * 58.5)


func _hex_polygon(center: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(0, -39), center + Vector2(47, -19.5),
		center + Vector2(47, 19.5), center + Vector2(0, 39),
		center + Vector2(-47, 19.5), center + Vector2(-47, -19.5),
	])


func _closed_hex_polygon(center: Vector2) -> PackedVector2Array:
	var points := _hex_polygon(center)
	points.append(points[0])
	return points


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
