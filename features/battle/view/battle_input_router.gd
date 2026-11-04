class_name BattleInputRouter
extends Node


signal hex_hovered(axial_cell: Vector2i)
signal hex_hover_exited
signal hex_selected(axial_cell: Vector2i)


@onready var _terrain_layer: TileMapLayer = %TerrainLayer
@onready var _hud := get_node_or_null("%BattleUI") as BattleHUD

var _hex_grid: HexGrid
## Hexes outside the grid the player may point at now, such as landing hexes.
var _extra_cells: Dictionary[Vector2i, bool] = {}
var _hovered_hex := Vector2i.ZERO
var _has_hovered_hex := false
var _interaction_enabled := true


func setup(hex_grid: HexGrid) -> void:
	_hex_grid = hex_grid


## Accepts these hexes too, although the grid lacks them; an empty list returns to the grid.
func set_extra_cells(cells: Array[Vector2i]) -> void:
	_extra_cells.clear()
	for cell: Vector2i in cells:
		_extra_cells[cell] = true


func _accepts(cell: Vector2i) -> bool:
	return _hex_grid != null and (_hex_grid.has_cell(cell) or _extra_cells.has(cell))


func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled

	if not enabled:
		_clear_hover()


## TileMapLayer остаётся границей между координатами мыши и логическими гексами.
func _process(_delta: float) -> void:
	if not _interaction_enabled:
		return

	if _hex_grid == null:
		return

	var hovered_control := get_viewport().gui_get_hovered_control()

	if _hud != null and _hud.contains_control(hovered_control):
		_clear_hover()
		return

	var map_cell := _terrain_layer.local_to_map(
		_terrain_layer.get_local_mouse_position()
	)
	var axial_cell := HexCoordinateMapper.offset_to_axial(map_cell)

	if not _accepts(axial_cell):
		_clear_hover()
		return

	if _has_hovered_hex and axial_cell == _hovered_hex:
		return

	_hovered_hex = axial_cell
	_has_hovered_hex = true
	hex_hovered.emit(axial_cell)


## UI получает возможность обработать клик раньше игрового поля.
func _unhandled_input(event: InputEvent) -> void:
	if not _interaction_enabled:
		return

	if not (event is InputEventMouseButton):
		return

	var mouse_event := event as InputEventMouseButton

	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	if not mouse_event.pressed:
		return

	var map_cell := _terrain_layer.local_to_map(_terrain_layer.to_local(_terrain_layer.get_canvas_transform().affine_inverse() * mouse_event.position))
	var hex := HexCoordinateMapper.offset_to_axial(map_cell)
	if not _accepts(hex):
		return
	hex_selected.emit(hex)
	get_viewport().set_input_as_handled()


func _clear_hover() -> void:
	if not _has_hovered_hex:
		return

	_has_hovered_hex = false
	hex_hover_exited.emit()
