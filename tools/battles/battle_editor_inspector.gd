class_name BattleEditorInspector
extends TabContainer
## Right panel of the battle editor: inspector, field and checks pages.
## Builds and shows controls only; the shell connects them to the document workflow.

enum Page { INSPECTOR, FIELD, CHECKS }

const WIDTH := 400.0
const DIRECTIONS := ["Вправо", "Вверх вправо", "Вверх влево", "Влево", "Вниз влево", "Вниз вправо"]
const HEX_TOOLS := [
	EditorBattleView.Tool.ADD_HEX, EditorBattleView.Tool.REMOVE_HEX,
	EditorBattleView.Tool.PAINT_TERRAIN, EditorBattleView.Tool.PAINT_COST,
]

var tool_title: Label
var tool_help: Label
var selection_hint: Label
var states_card: VBoxContainer
var state_palette: EditorStatePalette
var unit_card: VBoxContainer
var unit_card_title: Label
var selected_unit_label: Label
var palette_box: VBoxContainer
var palette_search: LineEdit
var palette: ItemList
var unit_editor_button: Button
var reload_button: Button
var side_option: OptionButton
var ai_option: OptionButton
var placement_actions: HBoxContainer
var duplicate_button: Button
var delete_button: Button
var roster_card: VBoxContainer
var roster: ItemList
var hex_card: VBoxContainer
var selected_hex_label: Label
var terrain_id_edit: LineEdit
var movement_cost_spin: SpinBox
var traversable_check: CheckButton
var hex_apply_button: Button
var hex_coordinates: VBoxContainer
var q_spin: SpinBox
var r_spin: SpinBox
var add_hex_button: Button
var remove_hex_button: Button
var obstacle_card: VBoxContainer
var obstacle_type: OptionButton
var obstacle_size: SpinBox
var obstacle_direction: OptionButton
var obstacle_destructible: CheckButton
var obstacle_hp: SpinBox
var obstacle_apply_button: Button
var obstacle_remove_button: Button
var document_path_label: Label
var open_button: Button
var save_as_button: Button
var new_button: Button
var export_button: Button
var use_in_game_buttons: Array[Button] = []
var background_option: OptionButton
var grid_layout_controls: EditorGridLayoutControls
var validation_summary: Label
var diagnostics: ItemList
var check_button: Button
var trial_button: Button


func _init() -> void:
	custom_minimum_size.x = WIDTH
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_inspector_page(_page("Inspector", "Инспектор"))
	_build_field_page(_page("Field", "Поле"))
	_build_checks_page(_page("Checks", "Проверка"))


## Shows only the cards that the active tool and the current selection can use.
func show_context(tool: EditorBattleView.Tool, placement_caption: String, unit_type: String, has_hex: bool, has_obstacle: bool) -> void:
	var selecting := tool == EditorBattleView.Tool.SELECT
	var placing := tool == EditorBattleView.Tool.PLACE_UNIT
	var has_placement := not placement_caption.is_empty()
	tool_title.text = "ИНСТРУМЕНТ: %s" % EditorToolBar.caption(tool).to_upper()
	tool_help.text = EditorToolBar.help(tool)
	selection_hint.visible = selecting and not has_placement and not has_hex
	EditorUi.set_card_visible(states_card, tool in [EditorBattleView.Tool.PAINT_STATE, EditorBattleView.Tool.ERASE_STATE])
	EditorUi.set_card_visible(unit_card, placing or (selecting and has_placement))
	palette_box.visible = placing
	placement_actions.visible = has_placement
	unit_card_title.text = "ВЫБРАННЫЙ ЮНИТ" if has_placement else "НОВЫЙ ЮНИТ"
	if has_placement:
		var move_hint := "\nЩелчок по свободному гексу переместит юнита. Выберите тип в списке, чтобы ставить новых."
		selected_unit_label.text = placement_caption + (move_hint if placing else "")
	elif not unit_type.is_empty():
		selected_unit_label.text = "Тип: %s. Щёлкните по свободному гексу." % unit_type
	else:
		selected_unit_label.text = "Выберите тип юнита в списке, затем щёлкните по свободному гексу."
	EditorUi.set_card_visible(hex_card, tool in HEX_TOOLS or (selecting and has_hex))
	hex_apply_button.visible = selecting and has_hex
	traversable_check.visible = selecting or tool == EditorBattleView.Tool.ADD_HEX
	hex_coordinates.visible = tool in [EditorBattleView.Tool.ADD_HEX, EditorBattleView.Tool.REMOVE_HEX]
	EditorUi.set_card_visible(obstacle_card, tool == EditorBattleView.Tool.PAINT_OBSTACLE or (selecting and has_obstacle))
	obstacle_remove_button.visible = has_obstacle
	EditorUi.set_card_visible(roster_card, selecting or placing)


## Lists document diagnostics; the tab title carries the error count.
func show_validation(errors: Array[String], warnings: Array[String]) -> void:
	diagnostics.clear()
	for error: String in errors:
		_add_diagnostic("✗ %s" % error, EditorUi.ERROR)
	for warning: String in warnings:
		_add_diagnostic("⚠ %s" % warning, EditorUi.WARN)
	diagnostics.visible = diagnostics.item_count > 0
	set_tab_title(Page.CHECKS, "Проверка (%d)" % errors.size() if not errors.is_empty() else "Проверка")
	if errors.is_empty():
		EditorUi.set_status(validation_summary, "Документ готов к сохранению, экспорту и пробному запуску.", EditorUi.Severity.OK)
	else:
		EditorUi.set_status(validation_summary, "Черновик можно сохранить, но запуск заблокирован: ошибок %d." % errors.size(), EditorUi.Severity.ERROR)


func show_load_errors(errors: Array[String]) -> void:
	for error: String in errors:
		_add_diagnostic("✗ %s" % error, EditorUi.ERROR)
	diagnostics.visible = true
	current_tab = Page.CHECKS


func _add_diagnostic(text: String, color: Color) -> void:
	var index := diagnostics.add_item(text)
	diagnostics.set_item_custom_fg_color(index, color)


func _page(node_name: String, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = node_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	set_tab_title(get_tab_count() - 1, title)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	scroll.add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	margin.add_child(page)
	return page


func _build_inspector_page(page: VBoxContainer) -> void:
	var tool := EditorUi.card(page)
	tool_title = EditorUi.label("", &"SectionLabel")
	tool.add_child(tool_title)
	tool_help = EditorUi.hint("")
	tool.add_child(tool_help)
	selection_hint = EditorUi.label("Ничего не выбрано. Щёлкните по гексу или юниту на поле.", &"FieldLabel", true)
	tool.add_child(selection_hint)
	tool.add_child(EditorUi.hint("СКМ — панорама · Ctrl+Z/Ctrl+Y — отмена/повтор · Esc — снять выбор"))
	states_card = EditorUi.card(page, "СОСТОЯНИЯ ГЕКСОВ")
	state_palette = EditorStatePalette.new()
	states_card.add_child(state_palette)
	_build_unit_card(page)
	_build_hex_card(page)
	_build_obstacle_card(page)
	roster_card = EditorUi.card(page, "РАССТАВЛЕННЫЕ ЮНИТЫ")
	roster = ItemList.new()
	# Typed letters belong to the tool shortcuts, not to incremental list search.
	roster.allow_search = false
	roster.custom_minimum_size.y = 200
	roster.fixed_icon_size = Vector2i(32, 32)
	roster_card.add_child(roster)


func _build_unit_card(page: VBoxContainer) -> void:
	unit_card = EditorUi.card(page)
	unit_card_title = EditorUi.label("", &"SectionLabel")
	unit_card.add_child(unit_card_title)
	selected_unit_label = EditorUi.label("", &"FieldLabel", true)
	unit_card.add_child(selected_unit_label)
	palette_box = VBoxContainer.new()
	palette_box.add_theme_constant_override("separation", 8)
	unit_card.add_child(palette_box)
	palette_search = LineEdit.new()
	palette_search.placeholder_text = "Поиск юнита по имени или ID"
	palette_search.clear_button_enabled = true
	palette_box.add_child(palette_search)
	palette = ItemList.new()
	palette.allow_search = false
	palette.custom_minimum_size = Vector2(0, 260)
	palette.fixed_icon_size = Vector2i(40, 40)
	palette_box.add_child(palette)
	unit_editor_button = _wide(EditorUi.button("Редактор юнитов", Callable()))
	reload_button = _wide(EditorUi.button("Перечитать", Callable(), "Перечитать библиотеку юнитов после правок в другом окне"))
	palette_box.add_child(_row([unit_editor_button, reload_button]))
	var form := EditorUi.form(unit_card)
	side_option = _option()
	EditorUi.row(form, "Сторона", side_option, "Сторона новой фигуры либо выбранного юнита.")
	ai_option = _option()
	EditorUi.row(form, "Профиль ИИ", ai_option, "Для стороны под управлением ИИ: общий профиль стороны или переопределение.")
	duplicate_button = _wide(EditorUi.button("Дублировать", Callable(), "Копия на ближайшем свободном гексе"))
	EditorUi.add_shortcut(duplicate_button, KEY_D, true)
	delete_button = _wide(EditorUi.button("Удалить юнита", Callable()))
	EditorUi.add_shortcut(delete_button, KEY_DELETE)
	placement_actions = _row([duplicate_button, delete_button])
	unit_card.add_child(placement_actions)


func _build_hex_card(page: VBoxContainer) -> void:
	hex_card = EditorUi.card(page, "ГЕКС И КИСТЬ МЕСТНОСТИ")
	selected_hex_label = EditorUi.label("Гекс не выбран", &"FieldLabel")
	hex_card.add_child(selected_hex_label)
	var form := EditorUi.form(hex_card)
	terrain_id_edit = LineEdit.new()
	terrain_id_edit.text = "core:default"
	terrain_id_edit.placeholder_text = "core:default"
	EditorUi.row(form, "Поверхность", terrain_id_edit, "ID поверхности клетки для кисти и выбранного гекса.")
	movement_cost_spin = EditorUi.spin(1, 99)
	movement_cost_spin.value = 1
	EditorUi.row(form, "Стоимость хода", movement_cost_spin, "Очки передвижения за вход в клетку. Клетка с состоянием берёт стоимость состояния.")
	traversable_check = CheckButton.new()
	traversable_check.text = "Проходимый"
	traversable_check.button_pressed = true
	hex_card.add_child(traversable_check)
	hex_apply_button = EditorUi.button("Применить к выбранному гексу", Callable())
	hex_card.add_child(hex_apply_button)
	hex_coordinates = VBoxContainer.new()
	hex_card.add_child(hex_coordinates)
	var coords := EditorUi.form(hex_coordinates, 4)
	q_spin = EditorUi.spin(-999, 999)
	r_spin = EditorUi.spin(-999, 999)
	EditorUi.row(coords, "q", q_spin)
	EditorUi.row(coords, "r", r_spin)
	add_hex_button = _wide(EditorUi.button("Добавить по q,r", Callable()))
	remove_hex_button = _wide(EditorUi.button("Удалить по q,r", Callable()))
	hex_coordinates.add_child(_row([add_hex_button, remove_hex_button]))


func _build_obstacle_card(page: VBoxContainer) -> void:
	obstacle_card = EditorUi.card(page, "ПРЕПЯТСТВИЕ")
	var form := EditorUi.form(obstacle_card)
	obstacle_type = _option()
	for label: String in BattleObstacleDefinition.NAMES:
		obstacle_type.add_item(label)
	EditorUi.row(form, "Местность", obstacle_type)
	obstacle_size = EditorUi.spin(1, 4)
	obstacle_size.value = 1
	EditorUi.row(form, "Гексов подряд", obstacle_size, "1–4 соседних гекса по прямой с общими HP.")
	obstacle_direction = _option()
	for label: String in DIRECTIONS:
		obstacle_direction.add_item(label)
	EditorUi.row(form, "Направление", obstacle_direction, "Направление от начального гекса.")
	obstacle_destructible = CheckButton.new()
	obstacle_destructible.text = "Уничтожаемое"
	obstacle_card.add_child(obstacle_destructible)
	obstacle_hp = EditorUi.spin(1, 1000000)
	obstacle_hp.value = 10
	obstacle_hp.editable = false
	obstacle_destructible.toggled.connect(func(value: bool) -> void: obstacle_hp.editable = value)
	EditorUi.row(EditorUi.form(obstacle_card), "HP всего препятствия", obstacle_hp)
	obstacle_apply_button = EditorUi.button("Поставить / обновить на выбранном гексе", Callable())
	obstacle_card.add_child(obstacle_apply_button)
	obstacle_remove_button = EditorUi.button("Удалить выбранное препятствие", Callable())
	EditorUi.add_shortcut(obstacle_remove_button, KEY_DELETE)
	obstacle_card.add_child(obstacle_remove_button)


func _build_field_page(page: VBoxContainer) -> void:
	var document := EditorUi.card(page, "ДОКУМЕНТ")
	document_path_label = EditorUi.hint("Файл: не сохранён")
	document.add_child(document_path_label)
	var file_actions := GridContainer.new()
	file_actions.columns = 2
	document.add_child(file_actions)
	open_button = _wide(EditorUi.button("Открыть…", Callable()))
	save_as_button = _wide(EditorUi.button("Сохранить как…", Callable()))
	new_button = _wide(EditorUi.button("Новое поле", Callable()))
	export_button = _wide(EditorUi.button("Экспорт копии", Callable()))
	for button: Button in [open_button, save_as_button, new_button, export_button]:
		file_actions.add_child(button)
	document.add_child(_use_in_game_button("Сохранить, проверить и назначить поле для обычного запуска игры (F5 в Godot)"))
	var backdrop := EditorUi.card(page, "ФОН")
	background_option = _option()
	for id: StringName in BattleBackdrops.NAMES:
		background_option.add_item(BattleBackdrops.NAMES[id])
		background_option.set_item_metadata(background_option.item_count - 1, id)
	backdrop.add_child(background_option)
	backdrop.add_child(EditorUi.hint("Фон — только подложка. Клетки и препятствия задаются картой."))
	grid_layout_controls = EditorGridLayoutControls.new()
	EditorUi.card(page, "СЕТКА").add_child(grid_layout_controls)
	EditorUi.card(page, "ОКНО РЕДАКТОРА").add_child(EditorDisplaySettings.new())


func _build_checks_page(page: VBoxContainer) -> void:
	var checks := EditorUi.card(page, "ПРОВЕРКА ДОКУМЕНТА")
	validation_summary = EditorUi.label("", &"FieldLabel", true)
	checks.add_child(validation_summary)
	diagnostics = ItemList.new()
	diagnostics.auto_height = true
	diagnostics.custom_minimum_size.y = 120
	checks.add_child(diagnostics)
	check_button = _wide(EditorUi.button("Проверить", Callable()))
	trial_button = _wide(EditorUi.button("▶ Пробный бой", Callable(), "", &"PrimaryButton"))
	checks.add_child(_row([check_button, trial_button]))
	checks.add_child(_use_in_game_button(""))
	checks.add_child(EditorUi.hint("Черновик с ошибками можно сохранить, но пробный бой и назначение стартовым блокируются."))


func _use_in_game_button(tooltip: String) -> Button:
	var button := EditorUi.button("Сделать стартовым боем", Callable(), tooltip)
	use_in_game_buttons.append(button)
	return button


func _option() -> OptionButton:
	var option := OptionButton.new()
	# Long item names must not widen the panel and shift the map when tabs switch.
	option.fit_to_longest_item = false
	return option


func _wide(button: Button) -> Button:
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button


func _row(controls: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	for control: Control in controls:
		row.add_child(control)
	return row
