class_name BattleEditorShell
extends Node


const DEFAULT_DRAFT_PATH := "user://battle_editor_draft.json"
const BATTLE_SCREEN_SCENE := preload("res://features/battle/battle_screen.tscn")

@export var content_packages: Array[ContentPackage] = []
@export var initial_battle_id: StringName = &"ember_pack:crossing_battle"
@export var trial_seed := 1

var _snapshot: ContentSnapshot
var _document: EditorDocument
var _history := EditorCommandHistory.new()
var _view: EditorBattleView
var _ui: Control
var _palette: ItemList
var _palette_search: LineEdit
var _side_option: OptionButton
var _ai_option: OptionButton
var _diagnostics: ItemList
var _status: Label
var _q_spin: SpinBox
var _r_spin: SpinBox
var _selected_definition_id: StringName
var _selected_placement_id: StringName
var _next_placement_number := 1
var _trial_screen: BattleScreen


func _ready() -> void:
	_build_ui()
	var load_result := ContentLoader.load_packages(content_packages)

	if not load_result.is_successful:
		_show_load_errors(load_result.errors)
		return

	_snapshot = load_result.snapshot
	_document = EditorDocument.from_snapshot(_snapshot, initial_battle_id)

	if _document == null:
		_set_status("Не удалось открыть стартовый бой.")
		return

	_view.setup(_document)
	_populate_palette()
	_populate_side_options()
	_populate_ai_options()
	_validate_document()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.055, 0.07, 0.09)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_ui = background

	_view = EditorBattleView.new()
	_view.position = Vector2(90, 150)
	_view.hex_selected.connect(_on_hex_selected)
	_view.placement_selected.connect(_on_placement_selected)
	add_child(_view)

	var panel := PanelContainer.new()
	panel.position = Vector2(900, 16)
	panel.size = Vector2(360, 688)
	background.add_child(panel)
	var root := VBoxContainer.new()
	panel.add_child(root)

	var title := Label.new()
	title.text = "Редактор боя"
	title.add_theme_font_size_override("font_size", 24)
	root.add_child(title)

	var hint := Label.new()
	hint.text = "Выберите юнита, затем гекс. Выбранный маркер перемещается кликом."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(hint)

	_palette_search = LineEdit.new()
	_palette_search.placeholder_text = "Поиск по палитре"
	_palette_search.text_changed.connect(_on_palette_search_changed)
	root.add_child(_palette_search)

	_palette = ItemList.new()
	_palette.custom_minimum_size = Vector2(0, 130)
	_palette.item_selected.connect(_on_palette_selected)
	root.add_child(_palette)

	_side_option = OptionButton.new()
	_side_option.item_selected.connect(_on_side_changed)
	root.add_child(_labeled("Сторона", _side_option))

	_ai_option = OptionButton.new()
	_ai_option.item_selected.connect(_on_ai_override_changed)
	root.add_child(_labeled("AI override", _ai_option))

	var placement_actions := HBoxContainer.new()
	placement_actions.add_child(_button("Дублировать", _duplicate_selected))
	placement_actions.add_child(_button("Удалить", _delete_selected))
	root.add_child(placement_actions)

	var coords := HBoxContainer.new()
	_q_spin = SpinBox.new()
	_q_spin.min_value = -99
	_q_spin.max_value = 99
	_r_spin = SpinBox.new()
	_r_spin.min_value = -99
	_r_spin.max_value = 99
	coords.add_child(_labeled("q", _q_spin))
	coords.add_child(_labeled("r", _r_spin))
	root.add_child(coords)

	var map_actions := HBoxContainer.new()
	map_actions.add_child(_button("Добавить гекс", _add_hex))
	map_actions.add_child(_button("Удалить гекс", _remove_hex))
	root.add_child(map_actions)

	var history_actions := HBoxContainer.new()
	history_actions.add_child(_button("Отменить", _undo))
	history_actions.add_child(_button("Повторить", _redo))
	root.add_child(history_actions)

	var file_actions := HBoxContainer.new()
	file_actions.add_child(_button("Сохранить", _save))
	file_actions.add_child(_button("Открыть", _open))
	file_actions.add_child(_button("Экспорт", _export))
	file_actions.add_child(_button("Проверить", _validate_document))
	root.add_child(file_actions)
	root.add_child(_button("Пробный бой", _start_trial))

	_diagnostics = ItemList.new()
	_diagnostics.custom_minimum_size = Vector2(0, 150)
	root.add_child(_diagnostics)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)


func _labeled(text: String, control: Control) -> Control:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = text
	box.add_child(label)
	box.add_child(control)
	return box


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	return button


func _populate_palette(filter_text: String = "") -> void:
	_palette.clear()

	var filter := filter_text.strip_edges().to_lower()

	for definition: UnitDefinition in _snapshot.get_all_unit_definitions():
		var searchable := "%s %s" % [definition.display_name, definition.id]

		if not filter.is_empty() and not searchable.to_lower().contains(filter):
			continue

		var index := _palette.add_item(
			"%s  [%s]" % [definition.display_name, definition.id]
		)
		_palette.set_item_metadata(index, definition.id)


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
	_set_status("Выбран юнит %s." % _selected_definition_id)


func _on_placement_selected(placement_id: StringName) -> void:
	_selected_placement_id = placement_id
	_selected_definition_id = StringName()
	_view.select_placement(placement_id)
	var placement := _find_placement(placement_id)

	if placement == null:
		return

	_select_option_by_metadata(_side_option, placement.side_id)
	_select_option_by_metadata(_ai_option, placement.ai_profile_override_id)
	_set_status("Выбрано размещение %s." % placement_id)


func _on_hex_selected(hex: Vector2i) -> void:
	if not _selected_placement_id.is_empty():
		_execute(EditCommand.move_placement(_selected_placement_id, hex))
		return

	if _selected_definition_id.is_empty() or _side_option.item_count == 0:
		_set_status("Сначала выберите юнита из палитры.")
		return

	var placement := UnitPlacementDefinition.new()
	placement.placement_id = StringName("author:placement_%s" % _next_placement_number)
	_next_placement_number += 1
	placement.definition_id = _selected_definition_id
	placement.side_id = _side_option.get_selected_metadata()
	placement.start_hex = hex
	placement.ai_profile_override_id = _ai_option.get_selected_metadata()
	_selected_placement_id = placement.placement_id
	_selected_definition_id = StringName()
	_execute(EditCommand.add_placement(placement))
	_view.select_placement(_selected_placement_id)


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
		return

	var new_id := StringName("author:placement_%s" % _next_placement_number)
	_next_placement_number += 1
	_selected_placement_id = new_id
	_execute(EditCommand.duplicate_placement(
		placement.placement_id,
		new_id,
		placement.start_hex + Vector2i(1, 0)
	))
	_view.select_placement(new_id)


func _delete_selected() -> void:
	if _selected_placement_id.is_empty():
		return

	_execute(EditCommand.remove_placement(_selected_placement_id))
	_selected_placement_id = StringName()
	_view.select_placement(StringName())


func _add_hex() -> void:
	_execute(EditCommand.add_hex(_selected_coordinate()))


func _remove_hex() -> void:
	_execute(EditCommand.remove_hex(_selected_coordinate()))


func _selected_coordinate() -> Vector2i:
	return Vector2i(int(_q_spin.value), int(_r_spin.value))


func _execute(command: EditCommand) -> void:
	if not _history.execute(command, _document):
		_set_status("Команда не применена.")
		return

	_after_document_changed()


func _undo() -> void:
	if _history.undo(_document):
		_after_document_changed()


func _redo() -> void:
	if _history.redo(_document):
		_after_document_changed()


func _after_document_changed() -> void:
	_view.setup(_document)
	_validate_document()


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
		_set_status("Черновик сохранится, но запуск заблокирован: ошибок %s." % validation.errors.size())


func _save() -> void:
	var error := EditorDocumentSerializer.save(_document, DEFAULT_DRAFT_PATH)
	_set_status("Сохранено: %s" % DEFAULT_DRAFT_PATH if error.is_empty() else error)


func _open() -> void:
	var loaded := EditorDocumentSerializer.load(DEFAULT_DRAFT_PATH)

	if loaded == null:
		_set_status("Не удалось открыть %s." % DEFAULT_DRAFT_PATH)
		return

	_document = loaded
	_history = EditorCommandHistory.new()
	_selected_placement_id = StringName()
	_view.setup(_document)
	_populate_side_options()
	_validate_document()
	_set_status("Открыт %s." % DEFAULT_DRAFT_PATH)


func _export() -> void:
	var path := "user://exported_battle_package"
	var error := EditorPackageExporter.export(_document, path)
	_set_status("Экспортировано: %s" % path if error.is_empty() else error)


func _start_trial() -> void:
	var request := _document.create_trial_request(_snapshot, trial_seed)

	if request == null:
		_validate_document()
		_set_status("Пробный запуск заблокирован ошибками документа.")
		return

	_trial_screen = BATTLE_SCREEN_SCENE.instantiate() as BattleScreen

	if not _trial_screen.setup(request):
		_trial_screen.free()
		_trial_screen = null
		_set_status("BattleScreen отклонил пробный запуск.")
		return

	_trial_screen.battle_finished.connect(_on_trial_finished)
	_ui.visible = false
	_view.visible = false
	add_child(_trial_screen)


func _on_trial_finished(_result: BattleResult) -> void:
	_trial_screen.queue_free()
	_trial_screen = null
	_ui.visible = true
	_view.visible = true
	_set_status("Пробный бой завершён; EditorDocument не изменён.")


func _find_placement(placement_id: StringName) -> UnitPlacementDefinition:
	if placement_id.is_empty():
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