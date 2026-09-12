class_name EditorBattleView
extends Node2D


signal hex_selected(hex: Vector2i)
signal placement_selected(placement_id: StringName)

const HEX_SIZE := 34.0

var document: EditorDocument
var selected_placement_id: StringName


func setup(p_document: EditorDocument) -> void:
	document = p_document
	queue_redraw()


func refresh() -> void:
	queue_redraw()


func select_placement(placement_id: StringName) -> void:
	selected_placement_id = placement_id
	queue_redraw()


func _draw() -> void:
	if document == null:
		return

	var existing_hexes: Dictionary[Vector2i, bool] = {}
	var occupancy: Dictionary[Vector2i, int] = {}

	for cell: BattleMapCellDefinition in document.map_definition.cells:
		existing_hexes[cell.hex] = true
		var center := _hex_center(cell.hex)
		var fill := Color(0.18, 0.24, 0.28, 1.0)

		if not cell.traversable:
			fill = Color(0.12, 0.12, 0.14, 1.0)
		elif cell.movement_cost > 1:
			fill = Color(0.38, 0.28, 0.18, 1.0)

		draw_colored_polygon(_hex_polygon(center), fill)
		draw_polyline(_closed_hex_polygon(center), Color(0.52, 0.62, 0.68), 2.0)

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
			draw_arc(center, 20.0, 0.0, TAU, 24, Color.YELLOW, 3.0)

		draw_string(
			ThemeDB.fallback_font,
			center + Vector2(-20.0, -20.0),
			String(placement.placement_id),
			HORIZONTAL_ALIGNMENT_CENTER,
			40.0,
			12,
			Color.WHITE
		)


func _unhandled_input(event: InputEvent) -> void:
	if document == null or not (event is InputEventMouseButton):
		return

	var mouse := event as InputEventMouseButton

	if mouse.button_index != MOUSE_BUTTON_LEFT or not mouse.pressed:
		return

	var local := to_local(mouse.position)

	for placement: UnitPlacementDefinition in document.battle_definition.unit_placements:
		if local.distance_to(_hex_center(placement.start_hex)) <= 18.0:
			placement_selected.emit(placement.placement_id)
			get_viewport().set_input_as_handled()
			return

	var best_hex := Vector2i.ZERO
	var best_distance := INF
	var found := false

	for cell: BattleMapCellDefinition in document.map_definition.cells:
		var distance := local.distance_to(_hex_center(cell.hex))

		if distance < best_distance:
			best_distance = distance
			best_hex = cell.hex
			found = true

	if found and best_distance <= HEX_SIZE:
		hex_selected.emit(best_hex)
		get_viewport().set_input_as_handled()


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


func _get_side_color(side_id: StringName) -> Color:
	for side: BattleSideDefinition in document.battle_definition.sides:
		if side.side_id != side_id:
			continue

		if side.faction == BattleFaction.Value.PLAYER:
			return Color(0.2, 0.65, 1.0)

		return Color(1.0, 0.35, 0.2)

	return Color.GRAY