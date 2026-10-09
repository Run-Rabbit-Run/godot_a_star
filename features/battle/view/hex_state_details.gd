class_name HexStateDetails
extends CanvasLayer
## Screen-space presentation of the displayed map, never the authoritative state.

var _map: BattleMapView
var _properties: Dictionary[Vector2i, Dictionary]
var _labels: Dictionary[Vector2i, Label] = {}
var _popup: PanelContainer
var _title: Label
var _body: Label
var _hovered := Vector2i.ZERO
var _has_hover := false
var _hover_time := 0.0
var _alt_visible := false

func setup(map: BattleMapView, properties: Dictionary[Vector2i, Dictionary]) -> void:
	_map = map
	_properties = properties
	layer = 40
	_popup = PanelContainer.new()
	_popup.name = "HexStatePopup"
	_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.10, 0.97)
	style.border_color = Color(0.65, 0.61, 0.42, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_popup.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 7)
	_title = Label.new()
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_theme_font_size_override("font_size", 18)
	column.add_child(_title)
	_body = Label.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.custom_minimum_size.x = 320
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", 15)
	column.add_child(_body)
	_popup.add_child(column)
	add_child(_popup)
	_popup.hide()

func hover(hex: Vector2i) -> void:
	_hovered = hex
	_has_hover = true
	_hover_time = 0.0
	_popup.hide()

func clear_hover() -> void:
	_has_hover = false
	_popup.hide()

func refresh() -> void:
	for hex: Vector2i in _labels.keys():
		if not _properties.has(hex) or int(_properties[hex].get("turns", 0)) <= 0:
			_labels[hex].queue_free()
			_labels.erase(hex)
	for hex: Vector2i in _properties:
		var turns := int(_properties[hex].get("turns", 0))
		if turns <= 0:
			continue
		if not _labels.has(hex):
			var label := Label.new()
			label.name = "HexTurns_%d_%d" % [hex.x, hex.y]
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 15)
			label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.64))
			label.add_theme_color_override("font_outline_color", Color(0.06, 0.07, 0.08))
			label.add_theme_constant_override("outline_size", 5)
			add_child(label)
			_labels[hex] = label
		_labels[hex].text = str(turns)
		_labels[hex].visible = _alt_visible
	move_child(_popup, get_child_count() - 1)
	_update_popup()

func _process(delta: float) -> void:
	if _map == null:
		return
	_alt_visible = get_window().has_focus() and Input.is_key_pressed(KEY_ALT)
	var viewport_size := get_viewport().get_visible_rect().size
	var screen_scale := minf(viewport_size.x / 1920.0, viewport_size.y / 1080.0)
	for hex: Vector2i in _labels:
		var label := _labels[hex]
		label.visible = _alt_visible
		label.scale = Vector2.ONE * screen_scale
		label.size = Vector2(30, 24)
		var center := _map.get_viewport().get_canvas_transform() * _map.hex_to_global_position(hex)
		label.position = center + Vector2(-15, 32) * screen_scale
	if not _has_hover or not get_window().has_focus():
		_popup.hide()
		return
	_hover_time += delta
	if _hover_time >= 0.35:
		_update_popup()
	if _popup.visible:
		var cursor := get_viewport().get_mouse_position()
		_popup.position = (cursor + Vector2(22, 20)).clamp(Vector2(8, 8), viewport_size - _popup.size - Vector2(8, 8))

func _update_popup() -> void:
	if not _has_hover or _hover_time < 0.35 or not _properties.has(_hovered):
		_popup.hide()
		return
	var properties := _properties[_hovered]
	var obstacle := properties.get("obstacle") as BattleObstacleDefinition
	if obstacle != null:
		_title.text = BattleObstacleDefinition.NAMES[BattleObstacleDefinition.TYPES.find(obstacle.terrain_type)]
		_body.text = "Препятствие: %d гекс.\nПроход запрещён. Состояния не применяются.\n%s" % [obstacle.hexes.size(), "HP: %d / %d. Атакуйте любой гекс препятствия." % [obstacle.current_hp, obstacle.max_hp] if obstacle.destructible else "Неуничтожаемое."]
		_popup.reset_size()
		_popup.show()
		return
	var id := StringName(properties.get("state", &""))
	if id.is_empty():
		_popup.hide()
		return
	_title.text = HexStateCatalog.get_display_name(id)
	_body.text = "%s\n\nСтоимость прохода: %d очк. движения.\nОсталось ходов (раундов): %d.\n%s" % [HexStateCatalog.description(id), properties.cost, properties.get("turns", 0), "" if properties.traversable else "Гекс непроходим."]
	_popup.reset_size()
	_popup.show()
