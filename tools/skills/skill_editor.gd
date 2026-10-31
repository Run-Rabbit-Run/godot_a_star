class_name SkillEditor
extends Control
## Edits existing active and passive skills: numbers, damage and status choices, name and description. The JSON draft is the source of truth.

signal closed

const HISTORY_LIMIT := 100
const KIND_TITLES := {"active": "Активные", "passive": "Пассивные"}
const TARGET_MODES := {0: "автоматически", 1: "противник", 2: "гекс", 3: "пустой гекс", 4: "линия", 5: "путь", 6: "свой гекс"}
const TARGET_HELP := {
	0: "При радиусе больше 0 выбирается гекс в пределах дальности, иначе — противник в пределах дальности.",
	1: "Выбирается противник в пределах дальности; область считается вокруг него.",
	2: "Выбирается любой гекс в пределах дальности; область считается вокруг него.",
	3: "Выбирается свободный проходимый гекс в пределах дальности.",
	4: "Выбирается направление: луч проходит по всей прямой и не останавливается дырами и препятствиями.",
	5: "Поражается путь от юнита до выбранного гекса.",
	6: "Действует вокруг своего гекса: соседи в радиусе области, без самого юнита.",
}
const EFFECT_TITLES := {"core:damage": "УРОН", "core:unit_status": "СОСТОЯНИЕ ЮНИТА", "core:hex_state": "СОСТОЯНИЕ ГЕКСА", "core:summon": "ПРИЗЫВ"}
## Targets whose "other targets" damage applies even without an area radius.
const SPREADING_TARGETS := [AbilityDefinition.TargetMode.LINE, AbilityDefinition.TargetMode.PATH, AbilityDefinition.TargetMode.SELF]
## Consecutive edits of these keys share one undo step (typing).
const TYPED_KEYS := ["name", "description"]

var embedded := false
var _document: Dictionary = {}
var _saved: Dictionary = {}
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _kind := "active"
## Built-in documents merged with project overrides. The disk is read on open, refresh and save only.
var _catalog: Dictionary = {}
var _builtin: Dictionary = {}
var _authored: Dictionary = {}
var _list: ItemList
var _search: LineEdit
var _library_count: Label
var _category: TabBar
var _scroll: ScrollContainer
var _form: VBoxContainer
var _description: TextEdit
var _variables: MenuButton
var _preview: Label
var _preview_context: VBoxContainer
var _preview_attack: SpinBox
var _preview_range: SpinBox
var _help: Label
var _reset: Button
## Controls enabled by the current draft: [control, Callable() -> bool].
var _conditions: Array = []
var _dirty: Label
var _status: Label
var _validation: Label
var _confirm: ConfirmationDialog
var _pending: Callable
var _sync := false
var _last_change := ""
var _previous_auto_accept := true


func _ready() -> void:
	_build_ui()
	_previous_auto_accept = get_tree().auto_accept_quit
	get_tree().auto_accept_quit = false
	_reload_catalog()
	_open_first()


func _exit_tree() -> void:
	get_tree().auto_accept_quit = _previous_auto_accept


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not embedded:
		request_close(func() -> void: get_tree().quit())


func request_close(action: Callable) -> void:
	_request(action)


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	EditorUi.apply(self)
	var root := EditorUi.background(self)
	_build_header(root)
	var margin := MarginContainer.new()
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	root.add_child(margin)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	margin.add_child(body)
	_build_library(body)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)
	_form = VBoxContainer.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form.add_theme_constant_override("separation", 14)
	_scroll.add_child(_form)
	_build_side(body)
	var footer := EditorUi.bar(root, &"EditorStatusBar")
	_status = EditorUi.label("")
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	footer.add_child(_status)
	_validation = EditorUi.label("")
	_validation.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_validation.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_validation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_validation.size_flags_stretch_ratio = 0.8
	_validation.mouse_filter = Control.MOUSE_FILTER_PASS
	footer.add_child(_validation)
	_confirm = EditorUi.confirm_discard(self, "Отбросить несохранённые изменения умения?", func() -> void: _pending.call())


func _build_header(root: Control) -> void:
	var header := EditorUi.bar(root)
	header.add_child(EditorUi.label("Навыки", &"TitleLabel"))
	_dirty = EditorUi.label("")
	header.add_child(_dirty)
	header.add_child(EditorUi.spacer())
	var undo := EditorUi.button("Отменить", _undo_edit)
	EditorUi.add_shortcut(undo, KEY_Z, true)
	header.add_child(undo)
	var redo := EditorUi.button("Повторить", _redo_edit)
	EditorUi.add_shortcut(redo, KEY_Y, true)
	EditorUi.add_shortcut(redo, KEY_Z, true, true)
	header.add_child(redo)
	header.add_child(EditorUi.separator())
	_reset = EditorUi.button("Исходные значения", _reset_to_builtin, "Вернуть значения встроенного умения. После сохранения переопределение удаляется.")
	header.add_child(_reset)
	header.add_child(EditorUi.separator())
	header.add_child(EditorUi.button("Папка данных", _open_folder, "Открыть content/authored/skills в проводнике"))
	var refresh := EditorUi.button("Обновить", _refresh, "Перечитать встроенные и авторские умения")
	EditorUi.add_shortcut(refresh, KEY_R, true)
	header.add_child(refresh)
	var save := EditorUi.button("Сохранить", _save, "", &"PrimaryButton")
	EditorUi.add_shortcut(save, KEY_S, true)
	header.add_child(save)
	header.add_child(EditorUi.button("Вернуться" if embedded else "Закрыть", func() -> void: _request(_leave)))


func _build_library(body: Control) -> void:
	var library := EditorUi.card(body, "БИБЛИОТЕКА")
	(library.get_parent() as Control).custom_minimum_size.x = 320
	_category = TabBar.new()
	_category.clip_tabs = false
	for kind: String in KIND_TITLES:
		_category.add_tab(KIND_TITLES[kind])
	_category.tab_changed.connect(_on_category_changed)
	library.add_child(_category)
	_search = LineEdit.new()
	_search.placeholder_text = "Поиск по имени или ID"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_text: String) -> void: _refresh_list())
	library.add_child(_search)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_select)
	library.add_child(_list)
	_library_count = EditorUi.hint("")
	library.add_child(_library_count)


func _build_side(body: Control) -> void:
	var side := EditorUi.card(body, "В ИГРЕ")
	(side.get_parent() as Control).custom_minimum_size.x = 360
	_preview = EditorUi.label("", &"", true)
	side.add_child(_preview)
	_preview_context = VBoxContainer.new()
	side.add_child(_preview_context)
	var grid := EditorUi.form(_preview_context)
	_preview_attack = EditorUi.spin(0, 9999)
	_preview_attack.value = 4
	_preview_attack.value_changed.connect(func(_value: float) -> void: _update_preview())
	EditorUi.row(grid, "Урон атаки юнита", _preview_attack)
	_preview_range = EditorUi.spin(1, 20)
	_preview_range.value = 3
	_preview_range.value_changed.connect(func(_value: float) -> void: _update_preview())
	EditorUi.row(grid, "Дальность атаки юнита", _preview_range)
	_preview_context.add_child(EditorUi.hint("Значения для примера. В бою подставляются урон и дальность атаки действующего юнита с пассивными бонусами."))
	side.add_child(HSeparator.new())
	side.add_child(EditorUi.label("ПРАВИЛА", &"SectionLabel"))
	var help_scroll := ScrollContainer.new()
	help_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	help_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(help_scroll)
	_help = EditorUi.label("", &"FieldLabel", true)
	help_scroll.add_child(_help)


func _on_category_changed(index: int) -> void:
	var next: String = KIND_TITLES.keys()[index]
	if next == _kind:
		return
	# The tab follows the open draft until a replacement is confirmed.
	_select_category_tab()
	_request(func() -> void:
		_kind = next
		_open_first()
	)


func _select_category_tab() -> void:
	_category.set_block_signals(true)
	_category.current_tab = KIND_TITLES.keys().find(_kind)
	_category.set_block_signals(false)


func _number(grid: GridContainer, title: String, data: Dictionary, key: String, minimum: int, maximum: int, action: Callable, tooltip := "") -> SpinBox:
	var spin := EditorUi.spin(minimum, maximum)
	spin.value = data.get(key, minimum)
	spin.value_changed.connect(func(value: float) -> void: action.call(key, int(value)))
	EditorUi.row(grid, title, spin, tooltip)
	return spin


func _choice(grid: GridContainer, title: String, data: Dictionary, key: String, values: Dictionary, action: Callable, tooltip := "") -> OptionButton:
	var option := OptionButton.new()
	option.fit_to_longest_item = false
	for value: Variant in values:
		option.add_item(values[value])
		option.set_item_metadata(option.item_count - 1, value)
		if str(data.get(key, "")) == str(value):
			option.select(option.item_count - 1)
	option.item_selected.connect(func(index: int) -> void: action.call(key, option.get_item_metadata(index)))
	EditorUi.row(grid, title, option, tooltip)
	return option


func _check(parent: Control, title: String, data: Dictionary, key: String, action: Callable, tooltip := "") -> CheckBox:
	var box := CheckBox.new()
	box.text = title
	box.tooltip_text = tooltip
	box.button_pressed = data.get(key, false)
	box.toggled.connect(func(value: bool) -> void: action.call(key, value))
	parent.add_child(box)
	return box


## The control stays editable only while the predicate accepts the current draft.
func _enable_when(control: Control, predicate: Callable) -> void:
	_conditions.append([control, predicate])


func _apply_conditions() -> void:
	for entry: Array in _conditions:
		var control: Control = entry[0]
		var enabled: bool = (entry[1] as Callable).call()
		if control is SpinBox:
			(control as SpinBox).editable = enabled
		elif control is BaseButton:
			(control as BaseButton).disabled = not enabled


func _reload_catalog() -> void:
	_builtin = SkillLibrary.builtin_documents()
	var authored := SkillLibrary.read_all()
	_authored = authored.documents
	_catalog = _builtin.duplicate(true)
	_catalog.merge(_authored, true)
	if not authored.errors.is_empty():
		EditorUi.set_status(_status, "Ошибки файлов навыков: " + " · ".join(authored.errors), EditorUi.Severity.ERROR)


func _entries(kind: String, filter := "") -> Array:
	var entries: Array = _catalog.values().filter(func(data: Dictionary) -> bool:
		return data.kind == kind and (filter.is_empty() or (String(data.name) + " " + String(data.id)).to_lower().contains(filter))
	)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	return entries


func _open_first() -> void:
	var entries := _entries(_kind)
	if entries.is_empty():
		EditorUi.set_status(_status, "В категории нет умений.", EditorUi.Severity.WARN)
		return
	_set_document(entries[0])


func _set_document(data: Dictionary, saved := true) -> void:
	_document = data.duplicate(true)
	_saved = data.duplicate(true) if saved else {}
	_kind = data.kind
	_undo.clear()
	_redo.clear()
	_last_change = ""
	_render()
	_refresh_list()


func _change(key: String, value: Variant) -> void:
	if _sync or _document.get(key) == value:
		return
	if not (key in TYPED_KEYS and _last_change == key and not _undo.is_empty() and _redo.is_empty()):
		_push_undo()
	_last_change = key
	_document[key] = value
	_update_status()


func _effect_change(index: int, key: String, value: Variant) -> void:
	var effects: Array = _document.effects.duplicate(true)
	effects[index].parameters[key] = value
	_change("effects", effects)


func _push_undo() -> void:
	_undo.append(_document.duplicate(true))
	if _undo.size() > HISTORY_LIMIT:
		_undo.pop_front()
	_redo.clear()


## The whole form is built only when another draft opens; single edits keep their controls.
func _render() -> void:
	var scroll := _scroll.scroll_vertical
	_sync = true
	for child: Node in _form.get_children():
		_form.remove_child(child)
		child.queue_free()
	_conditions.clear()
	_select_category_tab()
	_basics_form()
	if _kind == "active":
		_active_form()
	else:
		_passive_form()
	_preview_context.visible = _kind == "active" and _uses_unit_values()
	_sync = false
	_update_status()
	_scroll.set_deferred("scroll_vertical", scroll)


func _basics_form() -> void:
	var card := EditorUi.card(_form, "ОСНОВНОЕ")
	var grid := EditorUi.form(card)
	var name_field := LineEdit.new()
	name_field.text = _document.name
	name_field.max_length = 120
	name_field.text_changed.connect(func(value: String) -> void: _change("name", value))
	EditorUi.row(grid, "Название", name_field)
	_description = TextEdit.new()
	_description.text = String(_document.get("description", ""))
	_description.custom_minimum_size.y = 96
	_description.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_description.text_changed.connect(func() -> void: _change("description", _description.text))
	EditorUi.row(grid, "Описание", _description, "Текст подсказки в игре. Переменные в фигурных скобках подставляют итоговые значения.")
	_variables = MenuButton.new()
	_variables.text = "Вставить переменную ▾"
	_variables.flat = false
	var popup := _variables.get_popup()
	popup.about_to_popup.connect(_fill_variables)
	popup.id_pressed.connect(func(id: int) -> void: _insert_variable(String(popup.get_item_metadata(popup.get_item_index(id)))))
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	tools.add_child(_variables)
	tools.add_child(EditorUi.hint("Например: {damage} урона ({damage_type})." if _kind == "active" else "Например: накладывает {status} ×{levels}."))
	grid.add_child(Control.new())
	grid.add_child(tools)
	EditorUi.row(grid, "Источник", EditorUi.hint(_origin_text()))
	EditorUi.row(grid, "ID", EditorUi.label(String(_document.id), &"MutedLabel"))


func _origin_text() -> String:
	var id := String(_document.id)
	if not _builtin.has(id):
		return "Умение проекта: content/authored/skills/" + SkillLibrary.filename_for(_document)
	return "Встроенное умение. Сохранение создаёт переопределение в проекте, исходный ресурс не меняется." + (" Переопределение сохранено." if _authored.has(id) else "")


func _active_form() -> void:
	var card := EditorUi.card(_form, "ПАРАМЕТРЫ")
	var grid := EditorUi.form(card, 4)
	var range_spin := _number(grid, "Дальность", _document, "range", 1, 99, _change, "Гексы от юнита до цели.")
	_enable_when(range_spin, func() -> bool: return not _document.uses_attack_range)
	_number(grid, "Радиус области", _document, "area_radius", 0, 8, _change, "0 — только цель; 1 — цель и соседи.")
	_number(grid, "Перезарядка", _document, "cooldown_turns", 1, 99, _change, "1 запрещает умение на следующем собственном ходе.")
	_number(grid, "Начальная перезарядка", _document, "initial_cooldown_turns", 0, 99, _change, "1 делает умение доступным со второго собственного хода.")
	card.add_child(EditorUi.hint(_fixed_facts()))
	for index: int in range(_document.effects.size()):
		_effect_card(index)


func _fixed_facts() -> String:
	var facts := PackedStringArray(["Цель: %s." % TARGET_MODES.get(int(_document.target_mode), "?")])
	if _document.uses_attack_range:
		facts.append("Дальность — как у атаки юнита.")
	if _document.melee_attack:
		facts.append("Ближняя атака: вызывает ответный удар.")
	if _document.returns_next_turn:
		facts.append("Оружие возвращается в следующий ход.")
	facts.append("Цель, флаги и состав эффектов не меняются; каждое активное умение завершает ход.")
	return " ".join(facts)


func _effect_card(index: int) -> void:
	var effect: Dictionary = _document.effects[index]
	var params: Dictionary = effect.parameters
	var card := EditorUi.card(_form, "ЭФФЕКТ %d — %s" % [index + 1, EFFECT_TITLES.get(effect.type, effect.type)])
	var grid := EditorUi.form(card, 4)
	var change := func(key: String, value: Variant) -> void: _effect_change(index, key, value)
	match effect.type:
		"core:damage":
			var values := {"amount": params.get("amount", 1), "secondary_amount": params.get("secondary_amount", params.get("amount", 1)), "damage_type": params.get("damage_type", "physical")}
			var fixed := func() -> bool: return not _document.effects[index].parameters.get("use_base_attack", false)
			_enable_when(_number(grid, "Урон цели", values, "amount", 1, 9999, change), fixed)
			_enable_when(_number(grid, "Урон остальным", values, "secondary_amount", 1, 9999, change, "Остальные цели области, линии или пути."), func() -> bool:
				return fixed.call() and (int(_document.area_radius) > 0 or int(_document.target_mode) in SPREADING_TARGETS)
			)
			_choice(grid, "Тип урона", values, "damage_type", SkillLibrary.DAMAGE_TYPES, change)
			_check(card, "Урон атаки юнита вместо чисел", params, "use_base_attack", change, "Берётся урон обычной атаки юнита с пассивными бонусами.")
			if not params.get("affects_obstacles", true):
				card.add_child(EditorUi.hint("Препятствия не повреждаются."))
		"core:unit_status":
			var statuses := _status_choices()
			statuses.erase("")
			_choice(grid, "Состояние", params, "status_id", statuses, change)
			_number(grid, "Уровней", params, "levels", 1, 9999, change)
		"core:hex_state":
			var states := {}
			for id: StringName in HexStateCatalog.RULES:
				states[String(id)] = HexStateCatalog.get_display_name(id)
			_choice(grid, "Состояние гекса", params, "state_id", states, change)
			card.add_child(EditorUi.hint("Живёт %d полных раунда. %s" % [HexStateCatalog.LIFETIME, "Создаётся только в центре области." if params.get("center_only", false) else "Создаётся на всех гексах области."]))
		"core:summon":
			card.add_child(EditorUi.hint(_summon_text(params)))


func _summon_text(params: Dictionary) -> String:
	var unit: UnitDefinition = SkillLibrary.units().get(StringName(String(params.get("unit_id", ""))))
	if unit == null:
		return "Призываемый юнит %s не найден." % params.get("unit_id", "")
	return "Призывает «%s»: ОЗ %d, атака %d на дальность %d. Призываемый юнит меняется в своих данных, не здесь." % [unit.display_name, unit.base_stats.max_health, unit.base_stats.basic_attack_damage, unit.base_stats.basic_attack_range]


func _passive_form() -> void:
	var attack := EditorUi.card(_form, "БАЗОВАЯ АТАКА")
	var grid := EditorUi.form(attack, 4)
	_number(grid, "Бонус урона", _document, "attack_bonus", 0, 9999, _change, "Добавляется к обычной атаке и умениям, использующим урон атаки.")
	var types := {"": "Не менять"}
	types.merge(SkillLibrary.DAMAGE_TYPES)
	_choice(grid, "Тип урона", _document, "damage_type", types, _change, "У юнита может быть только одно умение, меняющее тип урона атаки.")
	_choice(grid, "Накладываемое состояние", _document, "status", _status_choices(), _change, "Накладывается обычной атакой и ответным ударом.")
	var levels := _number(grid, "Уровней за удар", _document, "levels", 1, 99, _change)
	_enable_when(levels, func() -> bool: return not String(_document.status).is_empty())
	var defence := EditorUi.card(_form, "ЗАЩИТА")
	var defence_grid := EditorUi.form(defence, 4)
	_choice(defence_grid, "Невосприимчивость", _document, "immunity", _status_choices(), _change, "Состояние не накладывается на юнита.")
	defence.add_child(EditorUi.hint("Ответный удар в ближнем бою: %s. Это свойство не меняется в редакторе." % ("есть" if _document.retaliation else "нет")))
	defence.add_child(EditorUi.hint("Пассивные свойства подключаются при следующей загрузке библиотеки или боя."))


func _status_choices() -> Dictionary:
	var choices := {"": "Нет"}
	for id: StringName in UnitStatusCatalog.RULES:
		choices[String(id)] = UnitStatusCatalog.display_name(id)
	return choices


func _uses_unit_values() -> bool:
	return _document.get("uses_attack_range", false) or _document.get("effects", []).any(func(effect: Dictionary) -> bool:
		return effect.parameters.get("use_base_attack", false)
	)


func _context() -> Dictionary:
	return {"attack_damage": int(_preview_attack.value), "attack_range": int(_preview_range.value)}


func _variable_entries() -> Array[Dictionary]:
	if _kind == "active":
		return AbilityDescription.variables(SkillLibrary.to_ability(_document), _context())
	return AbilityDescription.passive_variables(_passive_definition())


func _passive_definition() -> Dictionary:
	return SkillLibrary.passive_definitions({_document.id: _document}).values()[0]


func _fill_variables() -> void:
	var popup := _variables.get_popup()
	popup.clear()
	var entries := _variable_entries()
	for index: int in range(entries.size()):
		popup.add_item("{%s} — %s: %s" % [entries[index].key, entries[index].label, entries[index].value], index)
		popup.set_item_metadata(popup.item_count - 1, entries[index].key)


func _insert_variable(key: String) -> void:
	_description.insert_text_at_caret("{%s}" % key)
	_change("description", _description.text)
	if _description.is_inside_tree():
		_description.grab_focus()


func _update_status() -> void:
	var id := String(_document.get("id", ""))
	EditorUi.set_dirty(_dirty, _document != _saved, _builtin.has(id) or _authored.has(id))
	var error := SkillLibrary.validate(_document)
	if error.is_empty():
		EditorUi.set_status(_validation, "✓ Данные корректны", EditorUi.Severity.OK)
	else:
		EditorUi.set_status(_validation, "✗ " + error, EditorUi.Severity.ERROR)
	_validation.tooltip_text = error
	_reset.disabled = not _builtin.has(id) or SkillLibrary.is_builtin_default(_document)
	_apply_conditions()
	_update_preview()
	_update_help()


func _update_preview() -> void:
	if _document.is_empty():
		return
	var text := AbilityDescription.render(SkillLibrary.to_ability(_document), _context()) if _kind == "active" else AbilityDescription.render_passive(_passive_definition())
	_preview.text = "%s\n\n%s" % [_document.name, text if not text.strip_edges().is_empty() else "Описание не задано: в игре видны только название и параметры."]


func _update_help() -> void:
	var lines: PackedStringArray = []
	if _kind == "active":
		var mode := int(_document.target_mode)
		lines.append("Цель — %s." % TARGET_MODES.get(mode, "?"))
		lines.append(TARGET_HELP.get(mode, ""))
		for index: int in range(_document.effects.size()):
			var effect: Dictionary = _document.effects[index]
			var text := _effect_description(effect)
			if not text.is_empty():
				lines.append("")
				lines.append("%d. %s" % [index + 1, text])
	else:
		for key: String in ["status", "immunity"]:
			var id := StringName(_document[key])
			if not id.is_empty():
				lines.append("%s — %s" % [UnitStatusCatalog.display_name(id), "накладывается ударом" if key == "status" else "невосприимчивость"])
				lines.append(UnitStatusCatalog.description(id))
				lines.append("")
		if lines.is_empty():
			lines.append("Выберите состояние или невосприимчивость, чтобы увидеть их правила.")
	_help.text = "\n".join(lines)


func _effect_description(effect: Dictionary) -> String:
	var params: Dictionary = effect.parameters
	match effect.type:
		"core:unit_status":
			return UnitStatusCatalog.description(StringName(params.get("status_id", "")))
		"core:hex_state":
			return HexStateCatalog.description(StringName(params.get("state_id", "")))
		"core:damage":
			return "Броня поглощает только физический урон. Влага и горение меняют огненный, водный и электрический урон по правилам состояний."
	return ""


## Rebuilds the library list from the cached catalog; never reads the disk.
func _refresh_list() -> void:
	_list.clear()
	var entries := _entries(_kind, _search.text.strip_edges().to_lower())
	for data: Dictionary in entries:
		var custom := not _builtin.has(data.id)
		var overridden := not custom and _authored.has(data.id)
		var index := _list.add_item(String(data.name) + (" [изменён]" if overridden else ""))
		_list.set_item_metadata(index, data.id)
		_list.set_item_tooltip(index, "%s\n%s" % [data.id, "Умение проекта" if custom else ("Встроенное, переопределено в проекте" if overridden else "Встроенное умение")])
		if custom:
			_list.set_item_custom_fg_color(index, EditorUi.INFO)
		elif overridden:
			_list.set_item_custom_fg_color(index, EditorUi.ACCENT)
	_mark_current()
	_library_count.text = "Показано: %d. Белые — встроенные, бирюзовые — умения проекта, [изменён] — встроенные с переопределением." % entries.size()


func _mark_current() -> void:
	_list.deselect_all()
	for index: int in range(_list.item_count):
		if _list.get_item_metadata(index) == _document.get("id"):
			_list.select(index)


func _select(index: int) -> void:
	var id: String = _list.get_item_metadata(index)
	# The selection follows the open draft until a replacement is confirmed.
	_mark_current()
	if id == _document.get("id"):
		return
	_request(func() -> void:
		_set_document(_catalog[id])
		EditorUi.set_status(_status, "Открыто: " + id)
	)


func _reset_to_builtin() -> void:
	var original: Dictionary = _builtin.get(String(_document.get("id", "")), {})
	if original.is_empty() or SkillLibrary.is_builtin_default(_document):
		return
	_push_undo()
	_last_change = ""
	_document = original.duplicate(true)
	_render()
	EditorUi.set_status(_status, "Подставлены встроенные значения. Сохраните, чтобы удалить переопределение.")


func _save() -> void:
	var error := SkillLibrary.save_document(_document)
	if not error.is_empty():
		EditorUi.set_status(_status, "Не сохранено: " + error, EditorUi.Severity.ERROR)
		return
	var restored := SkillLibrary.is_builtin_default(_document)
	_saved = _document.duplicate(true)
	_reload_catalog()
	_render()
	_refresh_list()
	if restored:
		EditorUi.set_status(_status, "Встроенные значения восстановлены, переопределение удалено.", EditorUi.Severity.OK)
	else:
		EditorUi.set_status(_status, "Сохранено: " + ProjectSettings.globalize_path(SkillLibrary.ROOT.path_join(SkillLibrary.filename_for(_document))), EditorUi.Severity.OK)


func _refresh() -> void:
	SkillLibrary.reload()
	_reload_catalog()
	var id := String(_document.get("id", ""))
	if _document == _saved and _catalog.has(id):
		_set_document(_catalog[id])
	else:
		_refresh_list()
		_update_status()
	EditorUi.set_status(_status, "Умения перечитаны с диска.")


func _undo_edit() -> void:
	if _undo.is_empty():
		EditorUi.set_status(_status, "Нечего отменять.")
		return
	_last_change = ""
	_redo.append(_document.duplicate(true))
	_document = _undo.pop_back()
	_render()


func _redo_edit() -> void:
	if _redo.is_empty():
		EditorUi.set_status(_status, "Нечего повторять.")
		return
	_last_change = ""
	_undo.append(_document.duplicate(true))
	_document = _redo.pop_back()
	_render()


func _request(action: Callable) -> void:
	if _document != _saved:
		_pending = action
		_confirm.popup_centered()
	else:
		action.call()


func _open_folder() -> void:
	var path := ProjectSettings.globalize_path(SkillLibrary.ROOT)
	DirAccess.make_dir_recursive_absolute(path)
	var error := OS.shell_open(path)
	if error != OK:
		EditorUi.set_status(_status, "Не удалось открыть папку: %s" % error_string(error), EditorUi.Severity.ERROR)


func _leave() -> void:
	if embedded:
		closed.emit()
		queue_free()
	else:
		get_tree().quit()
