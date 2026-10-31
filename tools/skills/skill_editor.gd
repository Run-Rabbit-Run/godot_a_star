class_name SkillEditor
extends Control
## Authoring form of active skills, passive skills and effect templates. The JSON draft is the source of truth.

signal closed

const HISTORY_LIMIT := 100
const KIND_TITLES := ["Активные", "Пассивные", "Эффекты"]
const TARGET_MODES := {0: "Автоматически", 1: "Противник", 2: "Гекс", 3: "Пустой гекс (призыв)", 4: "Линия", 5: "Путь", 6: "Свой гекс"}
const TARGET_HELP := {
	0: "При радиусе больше 0 выбирается гекс в пределах дальности, иначе — противник в пределах дальности.",
	1: "Выбирается противник в пределах дальности; область считается вокруг него.",
	2: "Выбирается любой гекс в пределах дальности; область считается вокруг него.",
	3: "Выбирается свободный проходимый гекс в пределах дальности. Нужен для призыва.",
	4: "Выбирается направление: луч проходит по всей прямой и не останавливается дырами и препятствиями.",
	5: "Поражается путь от юнита до выбранного гекса. Только этот режим с радиусом 0 допускает возврат оружия.",
	6: "Действует вокруг своего гекса: соседи в радиусе области, без самого юнита.",
}
const EFFECT_TYPES := {"core:damage": "Урон", "core:unit_status": "Состояние юнита", "core:hex_state": "Состояние гекса", "core:summon": "Призыв"}
const TEMPLATE_ID_OFFSET := 100

var embedded := false
var _document: Dictionary = {}
var _saved: Dictionary = {}
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _kind := "active"
var _effect_index := 0
var _authored: Dictionary = {}
## Presentation IDs read once per editor: listing packages reloads them.
var _presentations: Dictionary = {}
var _list: ItemList
var _search: LineEdit
var _library_count: Label
var _category: TabBar
var _scroll: ScrollContainer
var _form: VBoxContainer
var _effect_holder: VBoxContainer
var _effects_list: ItemList
var _effect_buttons: Dictionary[String, Button] = {}
## Controls enabled by the current draft: [control, Callable(document) -> bool].
var _conditions: Array = []
var _help: Label
var _dirty: Label
var _status: Label
var _validation: Label
var _confirm: ConfirmationDialog
var _pending: Callable
var _sync := false
## Consecutive edits of this key share one undo step (typing a name).
var _last_change := ""
var _previous_auto_accept := true


func _ready() -> void:
	_build_ui()
	_previous_auto_accept = get_tree().auto_accept_quit
	get_tree().auto_accept_quit = false
	_new_document()


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
	var help := EditorUi.card(body, "СПРАВКА")
	(help.get_parent() as Control).custom_minimum_size.x = 360
	var help_scroll := ScrollContainer.new()
	help_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	help_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	help.add_child(help_scroll)
	_help = EditorUi.label("", &"FieldLabel", true)
	help_scroll.add_child(_help)
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
	_confirm = EditorUi.confirm_discard(self, "Отбросить несохранённые изменения навыка или эффекта?", func() -> void: _pending.call())


func _build_header(root: Control) -> void:
	var header := EditorUi.bar(root)
	header.add_child(EditorUi.label("Навыки и эффекты", &"TitleLabel"))
	_dirty = EditorUi.label("")
	header.add_child(_dirty)
	header.add_child(EditorUi.spacer())
	var create := EditorUi.button("Новый", func() -> void: _request(_new_document), "Создать определение в текущей категории")
	EditorUi.add_shortcut(create, KEY_N, true)
	header.add_child(create)
	header.add_child(EditorUi.button("Копия", _copy, "Создать независимую копию с новым ID"))
	header.add_child(EditorUi.separator())
	var undo := EditorUi.button("Отменить", _undo_edit)
	EditorUi.add_shortcut(undo, KEY_Z, true)
	header.add_child(undo)
	var redo := EditorUi.button("Повторить", _redo_edit)
	EditorUi.add_shortcut(redo, KEY_Y, true)
	EditorUi.add_shortcut(redo, KEY_Z, true, true)
	header.add_child(redo)
	header.add_child(EditorUi.separator())
	header.add_child(EditorUi.button("Папка данных", _open_folder, "Открыть content/authored/skills в проводнике"))
	var refresh := EditorUi.button("Обновить", func() -> void:
		SkillLibrary.reload()
		_refresh_list()
		EditorUi.set_status(_status, "Библиотека навыков перечитана с диска.")
	, "Перечитать авторские навыки с диска")
	EditorUi.add_shortcut(refresh, KEY_R, true)
	header.add_child(refresh)
	var save := EditorUi.button("Сохранить", _save, "", &"PrimaryButton")
	EditorUi.add_shortcut(save, KEY_S, true)
	header.add_child(save)
	header.add_child(EditorUi.button("Вернуться" if embedded else "Закрыть", func() -> void: _request(_leave)))


func _build_library(body: Control) -> void:
	var library := EditorUi.card(body, "БИБЛИОТЕКА")
	(library.get_parent() as Control).custom_minimum_size.x = 360
	_category = TabBar.new()
	_category.clip_tabs = false
	for title: String in KIND_TITLES:
		_category.add_tab(title)
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


func _on_category_changed(index: int) -> void:
	var next: String = SkillLibrary.KINDS[index]
	if next == _kind:
		return
	# The tab follows the open draft until a replacement is confirmed.
	_select_category_tab()
	_request(func() -> void:
		_kind = next
		_new_document()
	)


func _select_category_tab() -> void:
	_category.set_block_signals(true)
	_category.current_tab = SkillLibrary.KINDS.find(_kind)
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
	_conditions = _conditions.filter(func(entry: Array) -> bool:
		return is_instance_valid(entry[0]) and not (entry[0] as Node).is_queued_for_deletion()
	)
	for entry: Array in _conditions:
		var control: Control = entry[0]
		var enabled: bool = (entry[1] as Callable).call()
		if control is SpinBox:
			(control as SpinBox).editable = enabled
		elif control is BaseButton:
			(control as BaseButton).disabled = not enabled


func _new_document() -> void:
	_set_document(SkillLibrary.new_document(_kind))
	EditorUi.set_status(_status, "Новое определение. Сохраните его, чтобы назначить юнитам.")


func _set_document(data: Dictionary, saved := true) -> void:
	_document = data.duplicate(true)
	_saved = data.duplicate(true) if saved else {}
	_kind = data.kind
	_effect_index = 0
	_undo.clear()
	_redo.clear()
	_last_change = ""
	_render()
	_refresh_list()


func _change(key: String, value: Variant) -> void:
	if _sync or _document.get(key) == value:
		return
	if not (key == "name" and _last_change == "name" and not _undo.is_empty() and _redo.is_empty()):
		_undo.append(_document.duplicate(true))
		if _undo.size() > HISTORY_LIMIT:
			_undo.pop_front()
		_redo.clear()
	_last_change = key
	_document[key] = value
	_update_status()


func _render() -> void:
	var scroll := _scroll.scroll_vertical
	_sync = true
	for child: Node in _form.get_children():
		_form.remove_child(child)
		child.queue_free()
	_conditions.clear()
	_effects_list = null
	_effect_holder = null
	_select_category_tab()
	var basics := EditorUi.form(EditorUi.card(_form, "ОСНОВНОЕ"))
	var name_field := LineEdit.new()
	name_field.text = _document.name
	name_field.max_length = 120
	name_field.text_changed.connect(func(value: String) -> void: _change("name", value))
	EditorUi.row(basics, "Название", name_field)
	EditorUi.row(basics, "ID", EditorUi.label(String(_document.id), &"MutedLabel"))
	EditorUi.row(basics, "Источник", EditorUi.hint(_origin_text()))
	match _kind:
		"active":
			_active_form()
		"passive":
			_passive_form()
		"effect":
			_effect_holder = VBoxContainer.new()
			_form.add_child(_effect_holder)
			_render_effect()
	_sync = false
	_update_status()
	_scroll.set_deferred("scroll_vertical", scroll)


func _origin_text() -> String:
	var id := String(_document.id)
	if not id.begins_with("custom_skills:"):
		return "Встроенное определение. Сохранение создаёт переопределение в проекте, исходный ресурс не меняется." + (" Переопределение уже сохранено." if _authored.has(id) else "")
	return "Определение проекта: content/authored/skills/" + SkillLibrary.filename_for(_document)


func _active_form() -> void:
	var usage := EditorUi.card(_form, "ПРИМЕНЕНИЕ")
	var grid := EditorUi.form(usage, 4)
	_choice(grid, "Цель", _document, "target_mode", TARGET_MODES, _change)
	var range_spin := _number(grid, "Дальность", _document, "range", 1, 99, _change, "Гексы от юнита до цели.")
	_enable_when(range_spin, func() -> bool: return not _document.uses_attack_range)
	_number(grid, "Радиус области", _document, "area_radius", 0, 8, _change, "0 — только цель; 1 — цель и соседи.")
	_number(grid, "Перезарядка", _document, "cooldown_turns", 1, 99, _change, "1 запрещает навык на следующем собственном ходе.")
	_number(grid, "Начальная перезарядка", _document, "initial_cooldown_turns", 0, 99, _change, "1 делает навык доступным со второго собственного хода.")
	if _presentations.is_empty():
		_presentations[""] = "Автоматическое"
		for package: ContentPackage in SkillLibrary.packages():
			for definition: AbilityPresentationDefinition in package.ability_presentations:
				_presentations[String(definition.id)] = String(definition.id)
	_choice(grid, "Отображение", _document, "presentation_id", _presentations, _change, "Анимация и VFX навыка в бою.")
	var flags := HFlowContainer.new()
	flags.add_theme_constant_override("h_separation", 18)
	usage.add_child(flags)
	_check(flags, "Дальность базовой атаки", _document, "uses_attack_range", _change, "Вместо поля «Дальность» используется дальность обычной атаки юнита.")
	_check(flags, "Ближняя атака (ответный удар)", _document, "melee_attack", _change, "Цель может ответить ударом ближнего боя.")
	_check(flags, "Возврат оружия в следующий ход", _document, "returns_next_turn", _change, "Только для цели «Путь», радиуса 0 и эффектов урона.")
	usage.add_child(EditorUi.hint("Каждый активный навык расходует основное действие и завершает ход."))

	var effects := EditorUi.card(_form, "ЭФФЕКТЫ — ВЫПОЛНЯЮТСЯ ПО ПОРЯДКУ")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	effects.add_child(row)
	_effects_list = ItemList.new()
	_effects_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_effects_list.custom_minimum_size.y = 150
	# Only the parameter card is rebuilt: the list must not be cleared inside its own signal.
	_effects_list.item_selected.connect(func(index: int) -> void:
		_effect_index = index
		_sync_effect_buttons()
		_render_effect()
	)
	row.add_child(_effects_list)
	var buttons := VBoxContainer.new()
	buttons.custom_minimum_size.x = 170
	row.add_child(buttons)
	buttons.add_child(_add_effect_menu())
	_effect_buttons["up"] = EditorUi.button("Выше", func() -> void: _move_effect(-1))
	_effect_buttons["down"] = EditorUi.button("Ниже", func() -> void: _move_effect(1))
	_effect_buttons["remove"] = EditorUi.button("Удалить", _remove_effect, "Навык должен содержать хотя бы один эффект.")
	for key: String in ["up", "down", "remove"]:
		buttons.add_child(_effect_buttons[key])
	_effect_holder = VBoxContainer.new()
	_form.add_child(_effect_holder)
	_fill_effects_list()
	_render_effect()


func _add_effect_menu() -> MenuButton:
	var menu := MenuButton.new()
	menu.text = "Добавить ▾"
	menu.flat = false
	var popup := menu.get_popup()
	var types := EFFECT_TYPES.keys()
	for index: int in range(types.size()):
		popup.add_item(EFFECT_TYPES[types[index]], index)
	var templates := SkillLibrary.names("effect")
	if not templates.is_empty():
		popup.add_separator("Из шаблона")
		var ids := templates.keys()
		for index: int in range(ids.size()):
			popup.add_item(templates[ids[index]], TEMPLATE_ID_OFFSET + index)
			popup.set_item_metadata(popup.item_count - 1, ids[index])
	popup.id_pressed.connect(func(id: int) -> void:
		var effect: Dictionary
		if id < TEMPLATE_ID_OFFSET:
			effect = SkillLibrary.new_effect(types[id])
		else:
			var template_id: String = popup.get_item_metadata(popup.get_item_index(id))
			var catalog := SkillLibrary.catalog()
			if not catalog.has(template_id):
				EditorUi.set_status(_status, "Шаблон %s больше не найден на диске." % template_id, EditorUi.Severity.ERROR)
				return
			effect = catalog[template_id].effect.duplicate(true)
		var effects: Array = _document.effects.duplicate(true)
		effects.append(effect)
		_change("effects", effects)
		_effect_index = effects.size() - 1
		_fill_effects_list()
		_render_effect()
	)
	return menu


func _fill_effects_list() -> void:
	if _effects_list == null:
		return
	_effects_list.clear()
	_effect_index = clampi(_effect_index, 0, maxi(0, _document.effects.size() - 1))
	for index: int in range(_document.effects.size()):
		_effects_list.add_item("%d. %s" % [index + 1, _effect_summary(_document.effects[index])])
	if not _document.effects.is_empty():
		_effects_list.select(_effect_index)
	_sync_effect_buttons()


func _sync_effect_buttons() -> void:
	_effect_buttons["up"].disabled = _effect_index <= 0
	_effect_buttons["down"].disabled = _effect_index >= _document.effects.size() - 1
	_effect_buttons["remove"].disabled = _document.effects.size() <= 1


func _render_effect() -> void:
	if _effect_holder == null:
		return
	for child: Node in _effect_holder.get_children():
		_effect_holder.remove_child(child)
		child.queue_free()
	if _kind == "effect":
		var card := _effect_form(_document.effect, "ШАБЛОН ЭФФЕКТА")
		card.add_child(EditorUi.hint("Шаблон добавляется в активный навык как независимая копия. Уже добавленные эффекты редактируются в самом навыке."))
	elif not _document.effects.is_empty():
		_effect_index = clampi(_effect_index, 0, _document.effects.size() - 1)
		_effect_form(_document.effects[_effect_index], "ЭФФЕКТ %d" % (_effect_index + 1))
	_apply_conditions()


func _passive_form() -> void:
	var attack := EditorUi.card(_form, "БАЗОВАЯ АТАКА")
	var grid := EditorUi.form(attack)
	_number(grid, "Бонус урона", _document, "attack_bonus", 0, 9999, _change, "Добавляется к обычной атаке и умениям, использующим базовый урон.")
	var types := {"": "Не менять тип урона"}
	types.merge(SkillLibrary.DAMAGE_TYPES)
	_choice(grid, "Тип урона", _document, "damage_type", types, _change, "У юнита может быть только одно пассивное умение, меняющее тип урона.")
	_choice(grid, "Накладываемое состояние", _document, "status", _status_choices(), _change, "Накладывается базовой атакой и ответным ударом.")
	var levels := _number(grid, "Уровней за удар", _document, "levels", 1, 99, _change)
	_enable_when(levels, func() -> bool: return not String(_document.status).is_empty())
	var defence := EditorUi.card(_form, "ЗАЩИТА И ОТВЕТ")
	var defence_grid := EditorUi.form(defence)
	_choice(defence_grid, "Невосприимчивость", _document, "immunity", _status_choices(), _change, "Состояние не накладывается на юнита.")
	_check(defence, "Ответный удар в ближнем бою", _document, "retaliation", _change, "Юнит отвечает обычной атакой на удар ближнего боя.")
	defence.add_child(EditorUi.hint("Пассивные свойства действуют постоянно и подключаются при следующей загрузке библиотеки или боя."))


func _status_choices() -> Dictionary:
	var choices := {"": "Нет"}
	for id: StringName in UnitStatusCatalog.RULES:
		choices[String(id)] = UnitStatusCatalog.display_name(id)
	return choices


func _effect_form(effect: Dictionary, title: String) -> VBoxContainer:
	var card := EditorUi.card(_effect_holder, title)
	var grid := EditorUi.form(card)
	# Re-selecting the same type keeps the authored parameters.
	_choice(grid, "Тип эффекта", effect, "type", EFFECT_TYPES, func(_key: String, value: String) -> void:
		if value == _current_effect().type:
			return
		_replace_effect(SkillLibrary.new_effect(value))
		_render_effect()
	)
	var params: Dictionary = effect.parameters.duplicate(true)
	if effect.type == "core:damage" and not params.has("secondary_amount"):
		params["secondary_amount"] = params.get("amount", 1)
	match effect.type:
		"core:damage":
			var base := func() -> bool: return not _current_effect().parameters.get("use_base_attack", false)
			_enable_when(_number(grid, "Урон основной цели", params, "amount", 1, 9999, _effect_change), base)
			_enable_when(_number(grid, "Урон остальных в области", params, "secondary_amount", 1, 9999, _effect_change, "Урон по остальным целям области навыка."), base)
			_choice(grid, "Тип урона", params, "damage_type", SkillLibrary.DAMAGE_TYPES, _effect_change)
			var flags := HFlowContainer.new()
			flags.add_theme_constant_override("h_separation", 18)
			card.add_child(flags)
			_check(flags, "Урон базовой атаки вместо чисел", params, "use_base_attack", _effect_change, "Берётся базовый урон юнита с пассивными бонусами.")
			_check(flags, "Повреждать препятствия", params, "affects_obstacles", _effect_change, "Разрушаемое препятствие получает урон один раз за эффект.")
		"core:unit_status":
			var choices := _status_choices()
			choices.erase("")
			_choice(grid, "Состояние", params, "status_id", choices, _effect_change)
			_number(grid, "Накладываемых уровней", params, "levels", 1, 9999, _effect_change)
		"core:hex_state":
			var choices := {}
			for id: StringName in HexStateCatalog.RULES:
				choices[String(id)] = HexStateCatalog.get_display_name(id)
			_choice(grid, "Состояние гекса", params, "state_id", choices, _effect_change)
			card.add_child(EditorUi.hint("Состояние гекса живёт %d полных раунда и использует общие правила реакций." % HexStateCatalog.LIFETIME))
		"core:summon":
			_choice(grid, "Призываемый юнит", params, "unit_id", _summon_choices(), _effect_change)
			card.add_child(EditorUi.hint("Для призыва выберите цель «Пустой гекс», радиус 0 и единственный эффект."))
	return card


func _summon_choices() -> Dictionary:
	var choices := {}
	for unit: UnitDefinition in SkillLibrary.units().values():
		if unit.ability_ids.is_empty():
			choices[String(unit.id)] = unit.display_name
	return choices


func _current_effect() -> Dictionary:
	return _document.effect if _kind == "effect" else _document.effects[clampi(_effect_index, 0, _document.effects.size() - 1)]


func _effect_change(key: String, value: Variant) -> void:
	var effect: Dictionary = _current_effect().duplicate(true)
	effect.parameters[key] = value
	_replace_effect(effect)


func _replace_effect(effect: Dictionary) -> void:
	if _kind == "effect":
		_change("effect", effect)
		return
	var effects: Array = _document.effects.duplicate(true)
	effects[_effect_index] = effect
	_change("effects", effects)


func _move_effect(direction: int) -> void:
	var next := _effect_index + direction
	if next < 0 or next >= _document.effects.size():
		return
	var effects: Array = _document.effects.duplicate(true)
	var effect: Dictionary = effects[_effect_index]
	effects[_effect_index] = effects[next]
	effects[next] = effect
	_change("effects", effects)
	_effect_index = next
	_fill_effects_list()
	_render_effect()


func _remove_effect() -> void:
	var effects: Array = _document.effects.duplicate(true)
	if effects.size() <= 1:
		EditorUi.set_status(_status, "Навык должен содержать хотя бы один эффект.", EditorUi.Severity.WARN)
		return
	effects.remove_at(_effect_index)
	_change("effects", effects)
	_fill_effects_list()
	_render_effect()


func _effect_summary(effect: Dictionary) -> String:
	var params: Dictionary = effect.parameters
	match effect.type:
		"core:damage":
			if params.get("use_base_attack", false):
				return "Урон базовой атаки (%s)" % SkillLibrary.DAMAGE_TYPES.get(params.get("damage_type", "physical"), "?")
			return "Урон %s / %s (%s)" % [params.get("amount", 1), params.get("secondary_amount", params.get("amount", 1)), SkillLibrary.DAMAGE_TYPES.get(params.get("damage_type", "physical"), "?")]
		"core:unit_status":
			return "%s ×%s" % [UnitStatusCatalog.display_name(StringName(params.get("status_id", ""))), params.get("levels", 1)]
		"core:hex_state":
			return "Гекс: " + HexStateCatalog.get_display_name(StringName(params.get("state_id", "")))
	return "Призыв: " + String(_summon_choices().get(String(params.get("unit_id", "")), params.get("unit_id", "")))


func _effect_description(effect: Dictionary) -> String:
	var params: Dictionary = effect.parameters
	match effect.type:
		"core:unit_status":
			return UnitStatusCatalog.description(StringName(params.get("status_id", "")))
		"core:hex_state":
			return HexStateCatalog.description(StringName(params.get("state_id", "")))
		"core:damage":
			return "Броня поглощает только физический урон. Влага и горение меняют огненный, водный и электрический урон по правилам состояний."
	return "Призванный юнит появляется на выбранном свободном гексе на стороне владельца."


func _update_status() -> void:
	var stored := not String(_document.id).begins_with("custom_skills:") or _authored.has(_document.id)
	EditorUi.set_dirty(_dirty, _document != _saved, stored)
	var error := SkillLibrary.validate(_document)
	if error.is_empty():
		EditorUi.set_status(_validation, "✓ Данные корректны", EditorUi.Severity.OK)
	else:
		EditorUi.set_status(_validation, "✗ " + error, EditorUi.Severity.ERROR)
	_validation.tooltip_text = error
	_apply_conditions()
	if _effects_list != null and _effects_list.item_count == _document.effects.size():
		for index: int in range(_effects_list.item_count):
			_effects_list.set_item_text(index, "%d. %s" % [index + 1, _effect_summary(_document.effects[index])])
	_update_help()


func _update_help() -> void:
	var lines: PackedStringArray = []
	match _kind:
		"active":
			var mode := int(_document.target_mode)
			lines.append("Цель — %s." % String(TARGET_MODES.get(mode, "?")).to_lower())
			lines.append(TARGET_HELP.get(mode, ""))
			lines.append("Дальность: %s; радиус области: %s." % ["как у базовой атаки" if _document.uses_attack_range else str(_document.range), _document.area_radius])
			lines.append("Перезарядка %s: навык недоступен на %s следующих собственных ходах." % [_document.cooldown_turns, _document.cooldown_turns])
			for index: int in range(_document.effects.size()):
				var effect: Dictionary = _document.effects[index]
				lines.append("")
				lines.append("%d. %s" % [index + 1, _effect_summary(effect)])
				lines.append(_effect_description(effect))
		"passive":
			for key: String in ["status", "immunity"]:
				var id := StringName(_document[key])
				if not id.is_empty():
					lines.append("%s — %s" % [UnitStatusCatalog.display_name(id), "накладывается ударом" if key == "status" else "невосприимчивость"])
					lines.append(UnitStatusCatalog.description(id))
					lines.append("")
			if lines.is_empty():
				lines.append("Выберите состояние или невосприимчивость, чтобы увидеть их правила.")
		"effect":
			lines.append(_effect_summary(_document.effect))
			lines.append(_effect_description(_document.effect))
	_help.text = "\n".join(lines)


func _refresh_list() -> void:
	_list.clear()
	var authored := SkillLibrary.read_all()
	_authored = authored.documents
	var builtin := SkillLibrary.builtin_documents()
	var catalog := builtin.duplicate()
	catalog.merge(authored.documents, true)
	var filter := _search.text.strip_edges().to_lower()
	var entries: Array = catalog.values().filter(func(data: Dictionary) -> bool:
		return data.kind == _kind and (filter.is_empty() or (String(data.name) + " " + String(data.id)).to_lower().contains(filter))
	)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	for data: Dictionary in entries:
		var custom := not builtin.has(data.id)
		var overridden := not custom and _authored.has(data.id)
		var index := _list.add_item(String(data.name) + (" [изменён]" if overridden else ""))
		_list.set_item_metadata(index, data.id)
		_list.set_item_tooltip(index, "%s\n%s" % [data.id, "Определение проекта" if custom else ("Встроенное, переопределено в проекте" if overridden else "Встроенное определение")])
		if custom:
			_list.set_item_custom_fg_color(index, EditorUi.INFO)
		elif overridden:
			_list.set_item_custom_fg_color(index, EditorUi.ACCENT)
		if data.id == _document.get("id"):
			_list.select(index)
	_library_count.text = "Показано: %d. Белые — встроенные, бирюзовые — навыки проекта, [изменён] — встроенные с переопределением." % entries.size()
	if not authored.errors.is_empty():
		EditorUi.set_status(_status, "Ошибки файлов навыков: " + " · ".join(authored.errors), EditorUi.Severity.ERROR)
	if not _document.is_empty():
		_update_status()


func _select(index: int) -> void:
	var id: String = _list.get_item_metadata(index)
	_refresh_list()
	if id == _document.get("id"):
		return
	_request(func() -> void:
		var catalog := SkillLibrary.catalog()
		if not catalog.has(id):
			EditorUi.set_status(_status, "Определение %s больше не найдено на диске." % id, EditorUi.Severity.ERROR)
			_refresh_list()
			return
		_set_document(catalog[id])
		EditorUi.set_status(_status, "Открыто: " + id)
	)


func _save() -> void:
	var error := SkillLibrary.save_document(_document)
	if not error.is_empty():
		EditorUi.set_status(_status, "Не сохранено: " + error, EditorUi.Severity.ERROR)
		return
	_saved = _document.duplicate(true)
	_refresh_list()
	EditorUi.set_status(_status, "Сохранено: " + ProjectSettings.globalize_path(SkillLibrary.ROOT.path_join(SkillLibrary.filename_for(_document))), EditorUi.Severity.OK)


func _copy() -> void:
	var data := _document.duplicate(true)
	data.id = SkillLibrary.new_document(_kind).id
	data.name = String(data.name).left(110) + " — копия"
	_request(func() -> void:
		_set_document(data, false)
		EditorUi.set_status(_status, "Копия создана; сохраните её как отдельное определение.")
	)


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
