class_name BattleEditorShell
extends Control


const DEFAULT_DRAFT_FILENAME := "battle_editor_draft.json"
const BATTLE_SCREEN_SCENE := preload("res://features/battle/battle_screen.tscn")


var content_packages: Array[ContentPackage] = []
@export var initial_battle_id: StringName = &"plateau:battle"
@export var trial_seed := 1


var _background_option: OptionButton
var _selected_state_id: StringName = &"core:electricity"
var _snapshot: ContentSnapshot
var _document: BattleDocument
var _history := EditorCommandHistory.new()
var _view: EditorBattleView
var _ui: Control
var _map_workspace: Control
var _palette: ItemList
var _palette_search: LineEdit
var _side_option: OptionButton
var _ai_option: OptionButton
var _diagnostics: ItemList
var _status: Label
var _cursor_label: Label
var _tool_option: OptionButton
var _selected_hex_label: Label
var _terrain_id_edit: LineEdit
var _movement_cost_spin: SpinBox
var _traversable_check: CheckButton
var _q_spin: SpinBox
var _r_spin: SpinBox
var _document_path_label: Label
var _save_dialog: FileDialog
var _open_dialog: FileDialog
var _selected_definition_id: StringName
var _selected_placement_id: StringName
var _selected_hex := Vector2i.ZERO
var _has_selected_hex := false
var _next_placement_number := 1
var _current_document_path := ""
var _activate_after_save := false
var _trial_return_layer: CanvasLayer
var _trial_screen: BattleScreen
var _trial_result: BattleResult


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	var settings := GameContentSettings.read()
	if settings == null:
		_set_status("Не удалось прочитать content/game_content.tres.")
		return
	content_packages = settings.content_packages
	var load_result := UnitLibrary.load_content(content_packages)

	if not load_result.is_successful:
		_show_load_errors(load_result.errors)
		return

	_snapshot = load_result.snapshot
	if not settings.battle_document_path.is_empty():
		var loaded := BattleDocumentSerializer.load_result(settings.battle_document_path)
		if loaded.document == null:
			_set_status(loaded.error_message)
			return
		_document = loaded.document
		_current_document_path = settings.battle_document_path
	else:
		_document = BattleDocument.from_snapshot(_snapshot, initial_battle_id)

	if _document == null:
		_set_status("Не удалось открыть стартовый бой.")
		return

	_select_option_by_metadata(_background_option, _document.map_definition.background_id)
	_view.snapshot = _snapshot
	_view.setup(_document)
	_populate_palette()
	_populate_side_options()
	_populate_ai_options()
	_update_document_path_label()
	_validate_document()
	call_deferred("_frame_map")


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.035, 0.05, 0.065)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_ui = background

	_map_workspace = Control.new()
	_map_workspace.name = "MapWorkspace"
	_map_workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_workspace.offset_right = -380.0
	_map_workspace.offset_top = 52.0
	_map_workspace.offset_bottom = -150.0
	_map_workspace.clip_contents = true
	_map_workspace.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_child(_map_workspace)

	_view = EditorBattleView.new()
	_view.hex_activated.connect(_on_hex_activated)
	_view.hex_erased.connect(_on_hex_erased)
	_view.placement_selected.connect(_on_placement_selected)
	_view.hovered_hex_changed.connect(_on_hovered_hex_changed)
	_map_workspace.add_child(_view)
	_map_workspace.resized.connect(_frame_map)
	_build_visual_controls(background)

	var panel := PanelContainer.new()
	panel.name = "ToolsPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -364.0
	panel.offset_top = 16.0
	panel.offset_right = -16.0
	panel.offset_bottom = -16.0
	background.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(scroll)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(320.0, 0.0)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 7)
	scroll.add_child(root)

	var title := Label.new()
	title.text = "РЕДАКТОР БОЯ"
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)
	root.add_child(EditorDisplaySettings.new())

	var hint := Label.new()
	hint.text = "ЛКМ — инструмент · ПКМ — стереть состояние / юнита · СКМ — панорама"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(hint)

	_cursor_label = Label.new()
	_cursor_label.text = "Курсор: вне поля"
	_cursor_label.add_theme_color_override("font_color", Color(0.3, 0.82, 0.9))
	root.add_child(_cursor_label)

	_tool_option = OptionButton.new()
	_add_tool("Выбор клетки / юнита", EditorBattleView.Tool.SELECT)
	_add_tool("Кисть: состояние", EditorBattleView.Tool.PAINT_STATE)
	_add_tool("Ластик: состояние", EditorBattleView.Tool.ERASE_STATE)
	_add_tool("Кисть: добавить гексы", EditorBattleView.Tool.ADD_HEX)
	_add_tool("Кисть: удалить гексы", EditorBattleView.Tool.REMOVE_HEX)
	_add_tool("Кисть: поверхность", EditorBattleView.Tool.PAINT_TERRAIN)
	_add_tool("Кисть: стоимость движения", EditorBattleView.Tool.PAINT_COST)
	_add_tool("Кисть: препятствие", EditorBattleView.Tool.PAINT_OBSTACLE)
	_add_tool("Поставить / переместить юнита", EditorBattleView.Tool.PLACE_UNIT)
	_tool_option.item_selected.connect(_on_tool_changed)
	root.add_child(_labeled("Инструмент", _tool_option))
	root.add_child(_button("Показать всё поле", _frame_map))
	root.add_child(HSeparator.new())

	var map_title := Label.new()
	map_title.text = "СВОЙСТВА ГЕКСА И КИСТИ"
	map_title.add_theme_font_size_override("font_size", 14)
	root.add_child(map_title)

	_selected_hex_label = Label.new()
	_selected_hex_label.text = "Гекс не выбран"
	root.add_child(_selected_hex_label)

	_terrain_id_edit = LineEdit.new()
	_terrain_id_edit.text = "core:default"
	_terrain_id_edit.placeholder_text = "core:default"
	root.add_child(_labeled("ID поверхности", _terrain_id_edit))

	_movement_cost_spin = SpinBox.new()
	_movement_cost_spin.min_value = 1
	_movement_cost_spin.max_value = 99
	_movement_cost_spin.value = 1
	root.add_child(_labeled("Стоимость движения", _movement_cost_spin))

	_traversable_check = CheckButton.new()
	_traversable_check.text = "Проходимый гекс"
	_traversable_check.button_pressed = true
	root.add_child(_traversable_check)
	root.add_child(_button("Применить к выбранному гексу", _apply_selected_hex))

	var coords := HBoxContainer.new()
	_q_spin = _coordinate_spin()
	_r_spin = _coordinate_spin()
	coords.add_child(_labeled("q", _q_spin))
	coords.add_child(_labeled("r", _r_spin))
	root.add_child(coords)

	var coordinate_actions := HBoxContainer.new()
	coordinate_actions.add_child(_button("Добавить по q,r", _add_hex_by_coordinates))
	coordinate_actions.add_child(_button("Удалить по q,r", _remove_hex_by_coordinates))
	root.add_child(coordinate_actions)
	root.add_child(HSeparator.new())

	var unit_title := Label.new()
	unit_title.text = "РАССТАНОВКА ЮНИТОВ"
	unit_title.add_theme_font_size_override("font_size", 14)
	root.add_child(unit_title)
	root.add_child(_button("Редактор юнитов", _open_unit_editor))
	root.add_child(_button("Обновить библиотеку юнитов", _reload_unit_library))

	_palette_search = LineEdit.new()
	_palette_search.placeholder_text = "Поиск юнита"
	_palette_search.text_changed.connect(_on_palette_search_changed)
	root.add_child(_palette_search)

	_palette = ItemList.new()
	_palette.custom_minimum_size = Vector2(0, 180)
	_palette.fixed_icon_size = Vector2i(40, 40)
	_palette.item_selected.connect(_on_palette_selected)
	root.add_child(_palette)

	_side_option = OptionButton.new()
	_side_option.item_selected.connect(_on_side_changed)
	root.add_child(_labeled("Сторона", _side_option))

	_ai_option = OptionButton.new()
	_ai_option.item_selected.connect(_on_ai_override_changed)
	root.add_child(_labeled("Профиль ИИ", _ai_option))

	var placement_actions := HBoxContainer.new()
	placement_actions.add_child(_button("Дублировать", _duplicate_selected))
	placement_actions.add_child(_button("Удалить юнита", _delete_selected))
	root.add_child(placement_actions)
	root.add_child(HSeparator.new())

	var history_title := Label.new()
	history_title.text = "ДОКУМЕНТ"
	history_title.add_theme_font_size_override("font_size", 14)
	root.add_child(history_title)

	var history_actions := HBoxContainer.new()
	history_actions.add_child(_button("Отменить", _undo))
	history_actions.add_child(_button("Повторить", _redo))
	root.add_child(history_actions)

	_document_path_label = Label.new()
	_document_path_label.text = "Файл: не сохранён"
	_document_path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_document_path_label)

	var save_actions := HBoxContainer.new()
	save_actions.add_child(_button("Сохранить", _save))
	save_actions.add_child(_button("Сохранить как…", _save_as))
	save_actions.add_child(_button("Открыть…", _open_dialog_requested))
	root.add_child(save_actions)

	var document_actions := HBoxContainer.new()
	document_actions.add_child(_button("Экспорт", _export))
	document_actions.add_child(_button("Проверить", _validate_document))
	root.add_child(document_actions)
	root.add_child(_button("Пробный бой", _start_trial))
	root.add_child(_button("Сделать стартовым боем", _use_in_game))

	_diagnostics = ItemList.new()
	_diagnostics.custom_minimum_size = Vector2(0, 130)
	root.add_child(_diagnostics)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	_save_dialog = _create_file_dialog(FileDialog.FILE_MODE_SAVE_FILE)
	_save_dialog.file_selected.connect(_on_save_path_selected)
	_open_dialog = _create_file_dialog(FileDialog.FILE_MODE_OPEN_FILE)
	_open_dialog.file_selected.connect(_on_open_path_selected)


func _labeled(text: String, control: Control) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = text
	box.add_child(label)
	box.add_child(control)
	return box


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	return button


func _coordinate_spin() -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = -999
	spin.max_value = 999
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


func _create_file_dialog(mode: FileDialog.FileMode) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode
	dialog.filters = PackedStringArray(["*.json ; Документ редактора боя"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GameContentSettings.BATTLES))
	dialog.current_dir = ProjectSettings.globalize_path(GameContentSettings.BATTLES)
	dialog.canceled.connect(func() -> void: _activate_after_save = false)
	dialog.size = Vector2i(820, 560)
	dialog.about_to_popup.connect(func() -> void: _view.set_process_input(false))
	dialog.visibility_changed.connect(func() -> void: _view.set_process_input(not dialog.visible))
	add_child(dialog)
	return dialog


func _add_tool(label: String, tool: EditorBattleView.Tool) -> void:
	var index := _tool_option.item_count
	_tool_option.add_item(label)
	_tool_option.set_item_metadata(index, tool)


func _on_tool_changed(index: int) -> void:
	var tool := int(_tool_option.get_item_metadata(index)) as EditorBattleView.Tool
	_view.set_tool(tool)
	_set_status("Инструмент: %s." % _tool_option.get_item_text(index))


func _select_tool(tool: EditorBattleView.Tool) -> void:
	for index: int in range(_tool_option.item_count):
		if int(_tool_option.get_item_metadata(index)) == int(tool):
			_tool_option.select(index)
			_view.set_tool(tool)
			return


func _open_unit_editor() -> void:
	var editor := preload("res://tools/units/unit_editor.tscn").instantiate() as UnitEditor
	editor.embedded = true
	_ui.hide()
	_view.set_process_input(false)
	editor.closed.connect(func() -> void:
		_ui.show()
		_view.set_process_input(true)
		_reload_unit_library()
	)
	add_child(editor)


func _reload_unit_library() -> void:
	var result := UnitLibrary.load_content(content_packages)
	if not result.is_successful:
		_show_load_errors(result.errors)
		_set_status("Библиотека не обновлена: исправьте ошибки файлов. Предыдущий снимок сохранён.")
		return
	_snapshot = result.snapshot
	if _document == null:
		_document = BattleDocument.from_snapshot(_snapshot, initial_battle_id)
		if _document == null:
			_set_status("Не найден стартовый бой.")
			return
			_populate_side_options()
		_populate_ai_options()
	_view.snapshot = _snapshot
	_view.setup(_document)
	_populate_palette(_palette_search.text)
	_validate_document()


func _populate_palette(filter_text: String = "") -> void:
	_palette.clear()
	if _snapshot == null:
		return
	var filter := filter_text.strip_edges().to_lower()

	for definition: UnitDefinition in _snapshot.get_all_unit_definitions():
		var searchable := "%s %s" % [definition.display_name, definition.id]

		if not filter.is_empty() and not searchable.to_lower().contains(filter):
			continue

		var index := _palette.add_item(
			"%s  [%s]" % [definition.display_name, definition.id]
		)
		_palette.set_item_metadata(index, definition.id)
		var presentation := _snapshot.get_unit_presentation_definition(definition.presentation_id)
		if presentation != null:
			_palette.set_item_icon(index, presentation.portrait_texture if presentation.portrait_texture != null else presentation.actor_texture)


func _populate_side_options() -> void:
	_side_option.clear()

	for side: BattleSideDefinition in _document.battle_definition.sides:
		var index := _side_option.item_count
		_side_option.add_item(String(side.side_id))
		_side_option.set_item_metadata(index, side.side_id)


func _populate_ai_options() -> void:
	_ai_option.clear()
	_ai_option.add_item("Профиль стороны")
	_ai_option.set_item_metadata(0, StringName())
	var ids := _snapshot.get_ai_profile_definition_ids().keys()
	ids.sort()

	for ai_id: StringName in ids:
		var index := _ai_option.item_count
		_ai_option.add_item(String(ai_id))
		_ai_option.set_item_metadata(index, ai_id)


func _on_palette_search_changed(text: String) -> void:
	_populate_palette(text)


func _on_palette_selected(index: int) -> void:
	_selected_definition_id = _palette.get_item_metadata(index)
	_selected_placement_id = StringName()
	_view.select_placement(StringName())
	_select_tool(EditorBattleView.Tool.PLACE_UNIT)
	_set_status("Выбран юнит %s. Щёлкните по существующему гексу." % _selected_definition_id)


func _on_placement_selected(placement_id: StringName) -> void:
	_selected_placement_id = placement_id
	_selected_definition_id = StringName()
	_has_selected_hex = false
	_view.select_placement(placement_id)
	var placement := _find_placement(placement_id)

	if placement == null:
		return

	_select_option_by_metadata(_side_option, placement.side_id)
	_select_option_by_metadata(_ai_option, placement.ai_profile_override_id)
	_set_status(
		"Выбрано размещение %s. Для перемещения выберите инструмент юнита."
		% placement_id
	)


func _on_hovered_hex_changed(hex: Vector2i, is_inside: bool) -> void:
	_cursor_label.text = (
		"Курсор: q=%d, r=%d · масштаб %d%%"
		% [hex.x, hex.y, roundi(_view.get_zoom() * 100.0)]
		if is_inside
		else "Курсор: вне поля"
	)


func _on_hex_activated(hex: Vector2i) -> void:
	if not EditorBattleView.is_in_frame(hex):
		return
	_q_spin.value = hex.x
	_r_spin.value = hex.y

	match _view.active_tool:
		EditorBattleView.Tool.PAINT_STATE:
			_paint_state(hex, _selected_state_id)
		EditorBattleView.Tool.ERASE_STATE:
			_paint_state(hex, StringName())
		EditorBattleView.Tool.SELECT:
			_select_hex(hex)

		EditorBattleView.Tool.ADD_HEX:
			_add_hex(hex)

		EditorBattleView.Tool.REMOVE_HEX:
			_remove_hex(hex)

		EditorBattleView.Tool.PAINT_TERRAIN:
			_update_hex(hex, true, false, false)

		EditorBattleView.Tool.PAINT_COST:
			_update_hex(hex, false, true, false)

		EditorBattleView.Tool.PAINT_OBSTACLE:
			_update_hex(hex, false, false, true)

		EditorBattleView.Tool.PLACE_UNIT:
			_place_or_move_unit(hex)


func _select_hex(hex: Vector2i) -> void:
	var cell := _find_cell(hex)

	if cell == null:
		_has_selected_hex = false
		_view.select_hex(hex, false)
		_selected_hex_label.text = "Гекс q=%d, r=%d отсутствует" % [hex.x, hex.y]
		return

	_selected_hex = hex
	_has_selected_hex = true
	_selected_placement_id = StringName()
	_selected_definition_id = StringName()
	_view.select_hex(hex)
	_terrain_id_edit.text = String(cell.terrain_id)
	_movement_cost_spin.value = cell.movement_cost
	_traversable_check.button_pressed = cell.traversable
	_selected_hex_label.text = "Выбран гекс: q=%d, r=%d" % [hex.x, hex.y]
	_set_status("Свойства выбранного гекса загружены в панель.")


func _add_hex(hex: Vector2i) -> void:
	if not EditorBattleView.is_in_frame(hex):
		_set_status("Максимальная сетка — 18×12.")
		return
	if _find_cell(hex) != null:
		return

	_execute(EditCommand.add_hex(
		hex,
		_brush_terrain_id(),
		int(_movement_cost_spin.value),
		_traversable_check.button_pressed
	))


func _remove_hex(hex: Vector2i) -> void:
	if _find_cell(hex) == null:
		return

	for placement: UnitPlacementDefinition in _document.battle_definition.unit_placements:
		if placement.start_hex == hex:
			_set_status("Сначала переместите или удалите юнита с этого гекса.")
			return
	_execute(EditCommand.remove_hex(hex))

	if _has_selected_hex and _selected_hex == hex:
		_has_selected_hex = false
		_view.select_hex(hex, false)
		_selected_hex_label.text = "Гекс удалён"


func _update_hex(
	hex: Vector2i,
	change_terrain: bool,
	change_cost: bool,
	make_obstacle: bool
) -> void:
	var cell := _find_cell(hex)

	if cell == null:
		return

	var updated := cell.duplicate(true) as BattleMapCellDefinition

	if change_terrain:
		updated.terrain_id = _brush_terrain_id()
	if change_cost:
		updated.movement_cost = int(_movement_cost_spin.value)
		if not updated.hex_state_id.is_empty():
			updated.movement_cost = HexStateCatalog.get_movement_cost(updated.hex_state_id)
	if make_obstacle:
		updated.traversable = false

	_execute(EditCommand.update_hex(updated))


func _apply_selected_hex() -> void:
	if not _has_selected_hex:
		_set_status("Сначала выберите существующий гекс.")
		return

	var cell := _find_cell(_selected_hex)

	if cell == null:
		_set_status("Выбранный гекс больше не существует.")
		return

	var updated := cell.duplicate(true) as BattleMapCellDefinition
	updated.terrain_id = _brush_terrain_id()
	updated.movement_cost = int(_movement_cost_spin.value)
	if not updated.hex_state_id.is_empty():
		updated.movement_cost = HexStateCatalog.get_movement_cost(updated.hex_state_id)
	updated.traversable = _traversable_check.button_pressed
	_execute(EditCommand.update_hex(updated))
	_set_status("Свойства гекса q=%d, r=%d обновлены." % [_selected_hex.x, _selected_hex.y])


func _brush_terrain_id() -> StringName:
	var value := _terrain_id_edit.text.strip_edges()
	return StringName(value if not value.is_empty() else "core:default")


func _add_hex_by_coordinates() -> void:
	_add_hex(_selected_coordinate())


func _remove_hex_by_coordinates() -> void:
	_remove_hex(_selected_coordinate())


func _selected_coordinate() -> Vector2i:
	return Vector2i(int(_q_spin.value), int(_r_spin.value))


func _place_or_move_unit(hex: Vector2i) -> void:
	for existing: UnitPlacementDefinition in _document.battle_definition.unit_placements:
		if existing.start_hex == hex and existing.placement_id != _selected_placement_id:
			_set_status("Гекс уже занят юнитом.")
			return
	if _find_cell(hex) == null:
		_set_status("Юнита можно поставить только на существующий гекс.")
		return

	if not _find_cell(hex).traversable:
		_set_status("Нельзя поставить юнита на непроходимый гекс.")
		return
	if not _selected_placement_id.is_empty():
		_execute(EditCommand.move_placement(_selected_placement_id, hex))
		_select_tool(EditorBattleView.Tool.SELECT)
		return

	if _selected_definition_id.is_empty() or _side_option.item_count == 0:
		_set_status("Сначала выберите юнита из палитры или маркер на поле.")
		return

	var placement := UnitPlacementDefinition.new()
	placement.placement_id = _new_placement_id()
	placement.definition_id = _selected_definition_id
	placement.side_id = _side_option.get_selected_metadata()
	placement.start_hex = hex
	placement.ai_profile_override_id = _ai_option.get_selected_metadata()
	_execute(EditCommand.add_placement(placement))
	_view.select_placement(StringName())


func _on_side_changed(_index: int) -> void:
	var placement := _find_placement(_selected_placement_id)

	if placement == null:
		return

	var updated := placement.duplicate(true) as UnitPlacementDefinition
	updated.side_id = _side_option.get_selected_metadata()
	_execute(EditCommand.update_placement(updated))


func _on_ai_override_changed(_index: int) -> void:
	var placement := _find_placement(_selected_placement_id)

	if placement == null:
		return

	var updated := placement.duplicate(true) as UnitPlacementDefinition
	updated.ai_profile_override_id = _ai_option.get_selected_metadata()
	_execute(EditCommand.update_placement(updated))


func _duplicate_selected() -> void:
	var placement := _find_placement(_selected_placement_id)

	if placement == null:
		_set_status("Сначала выберите маркер юнита на поле.")
		return

	var destination := _free_hex_near(placement.start_hex)
	if destination == Vector2i(999999, 999999):
		_set_status("Нет свободного проходимого гекса для копии.")
		return
	var new_id := _new_placement_id()
	_selected_placement_id = new_id
	_execute(EditCommand.duplicate_placement(
		placement.placement_id,
		new_id,
		destination
	))
	_view.select_placement(new_id)


func _delete_selected() -> void:
	if _selected_placement_id.is_empty():
		_set_status("Сначала выберите маркер юнита на поле.")
		return

	_execute(EditCommand.remove_placement(_selected_placement_id))
	_selected_placement_id = StringName()
	_view.select_placement(StringName())


func _execute(command: EditCommand) -> void:
	if _document == null:
		_set_status("Сначала исправьте ошибки загрузки библиотеки и обновите её.")
		return
	if not _history.execute(command, _document):
		_set_status("Команда не применена.")
		return

	_after_document_changed()


func _undo() -> void:
	if _history.undo(_document):
		_after_document_changed()
	else:
		_set_status("Нечего отменять.")


func _redo() -> void:
	if _history.redo(_document):
		_after_document_changed()
	else:
		_set_status("Нечего повторять.")


func _after_document_changed() -> void:
	_view.setup(_document)
	_select_option_by_metadata(_background_option, _document.map_definition.background_id)
	_validate_document()


func _frame_map() -> void:
	if _view == null or _map_workspace == null:
		return
	_view.frame_document(_map_workspace.size)
	_set_status("Поле вписано в рабочую область.")


func _validate_document() -> void:
	if _document == null or _snapshot == null:
		return

	var validation := _document.validate(_snapshot)
	_diagnostics.clear()

	for error: String in validation.errors:
		_diagnostics.add_item("Ошибка: %s" % error)

	for warning: String in validation.warnings:
		_diagnostics.add_item("Предупреждение: %s" % warning)

	if validation.is_valid:
		_set_status("Документ готов к сохранению, экспорту и пробному запуску.")
	else:
		_set_status(
			"Черновик можно сохранить, но запуск заблокирован: ошибок %s."
			% validation.errors.size()
		)


func _save() -> void:
	if _current_document_path.is_empty():
		_save_as()
		return
	_save_to_path(_current_document_path)


func _save_as() -> void:
	_save_dialog.current_file = _suggested_document_filename()
	_save_dialog.popup_centered_ratio(0.78)


func _open_dialog_requested() -> void:
	_open_dialog.popup_centered_ratio(0.78)


func _on_save_path_selected(path: String) -> void:
	var saved := _save_to_path(_ensure_json_extension(path))
	if _activate_after_save:
		_activate_after_save = false
		if saved:
			_assign_starting_battle()


func _save_to_path(path: String) -> bool:
	if _document == null:
		_set_status("Нет документа боя для сохранения.")
		return false
	var error := BattleDocumentSerializer.save(_document, path)

	if not error.is_empty():
		_set_status(error)
		return false

	_current_document_path = path
	_update_document_path_label()
	_set_status("Сохранено: %s" % ProjectSettings.globalize_path(path))
	return true


func _on_open_path_selected(path: String) -> void:
	if _snapshot == null:
		_set_status("Сначала исправьте ошибки загрузки библиотеки и обновите её.")
		return
	var load_result := BattleDocumentSerializer.load_result(path)
	var loaded := load_result.document

	if loaded == null:
		_set_status("Не удалось открыть %s: %s" % [path, load_result.error_message])
		return

	_document = loaded
	_history = EditorCommandHistory.new()
	_selected_placement_id = StringName()
	_selected_definition_id = StringName()
	_has_selected_hex = false
	_current_document_path = path
	_select_option_by_metadata(_background_option, _document.map_definition.background_id)
	_view.setup(_document)
	_view.select_placement(StringName())
	_populate_side_options()
	_populate_ai_options()
	_update_document_path_label()
	_validate_document()
	call_deferred("_frame_map")


func _suggested_document_filename() -> String:
	if _document == null or _document.battle_definition.id.is_empty():
		return DEFAULT_DRAFT_FILENAME

	var safe_name := String(_document.battle_definition.id).replace(":", "_")
	return "%s.json" % safe_name


func _ensure_json_extension(path: String) -> String:
	return path if path.get_extension().to_lower() == "json" else "%s.json" % path


func _update_document_path_label() -> void:
	_document_path_label.text = (
		"Файл: %s" % ProjectSettings.globalize_path(_current_document_path)
		if not _current_document_path.is_empty()
		else "Файл: не сохранён"
	)


func _use_in_game() -> void:
	if _document == null or _snapshot == null:
		return
	var validation := _document.validate(_snapshot)
	if not validation.is_valid:
		_validate_document()
		_set_status("Назначение заблокировано ошибками документа.")
		return
	if _current_document_path.is_empty():
		_activate_after_save = true
		_save_as()
		return
	if _save_to_path(_current_document_path):
		_assign_starting_battle()


func _assign_starting_battle() -> void:
	var result := ProjectBattleLoader.load_battle(content_packages, _current_document_path, trial_seed)
	if result.request == null:
		_set_status(result.error_message)
		return
	var error := GameContentSettings.select_battle(_current_document_path)
	_set_status(
		"Стартовый бой игры: %s" % ProjectSettings.globalize_path(_current_document_path)
		if error == OK else "Сохраните бой внутри content/: %s" % error_string(error)
	)


func _export() -> void:
	if _document == null:
		_set_status("Нет документа боя для экспорта.")
		return
	var path := GameContentSettings.EXPORTS.path_join(String(_document.battle_definition.id).replace(":", "_"))
	var error := EditorPackageExporter.export(_document, path)
	_set_status("Экспортировано: %s" % ProjectSettings.globalize_path(path) if error.is_empty() else error)


func _start_trial() -> void:
	if _document == null or _snapshot == null:
		_set_status("Сначала исправьте ошибки загрузки библиотеки и обновите её.")
		return
	var request := _document.create_start_request(_snapshot, trial_seed)

	if request == null:
		_validate_document()
		_set_status("Пробный запуск заблокирован ошибками документа.")
		return

	_trial_screen = BATTLE_SCREEN_SCENE.instantiate() as BattleScreen

	if not _trial_screen.setup(request):
		var error := _trial_screen.initialization_error
		_trial_screen.free()
		_trial_screen = null
		_set_status("Пробный запуск отклонён: %s" % error)
		return

	_trial_screen.battle_finished.connect(_on_trial_finished)
	_trial_screen.battle_failed.connect(_on_trial_failed)
	_ui.visible = false
	add_child(_trial_screen)
	_trial_return_layer = CanvasLayer.new()
	_trial_return_layer.layer = 100
	add_child(_trial_return_layer)
	var back := _button("Вернуться в редактор", _return_from_trial)
	back.position = Vector2(20, 12)
	_trial_return_layer.add_child(back)


func _on_trial_finished(result: BattleResult) -> void:
	# The battle screen keeps showing the outcome until the author returns.
	# The editor status is hidden meanwhile, so the outcome is reported on return.
	_trial_result = result


func _on_trial_failed(message: String) -> void:
	_return_from_trial()
	_set_status("Пробный бой не запущен: %s" % message)


func _return_from_trial() -> void:
	if _trial_screen == null:
		return

	if is_instance_valid(_trial_return_layer):
		_trial_return_layer.queue_free()

	_trial_return_layer = null
	_trial_screen.queue_free()
	_trial_screen = null
	_ui.visible = true
	var outcome := ""

	if _trial_result != null:
		outcome = " (%s)" % (
			"победа"
			if _trial_result.outcome == BattleOutcome.Value.VICTORY
			else "поражение"
		)

	_trial_result = null
	_set_status("Пробный бой завершён%s; BattleDocument не изменён." % outcome)


func _find_cell(hex: Vector2i) -> BattleMapCellDefinition:
	if _document == null:
		return null

	for cell: BattleMapCellDefinition in _document.map_definition.cells:
		if cell.hex == hex:
			return cell

	return null


func _find_placement(placement_id: StringName) -> UnitPlacementDefinition:
	if _document == null or placement_id.is_empty():
		return null

	for placement: UnitPlacementDefinition in _document.battle_definition.unit_placements:
		if placement.placement_id == placement_id:
			return placement

	return null


func _select_option_by_metadata(option: OptionButton, value: Variant) -> void:
	for index: int in range(option.item_count):
		if option.get_item_metadata(index) == value:
			option.select(index)
			return


func _show_load_errors(errors: Array[String]) -> void:
	for error: String in errors:
		_diagnostics.add_item(error)
	_set_status("Пакеты контента не загружены.")


func _set_status(message: String) -> void:
	_status.text = message


func _build_visual_controls(parent: Control) -> void:
	var toolbar := HBoxContainer.new()
	toolbar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	toolbar.offset_left = 16
	toolbar.offset_top = 8
	toolbar.offset_right = -380
	parent.add_child(toolbar)
	_background_option = OptionButton.new()
	for id: StringName in BattleBackdrops.NAMES:
		var index := _background_option.item_count
		_background_option.add_item(BattleBackdrops.NAMES[id])
		_background_option.set_item_metadata(index, id)
	_background_option.item_selected.connect(func(_index: int) -> void:
		if _document != null:
			_execute(EditCommand.set_background(_background_option.get_selected_metadata()))
	)
	toolbar.add_child(_background_option)
	for title: String in ["Сетка", "Юниты"]:
		var check := CheckButton.new()
		check.text = title
		check.button_pressed = true
		check.toggled.connect(func(enabled: bool) -> void:
			if title == "Сетка":
				_view.show_grid = enabled
			else:
				_view.show_units = enabled
			_view.refresh()
		)
		toolbar.add_child(check)
	toolbar.add_child(_button("По размеру окна", _frame_map))
	toolbar.add_child(_button("Отменить", _undo))
	toolbar.add_child(_button("Повторить", _redo))
	toolbar.add_child(_button("Сохранить", _save))
	toolbar.add_child(_button("Пробный бой", _start_trial))
	var palette := EditorStatePalette.new()
	palette.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	palette.offset_left = 16
	palette.offset_right = -380
	palette.offset_top = -142
	palette.offset_bottom = -8
	palette.state_selected.connect(func(id: StringName) -> void:
		_selected_state_id = id
		_select_tool(EditorBattleView.Tool.PAINT_STATE)
	)
	palette.erase_selected.connect(func() -> void: _select_tool(EditorBattleView.Tool.ERASE_STATE))
	parent.add_child(palette)


func _paint_state(hex: Vector2i, state_id: StringName) -> void:
	var cell := _find_cell(hex)
	if cell == null or cell.hex_state_id == state_id:
		return
	var updated := cell.duplicate(true) as BattleMapCellDefinition
	updated.hex_state_id = state_id
	updated.movement_cost = HexStateCatalog.get_movement_cost(state_id)
	_execute(EditCommand.update_hex(updated))


func _on_hex_erased(hex: Vector2i) -> void:
	if _view.active_tool == EditorBattleView.Tool.PLACE_UNIT or _view.active_tool == EditorBattleView.Tool.SELECT:
		for placement: UnitPlacementDefinition in _document.battle_definition.unit_placements:
			if placement.start_hex == hex:
				_execute(EditCommand.remove_placement(placement.placement_id))
				_selected_placement_id = StringName()
				_view.select_placement(StringName())
				return
	_paint_state(hex, StringName())


func _new_placement_id() -> StringName:
	var id := StringName("author:placement_%s" % _next_placement_number)
	while _find_placement(id) != null:
		_next_placement_number += 1
		id = StringName("author:placement_%s" % _next_placement_number)
	_next_placement_number += 1
	return id


func _free_hex_near(origin: Vector2i) -> Vector2i:
	var occupied: Dictionary[Vector2i, bool] = {}
	for placement: UnitPlacementDefinition in _document.battle_definition.unit_placements:
		occupied[placement.start_hex] = true
	var best := Vector2i(999999, 999999)
	var best_distance := 999999
	for cell: BattleMapCellDefinition in _document.map_definition.cells:
		if not cell.traversable or occupied.has(cell.hex) or not EditorBattleView.is_in_frame(cell.hex):
			continue
		var delta := cell.hex - origin
		var distance := maxi(absi(delta.x), maxi(absi(delta.y), absi(delta.x + delta.y)))
		if distance < best_distance:
			best_distance = distance
			best = cell.hex
	return best
