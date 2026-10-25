class_name BattleEditorShell
extends Control
## Coordinates the battle map editor: document workflow, edit commands, panels and trial battles.


const DEFAULT_DRAFT_FILENAME := "battle_editor_draft.json"
const BATTLE_SCREEN_SCENE := preload("res://features/battle/battle_screen.tscn")
const NO_HEX := Vector2i(999999, 999999)

enum FileAction { NEW, OPEN, SAVE, SAVE_AS, REFRESH_LIST, RELOAD_LIBRARY, EXPORT, USE_IN_GAME }


var content_packages: Array[ContentPackage] = []
@export var initial_battle_id: StringName = &"plateau:battle"
@export var trial_seed := 1


var _background_option: OptionButton
var _grid_layout_controls: EditorGridLayoutControls
var _battle_option: OptionButton
var _name_edit: LineEdit
var _dirty_label: Label
var _selected_state_id: StringName = &"core:electricity"
var _snapshot: ContentSnapshot
var _document: BattleDocument
var _history := EditorCommandHistory.new()
var _view: EditorBattleView
var _ui: Control
var _map_workspace: Control
var _tool_bar: EditorToolBar
var _inspector: BattleEditorInspector
var _state_palette: EditorStatePalette
var _roster: ItemList
var _palette: ItemList
var _palette_search: LineEdit
var _side_option: OptionButton
var _ai_option: OptionButton
var _validation_badge: Button
var _status: Label
var _cursor_label: Label
var _zoom_label: Label
var _selected_hex_label: Label
var _terrain_id_edit: LineEdit
var _movement_cost_spin: SpinBox
var _obstacle_type: OptionButton
var _obstacle_size: SpinBox
var _obstacle_direction: OptionButton
var _obstacle_destructible: CheckButton
var _obstacle_hp: SpinBox

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
var _unit_editor: UnitEditor
var _skill_editor: SkillEditor
var _discard_dialog: ConfirmationDialog
var _pending_discard_action: Callable
var _saved_document: Dictionary = {}
var _trial_result: BattleResult
var _trial_error := ""
## Names and portraits by definition ID for one snapshot; snapshot getters return deep copies.
var _unit_info: Dictionary[StringName, Dictionary] = {}
var _unit_info_snapshot: ContentSnapshot
## Folder of the first ordinary save of a new field; tests point it at user://.
var battles_directory := GameContentSettings.BATTLES


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	get_tree().auto_accept_quit = false
	_discard_dialog = EditorUi.confirm_discard(self, "Есть несохранённые изменения поля боя. Отбросить их?", _confirm_discard)
	_discard_dialog.theme = EditorUi.theme()
	var settings := GameContentSettings.read()
	if settings == null:
		_set_status("Не удалось прочитать content/game_content.tres.", EditorUi.Severity.ERROR)
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
			_set_status(loaded.error_message, EditorUi.Severity.ERROR)
			return
		_document = loaded.document
		_current_document_path = settings.battle_document_path
	else:
		_document = BattleDocument.from_snapshot(_snapshot, initial_battle_id)

	if _document == null:
		_set_status("Не удалось открыть стартовый бой.", EditorUi.Severity.ERROR)
		return

	_saved_document = BattleDocumentSerializer.to_dictionary(_document).duplicate(true)
	_select_option_by_metadata(_background_option, _document.map_definition.background_id)
	_view.snapshot = _snapshot
	_view.setup(_document)
	_populate_palette()
	_sync_grid_layout()
	_populate_side_options()
	_populate_ai_options()
	_update_document_path_label()
	_after_document_changed()
	_set_status("Открыт стартовый бой игры. Выберите инструмент сверху или нажмите его клавишу.")
	call_deferred("_frame_map")


func _build_ui() -> void:
	var root := EditorUi.background(self)
	_ui = root.get_parent() as Control
	# The skin is scoped to the editor UI: trial battles and embedded tools keep their own look.
	EditorUi.apply(_ui)
	_build_top_bar(root)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)
	var workspace_column := VBoxContainer.new()
	workspace_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace_column.add_theme_constant_override("separation", 0)
	body.add_child(workspace_column)
	var tools := EditorUi.bar(workspace_column)
	_tool_bar = EditorToolBar.new()
	_tool_bar.tool_selected.connect(_on_tool_selected)
	tools.add_child(_tool_bar)

	_map_workspace = Control.new()
	_map_workspace.name = "MapWorkspace"
	_map_workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_workspace.clip_contents = true
	_map_workspace.mouse_filter = Control.MOUSE_FILTER_STOP
	workspace_column.add_child(_map_workspace)
	_view = EditorBattleView.new()
	_view.hex_activated.connect(_on_hex_activated)
	_view.hex_erased.connect(_on_hex_erased)
	_view.placement_selected.connect(_on_placement_selected)
	_view.placement_moved.connect(_move_placement)
	_view.hovered_hex_changed.connect(_on_hovered_hex_changed)
	_map_workspace.add_child(_view)
	_map_workspace.gui_input.connect(func(event: InputEvent) -> void:
		if _view.handle_input(event):
			_map_workspace.accept_event()
	)
	_map_workspace.mouse_exited.connect(_view.clear_hover)
	_map_workspace.resized.connect(_frame_map)
	_build_map_overlay()
	_build_inspector(body)
	_build_status_bar(root)

	_save_dialog = _create_file_dialog(FileDialog.FILE_MODE_SAVE_FILE)
	_save_dialog.file_selected.connect(_on_save_path_selected)
	_open_dialog = _create_file_dialog(FileDialog.FILE_MODE_OPEN_FILE)
	_open_dialog.file_selected.connect(_on_open_path_selected)
	_update_inspector()


func _build_top_bar(root: Control) -> void:
	var bar := EditorUi.bar(root)
	bar.add_child(EditorUi.label("Редактор поля боя", &"TitleLabel"))
	var file_menu := MenuButton.new()
	file_menu.text = "Файл ▾"
	file_menu.flat = false
	var popup := file_menu.get_popup()
	popup.add_item("Новое поле", FileAction.NEW, (KEY_MASK_CMD_OR_CTRL | KEY_N) as Key)
	popup.add_item("Открыть…", FileAction.OPEN, (KEY_MASK_CMD_OR_CTRL | KEY_O) as Key)
	popup.add_separator()
	popup.add_item("Сохранить", FileAction.SAVE, (KEY_MASK_CMD_OR_CTRL | KEY_S) as Key)
	popup.add_item("Сохранить как…", FileAction.SAVE_AS, (KEY_MASK_CMD_OR_CTRL | KEY_MASK_SHIFT | KEY_S) as Key)
	popup.add_separator()
	popup.add_item("Обновить список полей", FileAction.REFRESH_LIST)
	popup.add_item("Перечитать библиотеку юнитов", FileAction.RELOAD_LIBRARY)
	popup.add_item("Экспорт копии документа", FileAction.EXPORT)
	popup.add_separator()
	popup.add_item("Сделать стартовым боем", FileAction.USE_IN_GAME)
	popup.id_pressed.connect(_on_file_action)
	bar.add_child(file_menu)
	bar.add_child(EditorUi.separator())
	bar.add_child(EditorUi.label("Поле", &"FieldLabel"))
	_battle_option = OptionButton.new()
	_battle_option.custom_minimum_size.x = 250
	_battle_option.fit_to_longest_item = false
	_battle_option.clip_text = true
	_battle_option.tooltip_text = "Сохранённые поля боя из content/authored/battles"
	_battle_option.item_selected.connect(_on_battle_selected)
	bar.add_child(_battle_option)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Название поля боя"
	_name_edit.max_length = 120
	_name_edit.custom_minimum_size.x = 250
	_name_edit.tooltip_text = "Название поля; ID и путь файла при переименовании не меняются."
	_name_edit.text_changed.connect(_on_name_changed)
	bar.add_child(_name_edit)
	_dirty_label = EditorUi.label("")
	bar.add_child(_dirty_label)
	bar.add_child(EditorUi.spacer())
	var undo := EditorUi.button("Отменить", _undo)
	EditorUi.add_shortcut(undo, KEY_Z, true)
	bar.add_child(undo)
	var redo := EditorUi.button("Повторить", _redo)
	EditorUi.add_shortcut(redo, KEY_Y, true)
	EditorUi.add_shortcut(redo, KEY_Z, true, true)
	bar.add_child(redo)
	bar.add_child(EditorUi.separator())
	bar.add_child(EditorUi.button("Юниты…", _open_unit_editor, "Открыть редактор юнитов; при возврате палитра обновится"))
	bar.add_child(EditorUi.button("Навыки…", _open_skill_editor, "Открыть редактор навыков и эффектов"))
	bar.add_child(EditorUi.separator())
	bar.add_child(EditorUi.button("Сохранить", _save, "Сохранить поле (Ctrl+S)"))
	bar.add_child(EditorUi.button("▶ Пробный бой", _start_trial, "Запустить текущий черновик в обычном бою без записи результата", &"PrimaryButton"))


func _build_map_overlay() -> void:
	var overlay := PanelContainer.new()
	overlay.theme_type_variation = &"EditorOverlay"
	overlay.anchor_left = 1.0
	overlay.anchor_right = 1.0
	overlay.offset_left = -12.0
	overlay.offset_right = -12.0
	overlay.offset_top = 12.0
	overlay.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_map_workspace.add_child(overlay)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	overlay.add_child(row)
	for title: String in ["Сетка", "Юниты"]:
		var check := CheckButton.new()
		check.text = title
		check.button_pressed = true
		check.focus_mode = Control.FOCUS_NONE
		check.tooltip_text = "Показать или скрыть %s. Документ не меняется." % ("сетку" if title == "Сетка" else "фигуры юнитов")
		check.toggled.connect(func(enabled: bool) -> void:
			if title == "Сетка":
				_view.show_grid = enabled
			else:
				_view.show_units = enabled
			_view.refresh()
		)
		row.add_child(check)
	row.add_child(EditorUi.separator())
	var zoom_out := EditorUi.button("−", func() -> void: _zoom_view(1.0 / 1.2), "Уменьшить")
	EditorUi.add_shortcut(zoom_out, KEY_MINUS)
	var zoom_in := EditorUi.button("+", func() -> void: _zoom_view(1.2), "Увеличить")
	EditorUi.add_shortcut(zoom_in, KEY_EQUAL)
	EditorUi.add_shortcut(zoom_in, KEY_PLUS)
	var fit := EditorUi.button("Вписать", _frame_map, "Показать всё поле")
	EditorUi.add_shortcut(fit, KEY_F)
	for button: Button in [zoom_out, zoom_in, fit]:
		button.focus_mode = Control.FOCUS_NONE
		row.add_child(button)


func _build_inspector(body: Control) -> void:
	_inspector = BattleEditorInspector.new()
	body.add_child(_inspector)
	# Short aliases keep the workflow code and its tests independent of the panel layout.
	_state_palette = _inspector.state_palette
	_palette = _inspector.palette
	_palette_search = _inspector.palette_search
	_roster = _inspector.roster
	_side_option = _inspector.side_option
	_ai_option = _inspector.ai_option
	_selected_hex_label = _inspector.selected_hex_label
	_terrain_id_edit = _inspector.terrain_id_edit
	_movement_cost_spin = _inspector.movement_cost_spin
	_traversable_check = _inspector.traversable_check
	_q_spin = _inspector.q_spin
	_r_spin = _inspector.r_spin
	_obstacle_type = _inspector.obstacle_type
	_obstacle_size = _inspector.obstacle_size
	_obstacle_direction = _inspector.obstacle_direction
	_obstacle_destructible = _inspector.obstacle_destructible
	_obstacle_hp = _inspector.obstacle_hp
	_document_path_label = _inspector.document_path_label
	_background_option = _inspector.background_option
	_grid_layout_controls = _inspector.grid_layout_controls

	_state_palette.state_selected.connect(func(id: StringName) -> void:
		_selected_state_id = id
		_select_tool(EditorBattleView.Tool.PAINT_STATE)
	)
	_state_palette.erase_selected.connect(func() -> void: _select_tool(EditorBattleView.Tool.ERASE_STATE))
	_palette_search.text_changed.connect(_on_palette_search_changed)
	_palette.item_selected.connect(_on_palette_selected)
	_roster.item_selected.connect(func(index: int) -> void: _on_placement_selected(_roster.get_item_metadata(index)))
	_side_option.item_selected.connect(_on_side_changed)
	_ai_option.item_selected.connect(_on_ai_override_changed)
	_obstacle_size.value_changed.connect(func(value: float) -> void:
		_view.obstacle_size = int(value)
		_view.refresh()
	)
	_obstacle_direction.item_selected.connect(func(index: int) -> void:
		_view.obstacle_direction = index
		_view.refresh()
	)
	_background_option.item_selected.connect(func(_index: int) -> void:
		if _document != null:
			_execute(EditCommand.set_background(_background_option.get_selected_metadata()))
	)
	_grid_layout_controls.offset_changed.connect(func(value: int, custom: bool) -> void:
		if _document != null:
			_execute(EditCommand.set_grid_offset(value, custom))
	)
	_grid_layout_controls.default_saved.connect(func(_value: int) -> void:
		_sync_grid_layout()
		_set_status("Высота по умолчанию сохранена для полей без своей настройки.", EditorUi.Severity.OK)
	)
	_grid_layout_controls.save_failed.connect(func(message: String) -> void: _set_status(message, EditorUi.Severity.ERROR))
	for pair: Array in [
		[_inspector.unit_editor_button, _open_unit_editor], [_inspector.reload_button, _reload_unit_library],
		[_inspector.duplicate_button, _duplicate_selected], [_inspector.delete_button, _delete_selected],
		[_inspector.hex_apply_button, _apply_selected_hex], [_inspector.add_hex_button, _add_hex_by_coordinates],
		[_inspector.remove_hex_button, _remove_hex_by_coordinates], [_inspector.obstacle_apply_button, _apply_selected_obstacle],
		[_inspector.obstacle_remove_button, _remove_selected_obstacle], [_inspector.open_button, _open_dialog_requested],
		[_inspector.save_as_button, _save_as], [_inspector.new_button, _new_document_requested],
		[_inspector.export_button, _export], [_inspector.check_button, _check_document],
		[_inspector.trial_button, _start_trial],
	]:
		(pair[0] as Button).pressed.connect(pair[1])
	for button: Button in _inspector.use_in_game_buttons:
		button.pressed.connect(_use_in_game)


func _build_status_bar(root: Control) -> void:
	var bar := EditorUi.bar(root, &"EditorStatusBar")
	_status = EditorUi.label("")
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.add_child(_status)
	_cursor_label = EditorUi.label("Курсор: вне поля", &"MutedLabel")
	_cursor_label.custom_minimum_size.x = 340
	_cursor_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bar.add_child(_cursor_label)
	_zoom_label = EditorUi.label("", &"MutedLabel")
	bar.add_child(_zoom_label)
	_validation_badge = Button.new()
	_validation_badge.flat = true
	_validation_badge.focus_mode = Control.FOCUS_NONE
	_validation_badge.tooltip_text = "Открыть вкладку «Проверка»"
	_validation_badge.pressed.connect(func() -> void: _inspector.current_tab = BattleEditorInspector.Page.CHECKS)
	bar.add_child(_validation_badge)


func _create_file_dialog(mode: FileDialog.FileMode) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode
	dialog.filters = PackedStringArray(["*.json ; Документ редактора боя"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GameContentSettings.BATTLES))
	dialog.current_dir = ProjectSettings.globalize_path(GameContentSettings.BATTLES)
	dialog.canceled.connect(func() -> void: _activate_after_save = false)
	dialog.size = Vector2i(820, 560)
	dialog.theme = EditorUi.theme()
	add_child(dialog)
	return dialog


func _on_file_action(id: int) -> void:
	match id:
		FileAction.NEW:
			_new_document_requested()
		FileAction.OPEN:
			_open_dialog_requested()
		FileAction.SAVE:
			_save()
		FileAction.SAVE_AS:
			_save_as()
		FileAction.REFRESH_LIST:
			_refresh_battle_library()
			_set_status("Список сохранённых полей обновлён.")
		FileAction.RELOAD_LIBRARY:
			_reload_unit_library()
		FileAction.EXPORT:
			_export()
		FileAction.USE_IN_GAME:
			_use_in_game()


func _on_tool_selected(tool: EditorBattleView.Tool) -> void:
	_apply_tool(tool)
	_set_status("Инструмент: %s. %s" % [EditorToolBar.caption(tool), EditorToolBar.help(tool)])


func _select_tool(tool: EditorBattleView.Tool) -> void:
	_tool_bar.select(tool)
	_apply_tool(tool)


func _apply_tool(tool: EditorBattleView.Tool) -> void:
	_view.set_tool(tool)
	_view.cancel_drag()
	_state_palette.show_brush(_selected_state_id, tool == EditorBattleView.Tool.ERASE_STATE)
	_inspector.current_tab = BattleEditorInspector.Page.INSPECTOR
	_update_inspector()


func _update_inspector() -> void:
	var placement := _find_placement(_selected_placement_id)
	_inspector.show_context(
		_view.active_tool,
		_placement_caption(placement) if placement != null else "",
		_definition_name(_selected_definition_id) if not _selected_definition_id.is_empty() else "",
		_has_selected_hex,
		_has_selected_hex and _obstacle_at(_selected_hex) != null,
	)


func _open_skill_editor() -> void:
	var editor := preload("res://tools/skills/skill_editor.tscn").instantiate() as SkillEditor
	editor.embedded = true
	_skill_editor = editor
	_ui.hide()
	editor.closed.connect(func() -> void:
		_skill_editor = null
		_ui.show()
		_reload_unit_library()
	)
	add_child(editor)


func _open_unit_editor() -> void:
	var editor := preload("res://tools/units/unit_editor.tscn").instantiate() as UnitEditor
	editor.embedded = true
	_unit_editor = editor
	_ui.hide()
	editor.closed.connect(func() -> void:
		_unit_editor = null
		_ui.show()
		_reload_unit_library()
	)
	add_child(editor)


func _reload_unit_library() -> void:
	var result := UnitLibrary.load_content(content_packages)
	if not result.is_successful:
		_show_load_errors(result.errors)
		_set_status("Библиотека не обновлена: исправьте ошибки файлов. Предыдущий снимок сохранён.", EditorUi.Severity.ERROR)
		return
	_snapshot = result.snapshot
	if _document == null:
		var settings := GameContentSettings.read()
		if settings != null and not settings.battle_document_path.is_empty():
			var loaded := BattleDocumentSerializer.load_result(settings.battle_document_path)
			_document = loaded.document
			if _document == null:
				_set_status(loaded.error_message, EditorUi.Severity.ERROR)
				return
			_current_document_path = settings.battle_document_path
		else:
			_document = BattleDocument.from_snapshot(_snapshot, initial_battle_id)
		if _document == null:
			_set_status("Не найден стартовый бой.", EditorUi.Severity.ERROR)
			return
		_saved_document = BattleDocumentSerializer.to_dictionary(_document).duplicate(true)
		_populate_side_options()
		_populate_ai_options()
		_update_document_path_label()
	_view.snapshot = _snapshot
	_view.setup(_document)
	_populate_palette(_palette_search.text)
	_sync_grid_layout()
	_after_document_changed()
	_set_status("Библиотека юнитов перечитана; черновик поля и история сохранены.", EditorUi.Severity.OK)


func _populate_palette(filter_text: String = "") -> void:
	_palette.clear()
	if _snapshot == null:
		return
	var filter := filter_text.strip_edges().to_lower()

	for definition: UnitDefinition in _snapshot.get_all_unit_definitions():
		var searchable := "%s %s" % [definition.display_name, definition.id]

		if not filter.is_empty() and not searchable.to_lower().contains(filter):
			continue

		var index := _palette.add_item(definition.display_name)
		_palette.set_item_metadata(index, definition.id)
		var stats := definition.base_stats
		_palette.set_item_tooltip(index, "%s\nОЗ %d · урон %d · дальность %d · передвижение %d" % [
			definition.id, stats.max_health, stats.basic_attack_damage, stats.basic_attack_range, stats.movement_points,
		] if stats != null else String(definition.id))
		_palette.set_item_icon(index, _portrait_for(definition.id))
		if definition.id == _selected_definition_id:
			_palette.select(index)


func _populate_side_options() -> void:
	_side_option.clear()

	for side: BattleSideDefinition in _document.battle_definition.sides:
		var index := _side_option.item_count
		_side_option.add_item("%s · %s%s" % [
			side.side_id,
			"игрок" if side.faction == BattleFaction.Value.PLAYER else "противник",
			", ИИ" if side.control_source == BattleControlSource.Value.AI else "",
		])
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


func _refresh_roster() -> void:
	_roster.clear()
	if _document == null:
		return
	var placements := _document.battle_definition.unit_placements.duplicate()
	placements.sort_custom(func(a: UnitPlacementDefinition, b: UnitPlacementDefinition) -> bool:
		return [String(a.side_id), a.start_hex.y, a.start_hex.x] < [String(b.side_id), b.start_hex.y, b.start_hex.x]
	)
	for placement: UnitPlacementDefinition in placements:
		var index := _roster.add_item(_placement_caption(placement), _portrait_for(placement.definition_id))
		_roster.set_item_metadata(index, placement.placement_id)
		_roster.set_item_tooltip(index, String(placement.placement_id))
	_sync_roster_selection()


func _sync_roster_selection() -> void:
	_roster.deselect_all()
	for index: int in range(_roster.item_count):
		if _roster.get_item_metadata(index) == _selected_placement_id:
			_roster.select(index)
			_roster.ensure_current_is_visible()


func _placement_caption(placement: UnitPlacementDefinition) -> String:
	return "%s — %s (q %d, r %d)" % [_definition_name(placement.definition_id), placement.side_id, placement.start_hex.x, placement.start_hex.y]


func _definition_name(definition_id: StringName) -> String:
	return String(_describe_unit(definition_id).get("name", definition_id))


func _portrait_for(definition_id: StringName) -> Texture2D:
	return _describe_unit(definition_id).get("portrait") as Texture2D


func _describe_unit(definition_id: StringName) -> Dictionary:
	if _snapshot == null:
		return {}
	if _unit_info_snapshot != _snapshot:
		_unit_info.clear()
		_unit_info_snapshot = _snapshot
	if not _unit_info.has(definition_id):
		var info := {}
		var definition := _snapshot.get_unit_definition(definition_id)
		if definition != null:
			info["name"] = definition.display_name
			var presentation := _snapshot.get_unit_presentation_definition(definition.presentation_id)
			if presentation != null:
				info["portrait"] = presentation.portrait_texture if presentation.portrait_texture != null else presentation.actor_texture
		_unit_info[definition_id] = info
	return _unit_info[definition_id]


func _on_palette_search_changed(text: String) -> void:
	_populate_palette(text)


func _on_palette_selected(index: int) -> void:
	_selected_definition_id = _palette.get_item_metadata(index)
	_selected_placement_id = StringName()
	_view.select_placement(StringName())
	_sync_roster_selection()
	_select_tool(EditorBattleView.Tool.PLACE_UNIT)
	_set_status("Выбран юнит «%s». Щёлкните по свободному гексу." % _definition_name(_selected_definition_id))


func _on_placement_selected(placement_id: StringName) -> void:
	_selected_placement_id = placement_id
	_selected_definition_id = StringName()
	_has_selected_hex = false
	_view.select_placement(placement_id)
	var placement := _find_placement(placement_id)

	if placement == null:
		_update_inspector()
		return

	_select_option_by_metadata(_side_option, placement.side_id)
	_select_option_by_metadata(_ai_option, placement.ai_profile_override_id)
	_sync_roster_selection()
	_update_inspector()
	_set_status("Выбран юнит «%s». Перетащите его на другой гекс; Delete — удалить, Ctrl+D — дублировать." % _definition_name(placement.definition_id))


func _on_hovered_hex_changed(hex: Vector2i, is_inside: bool) -> void:
	if not is_inside or _document == null:
		_cursor_label.text = "Курсор: вне поля"
		return
	var parts: PackedStringArray = ["q %d, r %d" % [hex.x, hex.y]]
	var cell := _find_cell(hex)
	if cell == null:
		parts.append("клетки нет")
	else:
		if not cell.hex_state_id.is_empty():
			parts.append(HexStateCatalog.get_display_name(cell.hex_state_id))
		parts.append("ход %d" % cell.movement_cost)
		if not cell.traversable:
			parts.append("непроходим")
		if _obstacle_at(hex) != null:
			parts.append("препятствие")
	for placement: UnitPlacementDefinition in _document.battle_definition.unit_placements:
		if placement.start_hex == hex:
			parts.append(_definition_name(placement.definition_id))
	_cursor_label.text = " · ".join(parts)


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
			_update_hex(hex, true, false)

		EditorBattleView.Tool.PAINT_COST:
			_update_hex(hex, false, true)

		EditorBattleView.Tool.PAINT_OBSTACLE:
			_put_obstacle(hex)

		EditorBattleView.Tool.PLACE_UNIT:
			_place_or_move_unit(hex)


func _select_hex(hex: Vector2i) -> void:
	var cell := _find_cell(hex)
	# Any click on the map replaces the previous selection, including the unit selection.
	_selected_placement_id = StringName()
	_selected_definition_id = StringName()
	_sync_roster_selection()

	if cell == null:
		_has_selected_hex = false
		_view.select_hex(hex, false)
		_selected_hex_label.text = "Гекс q=%d, r=%d отсутствует" % [hex.x, hex.y]
		_update_inspector()
		_set_status("Клетки q=%d, r=%d нет на карте. Восстановите её инструментом «+ Гексы»." % [hex.x, hex.y])
		return

	_selected_hex = hex
	_has_selected_hex = true
	_view.select_hex(hex)
	_terrain_id_edit.text = String(cell.terrain_id)
	_movement_cost_spin.value = cell.movement_cost
	_traversable_check.button_pressed = cell.traversable and _obstacle_at(hex) == null
	var obstacle := _obstacle_at(hex)
	if obstacle != null:
		_obstacle_type.select(BattleObstacleDefinition.TYPES.find(obstacle.terrain_type))
		_obstacle_size.value = obstacle.hexes.size()
		_obstacle_destructible.button_pressed = obstacle.destructible
		_obstacle_hp.editable = obstacle.destructible
		_obstacle_hp.value = obstacle.max_hp
		if obstacle.hexes.size() > 1:
			_obstacle_direction.select(HexGrid.DIRECTIONS.find(obstacle.hexes[1] - obstacle.hexes[0]))
		_view.obstacle_direction = _obstacle_direction.selected
	_selected_hex_label.text = "Выбран гекс q=%d, r=%d%s" % [hex.x, hex.y, " · " + HexStateCatalog.get_display_name(cell.hex_state_id) if not cell.hex_state_id.is_empty() else ""]
	_update_inspector()
	_set_status("Свойства гекса загружены в инспектор.")


func _clear_selection() -> void:
	_selected_placement_id = StringName()
	_selected_definition_id = StringName()
	_has_selected_hex = false
	_view.select_placement(StringName())
	_view.cancel_drag()
	_palette.deselect_all()
	_sync_roster_selection()
	_selected_hex_label.text = "Гекс не выбран"
	_update_inspector()


func _unhandled_key_input(event: InputEvent) -> void:
	if not _ui.visible or _trial_screen != null:
		return
	if event.is_action_pressed("ui_cancel"):
		_clear_selection()
		get_viewport().set_input_as_handled()


func _add_hex(hex: Vector2i) -> void:
	if not EditorBattleView.is_in_frame(hex):
		_set_status("Максимальная сетка — 18×12.", EditorUi.Severity.WARN)
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
	if _obstacle_at(hex) != null:
		_set_status("Сначала удалите препятствие целиком.", EditorUi.Severity.WARN)
		return
	if _find_cell(hex) == null:
		return

	if _hex_is_occupied(hex):
		_set_status("Сначала переместите или удалите юнита с этого гекса.", EditorUi.Severity.WARN)
		return
	_execute(EditCommand.remove_hex(hex))


func _update_hex(
	hex: Vector2i,
	change_terrain: bool,
	change_cost: bool
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

	_execute(EditCommand.update_hex(updated))


func _apply_selected_hex() -> void:
	if _has_selected_hex and _obstacle_at(_selected_hex) != null:
		_set_status("Используйте свойства препятствия или удалите его целиком.", EditorUi.Severity.WARN)
		return
	if not _has_selected_hex:
		_set_status("Сначала выберите существующий гекс.", EditorUi.Severity.WARN)
		return

	var cell := _find_cell(_selected_hex)

	if cell == null:
		_set_status("Выбранный гекс больше не существует.", EditorUi.Severity.WARN)
		return

	var updated := cell.duplicate(true) as BattleMapCellDefinition
	updated.terrain_id = _brush_terrain_id()
	updated.movement_cost = int(_movement_cost_spin.value)
	if not updated.hex_state_id.is_empty():
		updated.movement_cost = HexStateCatalog.get_movement_cost(updated.hex_state_id)
	if not _traversable_check.button_pressed and _hex_is_occupied(_selected_hex):
		_set_status("Нельзя сделать занятый гекс непроходимым.", EditorUi.Severity.WARN)
		return
	updated.traversable = _traversable_check.button_pressed
	_execute(EditCommand.update_hex(updated))
	_set_status("Свойства гекса q=%d, r=%d обновлены." % [_selected_hex.x, _selected_hex.y], EditorUi.Severity.OK)


func _brush_terrain_id() -> StringName:
	var value := _terrain_id_edit.text.strip_edges()
	return StringName(value if not value.is_empty() else "core:default")


func _add_hex_by_coordinates() -> void:
	_add_hex(_selected_coordinate())


func _remove_hex_by_coordinates() -> void:
	_remove_hex(_selected_coordinate())


func _selected_coordinate() -> Vector2i:
	return Vector2i(int(_q_spin.value), int(_r_spin.value))


## Empty when a unit (other than the ignored one) may start on the hex.
func _placement_target_error(hex: Vector2i, ignored_placement_id: StringName) -> String:
	for existing: UnitPlacementDefinition in _document.battle_definition.unit_placements:
		if existing.start_hex == hex and existing.placement_id != ignored_placement_id:
			return "Гекс уже занят юнитом."
	var cell := _find_cell(hex)
	if cell == null:
		return "Юнита можно поставить только на существующий гекс."
	if not cell.traversable or _obstacle_at(hex) != null:
		return "Нельзя поставить юнита на непроходимый гекс."
	return ""


func _place_or_move_unit(hex: Vector2i) -> void:
	if not _selected_placement_id.is_empty():
		if _move_placement(_selected_placement_id, hex):
			_select_tool(EditorBattleView.Tool.SELECT)
		return
	var error := _placement_target_error(hex, StringName())
	if not error.is_empty():
		_set_status(error, EditorUi.Severity.WARN)
		return

	if _selected_definition_id.is_empty() or _side_option.item_count == 0:
		_set_status("Сначала выберите юнита из списка или маркер на поле.", EditorUi.Severity.WARN)
		return

	var placement := UnitPlacementDefinition.new()
	placement.placement_id = _new_placement_id()
	placement.definition_id = _selected_definition_id
	placement.side_id = _side_option.get_selected_metadata()
	placement.start_hex = hex
	placement.ai_profile_override_id = _ai_option.get_selected_metadata()
	_execute(EditCommand.add_placement(placement))
	_view.select_placement(StringName())


func _move_placement(placement_id: StringName, hex: Vector2i) -> bool:
	if _find_placement(placement_id) == null:
		return false
	var error := _placement_target_error(hex, placement_id)
	if not error.is_empty():
		_set_status(error, EditorUi.Severity.WARN)
		return false
	_selected_placement_id = placement_id
	_execute(EditCommand.move_placement(placement_id, hex))
	_set_status("Юнит перемещён на q=%d, r=%d." % [hex.x, hex.y], EditorUi.Severity.OK)
	return true


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
		_set_status("Сначала выберите маркер юнита на поле.", EditorUi.Severity.WARN)
		return

	var destination := _free_hex_near(placement.start_hex)
	if destination == NO_HEX:
		_set_status("Нет свободного проходимого гекса для копии.", EditorUi.Severity.WARN)
		return
	var new_id := _new_placement_id()
	if _execute(EditCommand.duplicate_placement(placement.placement_id, new_id, destination)):
		_selected_placement_id = new_id
		_after_selection_changed()


func _delete_selected() -> void:
	if _selected_placement_id.is_empty():
		_set_status("Сначала выберите маркер юнита на поле.", EditorUi.Severity.WARN)
		return

	_execute(EditCommand.remove_placement(_selected_placement_id))


func _execute(command: EditCommand) -> bool:
	if _document == null:
		_set_status("Сначала исправьте ошибки загрузки библиотеки и обновите её.", EditorUi.Severity.ERROR)
		return false
	if not _history.execute(command, _document):
		_set_status("Команда не применена.", EditorUi.Severity.WARN)
		return false

	_after_document_changed()
	return true


func _undo() -> void:
	if _document != null and _history.undo(_document):
		_after_document_changed()
		_set_status("Отменено.")
	else:
		_set_status("Нечего отменять.")


func _redo() -> void:
	if _document != null and _history.redo(_document):
		_after_document_changed()
		_set_status("Повторено.")
	else:
		_set_status("Нечего повторять.")


func _after_document_changed() -> void:
	if _document == null:
		return
	_view.setup(_document)
	_sync_grid_layout()
	_sync_document_name()
	_select_option_by_metadata(_background_option, _document.map_definition.background_id)
	_validate_document()
	_refresh_roster()
	_after_selection_changed()
	_update_dirty()


## Drops selections that undo or deletion removed from the document.
func _after_selection_changed() -> void:
	if not _selected_placement_id.is_empty() and _find_placement(_selected_placement_id) == null:
		_selected_placement_id = StringName()
	if _has_selected_hex and _find_cell(_selected_hex) == null:
		_has_selected_hex = false
		_selected_hex_label.text = "Гекс удалён"
	if not _selected_placement_id.is_empty():
		_view.select_placement(_selected_placement_id)
	elif _has_selected_hex:
		_view.select_hex(_selected_hex)
	else:
		_view.select_placement(StringName())
	_sync_roster_selection()
	_update_inspector()


func _update_dirty() -> void:
	EditorUi.set_dirty(_dirty_label, has_unsaved_changes(), not _current_document_path.is_empty())


func _sync_grid_layout() -> void:
	_grid_layout_controls.sync(_document.map_definition if _document != null else null)
	_view.default_grid_offset_y = _grid_layout_controls.default_offset_y
	_view.refresh()


func _frame_map() -> void:
	if _view == null or _map_workspace == null:
		return
	_view.frame_document(_map_workspace.size)
	_update_zoom_label()


func _zoom_view(factor: float) -> void:
	_view.zoom_by(factor, _map_workspace.size)
	_update_zoom_label()


func _update_zoom_label() -> void:
	_zoom_label.text = "Масштаб %d%%" % roundi(_view.get_zoom() * 100.0)


func _validate_document() -> void:
	if _document == null or _snapshot == null:
		return

	var validation := _document.validate(_snapshot)
	_inspector.show_validation(validation.errors, validation.warnings)
	if validation.is_valid:
		_validation_badge.text = "✓ Готово к запуску" + (" · предупреждений: %d" % validation.warnings.size() if not validation.warnings.is_empty() else "")
		_validation_badge.add_theme_color_override("font_color", EditorUi.OK)
	else:
		_validation_badge.text = "✗ Ошибок: %d" % validation.errors.size()
		_validation_badge.add_theme_color_override("font_color", EditorUi.ERROR)


func _check_document() -> void:
	_validate_document()
	_inspector.current_tab = BattleEditorInspector.Page.CHECKS
	_set_status(_inspector.validation_summary.text, EditorUi.Severity.OK if _inspector.diagnostics.item_count == 0 else EditorUi.Severity.WARN)


## The first ordinary save of a new field never replaces another battle's file silently.
func _save() -> void:
	if _document == null:
		return
	if not _current_document_path.is_empty():
		_save_to_path(_current_document_path)
		return
	var path := battles_directory.path_join(_suggested_document_filename())
	if FileAccess.file_exists(path) and not _is_same_document(path):
		_set_status("Файл %s принадлежит другому полю: выберите имя файла." % path.get_file(), EditorUi.Severity.WARN)
		_save_as()
		return
	_save_to_path(path)


func _is_same_document(path: String) -> bool:
	var existing := BattleDocumentSerializer.load_result(path).document
	return existing != null and existing.document_id == _document.document_id


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
		_set_status("Нет документа боя для сохранения.", EditorUi.Severity.ERROR)
		return false
	var error := BattleDocumentSerializer.save(_document, path)

	if not error.is_empty():
		_set_status("Не сохранено: %s" % error, EditorUi.Severity.ERROR)
		return false

	_current_document_path = path
	_saved_document = BattleDocumentSerializer.to_dictionary(_document).duplicate(true)
	_update_document_path_label()
	_update_dirty()
	_set_status("Сохранено: %s" % ProjectSettings.globalize_path(path), EditorUi.Severity.OK)
	return true


func _on_open_path_selected(path: String) -> void:
	_guard_discard(_load_document_path.bind(path))


func _load_document_path(path: String) -> void:
	if _snapshot == null:
		_set_status("Сначала исправьте ошибки загрузки библиотеки и обновите её.", EditorUi.Severity.ERROR)
		return
	var load_result := BattleDocumentSerializer.load_result(path)
	var loaded := load_result.document

	if loaded == null:
		_set_status("Не удалось открыть %s: %s" % [path, load_result.error_message], EditorUi.Severity.ERROR)
		return

	_replace_document(loaded, path, true)
	_set_status("Открыто: %s" % ProjectSettings.globalize_path(path))


func _replace_document(loaded: BattleDocument, path: String, saved: bool) -> void:
	_document = loaded
	_saved_document = BattleDocumentSerializer.to_dictionary(_document).duplicate(true)
	if not saved:
		_saved_document = {}
	_history = EditorCommandHistory.new()
	_selected_placement_id = StringName()
	_selected_definition_id = StringName()
	_has_selected_hex = false
	_current_document_path = path
	_next_placement_number = 1
	_selected_hex_label.text = "Гекс не выбран"
	_select_option_by_metadata(_background_option, _document.map_definition.background_id)
	_view.setup(_document)
	_view.select_placement(StringName())
	_sync_grid_layout()
	_populate_side_options()
	_populate_ai_options()
	_update_document_path_label()
	_after_document_changed()
	call_deferred("_frame_map")


func _new_document_requested() -> void:
	_guard_discard(_create_new_document)


func _create_new_document() -> void:
	if _snapshot == null:
		_set_status("Сначала исправьте ошибки загрузки библиотеки и обновите её.", EditorUi.Severity.ERROR)
		return
	var document := BattleLibrary.create_document(_snapshot, initial_battle_id)
	if document == null:
		_set_status("Не удалось создать поле: проверьте загрузку базового контента.", EditorUi.Severity.ERROR)
		return
	_replace_document(document, "", false)
	_set_status("Создано новое поле 18×12. Введите название и сохраните его.")


func _on_name_changed(value: String) -> void:
	if _document != null and _document.display_name != value:
		_execute(EditCommand.rename_document(value))


func _sync_document_name() -> void:
	var value := _document.display_name if _document != null else ""
	if _name_edit.text == value:
		return
	_name_edit.set_block_signals(true)
	_name_edit.text = value
	_name_edit.set_block_signals(false)


func _refresh_battle_library() -> void:
	_battle_option.clear()
	_battle_option.add_item("Текущее поле: не сохранено" if _current_document_path.is_empty() else "Текущее поле")
	_battle_option.set_item_metadata(0, "")
	_battle_option.set_item_disabled(0, true)
	var current := ProjectSettings.globalize_path(_current_document_path) if not _current_document_path.is_empty() else ""
	for entry: Dictionary in BattleLibrary.list_documents():
		var index := _battle_option.item_count
		_battle_option.add_item(entry.label)
		_battle_option.set_item_metadata(index, entry.path)
		_battle_option.set_item_tooltip(index, entry.path if String(entry.error).is_empty() else entry.error)
		_battle_option.set_item_disabled(index, not String(entry.error).is_empty())
		if ProjectSettings.globalize_path(entry.path) == current:
			_battle_option.select(index)


func _on_battle_selected(index: int) -> void:
	var path := String(_battle_option.get_item_metadata(index))
	_refresh_battle_library()
	if not path.is_empty() and ProjectSettings.globalize_path(path) != ProjectSettings.globalize_path(_current_document_path):
		_guard_discard(_load_document_path.bind(path))


func _suggested_document_filename() -> String:
	if _document == null or _document.battle_definition.id.is_empty():
		return DEFAULT_DRAFT_FILENAME

	var safe_name := String(_document.battle_definition.id).replace(":", "_")
	return "%s.json" % safe_name


func _ensure_json_extension(path: String) -> String:
	return path if path.get_extension().to_lower() == "json" else "%s.json" % path


func _update_document_path_label() -> void:
	_sync_document_name()
	_refresh_battle_library()
	# Legacy fields without a name are listed by file name; the empty field says so.
	_name_edit.placeholder_text = (
		"Без названия · %s" % _current_document_path.get_file().get_basename()
		if not _current_document_path.is_empty() else "Название поля боя"
	)
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
		_inspector.current_tab = BattleEditorInspector.Page.CHECKS
		_set_status("Назначение заблокировано ошибками документа.", EditorUi.Severity.ERROR)
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
		_set_status(result.error_message, EditorUi.Severity.ERROR)
		return
	var error := GameContentSettings.select_battle(_current_document_path)
	if error == OK:
		_set_status("Стартовый бой игры: %s" % ProjectSettings.globalize_path(_current_document_path), EditorUi.Severity.OK)
	else:
		_set_status("Сохраните бой внутри content/: %s" % error_string(error), EditorUi.Severity.ERROR)


func _export() -> void:
	if _document == null:
		_set_status("Нет документа боя для экспорта.", EditorUi.Severity.ERROR)
		return
	var path := GameContentSettings.EXPORTS.path_join(String(_document.battle_definition.id).replace(":", "_"))
	var error := EditorPackageExporter.export(_document, path)
	if error.is_empty():
		_set_status("Экспортировано: %s" % ProjectSettings.globalize_path(path), EditorUi.Severity.OK)
	else:
		_set_status(error, EditorUi.Severity.ERROR)


func _start_trial() -> void:
	if _document == null or _snapshot == null:
		_set_status("Сначала исправьте ошибки загрузки библиотеки и обновите её.", EditorUi.Severity.ERROR)
		return
	if _trial_screen != null:
		return
	var request := _document.create_start_request(_snapshot, trial_seed)

	if request == null:
		_validate_document()
		_inspector.current_tab = BattleEditorInspector.Page.CHECKS
		_set_status("Пробный запуск заблокирован ошибками документа.", EditorUi.Severity.ERROR)
		return

	_trial_screen = BATTLE_SCREEN_SCENE.instantiate() as BattleScreen

	_trial_screen.show_failure_message = false
	if not _trial_screen.setup(request):
		var error := _trial_screen.initialization_error
		_trial_screen.free()
		_trial_screen = null
		_set_status("Пробный запуск отклонён: %s" % error, EditorUi.Severity.ERROR)
		return

	_trial_screen.battle_finished.connect(_on_trial_finished)
	_trial_screen.battle_failed.connect(_on_trial_failed)
	_ui.visible = false
	add_child(_trial_screen)
	_trial_return_layer = CanvasLayer.new()
	_trial_return_layer.layer = 100
	add_child(_trial_return_layer)
	var back := EditorUi.button("← Вернуться в редактор", _return_from_trial)
	back.theme = EditorUi.theme()
	back.position = Vector2(20, 12)
	_trial_return_layer.add_child(back)


func _on_trial_finished(result: BattleResult) -> void:
	# The battle screen keeps showing the outcome until the author returns.
	# The editor status is hidden meanwhile, so the outcome is reported on return.
	_trial_result = result


func _on_trial_failed(message: String) -> void:
	if _trial_screen == null or not _trial_screen.has_started():
		_return_from_trial()
		_set_status("Пробный бой не запущен: %s" % message, EditorUi.Severity.ERROR)
		return
	# A battle that stopped mid-play stays visible for diagnosis until the author returns.
	_trial_error = message
	var label := Label.new()
	label.name = "TrialError"
	label.text = "Бой остановлен из-за ошибки:\n%s" % message
	label.position = Vector2(20, 60)
	label.custom_minimum_size.x = 850
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", EditorUi.ERROR)
	_trial_return_layer.add_child(label)


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
	if not _trial_error.is_empty():
		_set_status("Пробный бой остановлен ошибкой: %s; BattleDocument не изменён." % _trial_error, EditorUi.Severity.ERROR)
		_trial_error = ""
		return
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
	_inspector.show_load_errors(errors)
	_set_status("Пакеты контента не загружены.", EditorUi.Severity.ERROR)


func _set_status(message: String, severity := EditorUi.Severity.INFO) -> void:
	EditorUi.set_status(_status, message, severity)
	_status.tooltip_text = message


func _paint_state(hex: Vector2i, state_id: StringName) -> void:
	var cell := _find_cell(hex)
	if _obstacle_at(hex) != null:
		_set_status("К препятствиям состояния не применяются.", EditorUi.Severity.WARN)
		return
	if cell == null or cell.hex_state_id == state_id:
		return
	var updated := cell.duplicate(true) as BattleMapCellDefinition
	updated.hex_state_id = state_id
	updated.movement_cost = HexStateCatalog.get_movement_cost(state_id)
	_execute(EditCommand.update_hex(updated))


func _on_hex_erased(hex: Vector2i) -> void:
	var obstacle := _obstacle_at(hex)
	if obstacle != null:
		_execute(EditCommand.remove_obstacle(obstacle.id))
		return
	if _view.active_tool == EditorBattleView.Tool.PLACE_UNIT or _view.active_tool == EditorBattleView.Tool.SELECT:
		for placement: UnitPlacementDefinition in _document.battle_definition.unit_placements:
			if placement.start_hex == hex:
				_execute(EditCommand.remove_placement(placement.placement_id))
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
	var best := NO_HEX
	var best_distance := 999999
	for cell: BattleMapCellDefinition in _document.map_definition.cells:
		if not cell.traversable or _obstacle_at(cell.hex) != null or occupied.has(cell.hex) or not EditorBattleView.is_in_frame(cell.hex):
			continue
		var delta := cell.hex - origin
		var distance := maxi(absi(delta.x), maxi(absi(delta.y), absi(delta.x + delta.y)))
		if distance < best_distance:
			best_distance = distance
			best = cell.hex
	return best


func has_unsaved_changes() -> bool:
	return _document != null and BattleDocumentSerializer.to_dictionary(_document) != _saved_document

func _guard_discard(action: Callable) -> void:
	if not has_unsaved_changes():
		action.call()
		return
	_pending_discard_action = action
	_discard_dialog.popup_centered()

func _confirm_discard() -> void:
	var action := _pending_discard_action
	_pending_discard_action = Callable()
	if action.is_valid():
		action.call()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_node_ready():
		request_quit()


## The embedded unit editor confirms its own draft first; quitting then guards the battle draft.
func request_quit() -> void:
	var quit_guarded := func() -> void: _guard_discard(func() -> void: get_tree().quit())
	if is_instance_valid(_skill_editor):
		_skill_editor.request_close(quit_guarded)
	elif is_instance_valid(_unit_editor):
		_unit_editor.request_close(quit_guarded)
	else:
		quit_guarded.call()

func _exit_tree() -> void:
	if get_tree() != null:
		get_tree().auto_accept_quit = true

func _hex_is_occupied(hex: Vector2i) -> bool:
	if _document == null:
		return false
	for placement: UnitPlacementDefinition in _document.battle_definition.unit_placements:
		if placement.start_hex == hex:
			return true
	return false


func _obstacle_at(hex: Vector2i) -> BattleObstacleDefinition:
	if _document == null:
		return null
	for obstacle: BattleObstacleDefinition in _document.map_definition.obstacles:
		if obstacle.hexes.has(hex):
			return obstacle
	return null

func _apply_selected_obstacle() -> void:
	if _has_selected_hex:
		_put_obstacle(_selected_hex)
	else:
		_set_status("Выберите начальный гекс или используйте кисть препятствий.", EditorUi.Severity.WARN)

func _remove_selected_obstacle() -> void:
	if not _has_selected_hex:
		return
	var obstacle := _obstacle_at(_selected_hex)
	if obstacle != null:
		_execute(EditCommand.remove_obstacle(obstacle.id))

## Obstacle IDs stay unique inside the document across editor sessions.
func _new_obstacle_id() -> StringName:
	var id := StringName()
	while id.is_empty() or _document.map_definition.obstacles.any(func(obstacle: BattleObstacleDefinition) -> bool: return obstacle.id == id):
		id = StringName("obstacle:%s" % Crypto.new().generate_random_bytes(8).hex_encode())
	return id

func _put_obstacle(hex: Vector2i) -> void:
	var previous := _obstacle_at(hex)
	var value := BattleObstacleDefinition.new()
	value.id = previous.id if previous != null else _new_obstacle_id()
	value.terrain_type = BattleObstacleDefinition.TYPES[_obstacle_type.selected]
	value.destructible = _obstacle_destructible.button_pressed
	value.max_hp = int(_obstacle_hp.value)
	value.current_hp = value.max_hp
	var origin := previous.hexes[0] if previous != null else hex
	for index in range(int(_obstacle_size.value)):
		var occupied := origin + HexGrid.DIRECTIONS[_obstacle_direction.selected] * index
		if not EditorBattleView.is_in_frame(occupied) or _find_cell(occupied) == null or not _find_cell(occupied).traversable or _hex_is_occupied(occupied):
			_set_status("Препятствие требует свободные существующие гексы внутри поля.", EditorUi.Severity.WARN)
			return
		var other := _obstacle_at(occupied)
		if other != null and other != previous:
			_set_status("Препятствия не могут пересекаться.", EditorUi.Severity.WARN)
			return
		value.hexes.append(occupied)
	if _execute(EditCommand.put_obstacle(value, previous.id if previous != null else &"")):
		_select_hex(origin)
