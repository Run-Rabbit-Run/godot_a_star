class_name SkillEditor
extends Control

signal closed
var embedded := false
var _document: Dictionary = {}
var _saved: Dictionary = {}
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _kind := "active"
var _effect_index := 0
var _list: ItemList
var _form: VBoxContainer
var _status: Label
var _identity: Label
var _category: OptionButton
var _search: LineEdit
var _confirm: ConfirmationDialog
var _pending: Callable
var _sync := false
var _previous_auto_accept := true

func _ready() -> void:
	_build_ui()
	_previous_auto_accept = get_tree().auto_accept_quit
	get_tree().auto_accept_quit = false
	_new_document()

func _exit_tree() -> void:
	get_tree().auto_accept_quit = _previous_auto_accept

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not embedded: request_close(func() -> void: get_tree().quit())

func request_close(action: Callable) -> void:
	_request(action)

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	return button

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "РЕДАКТОР НАВЫКОВ И ЭФФЕКТОВ"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button("Вернуться" if embedded else "Закрыть", func() -> void: _request(_leave)))
	var toolbar := HFlowContainer.new()
	root.add_child(toolbar)
	_category = OptionButton.new()
	for text: String in ["Активные навыки", "Пассивные навыки", "Накладываемые эффекты"]: _category.add_item(text)
	_category.item_selected.connect(func(index: int) -> void:
		var next: String = SkillLibrary.KINDS[index]
		_category.select(SkillLibrary.KINDS.find(_kind))
		_request(func() -> void:
			_kind = next
			_new_document()
		))
	toolbar.add_child(_category)
	toolbar.add_child(_button("Новый", func() -> void: _request(_new_document)))
	toolbar.add_child(_button("Сохранить", _save))
	toolbar.add_child(_button("Создать копию", _copy))
	toolbar.add_child(_button("Отменить", _undo_edit))
	toolbar.add_child(_button("Повторить", _redo_edit))
	toolbar.add_child(_button("Обновить библиотеку", _refresh_list))
	toolbar.add_child(_button("Папка данных", func() -> void:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SkillLibrary.ROOT))
		OS.shell_open(ProjectSettings.globalize_path(SkillLibrary.ROOT))
	))
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var library := VBoxContainer.new()
	library.custom_minimum_size.x = 380
	body.add_child(library)
	_search = LineEdit.new()
	_search.placeholder_text = "Поиск по имени или ID"
	_search.text_changed.connect(func(_text: String) -> void: _refresh_list())
	library.add_child(_search)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_select)
	library.add_child(_list)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	_form = VBoxContainer.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form.add_theme_constant_override("separation", 8)
	scroll.add_child(_form)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Несохранённые изменения"
	_confirm.dialog_text = "Отбросить несохранённые изменения навыка или эффекта?"
	_confirm.ok_button_text = "Отбросить"
	_confirm.cancel_button_text = "Продолжить редактирование"
	_confirm.confirmed.connect(func() -> void: _pending.call())
	add_child(_confirm)

func _field(title: String, control: Control) -> void:
	_label(title)
	_form.add_child(control)

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_form.add_child(label)
	return label

func _number(title: String, data: Dictionary, key: String, minimum: int, maximum: int, action: Callable) -> void:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.value = data.get(key, minimum)
	spin.value_changed.connect(func(value: float) -> void: action.call(key, int(value)))
	_field(title, spin)

func _choice(title: String, data: Dictionary, key: String, values: Dictionary, action: Callable) -> void:
	var option := OptionButton.new()
	for value: Variant in values:
		option.add_item(values[value])
		option.set_item_metadata(option.item_count - 1, value)
		if str(data.get(key, "")) == str(value): option.select(option.item_count - 1)
	option.item_selected.connect(func(index: int) -> void: action.call(key, option.get_item_metadata(index)))
	_field(title, option)

func _check(title: String, data: Dictionary, key: String, action: Callable) -> void:
	var box := CheckBox.new()
	box.text = title
	box.button_pressed = data.get(key, false)
	box.toggled.connect(func(value: bool) -> void: action.call(key, value))
	_form.add_child(box)

func _new_document() -> void:
	_set_document(SkillLibrary.new_document(_kind))

func _set_document(data: Dictionary, saved := true) -> void:
	_document = data.duplicate(true)
	_saved = data.duplicate(true) if saved else {}
	_kind = data.kind
	_effect_index = 0
	_undo.clear()
	_redo.clear()
	_render()
	_refresh_list()

func _change(key: String, value: Variant) -> void:
	if _sync or _document.get(key) == value: return
	_undo.append(_document.duplicate(true))
	if _undo.size() > 100: _undo.pop_front()
	_redo.clear()
	_document[key] = value
	_update_status()

func _render() -> void:
	_sync = true
	for child: Node in _form.get_children():
		_form.remove_child(child)
		child.queue_free()
	_category.select(SkillLibrary.KINDS.find(_kind))
	_identity = _label("")
	_label("ID: " + String(_document.id))
	var name_field := LineEdit.new()
	name_field.text = _document.name
	name_field.max_length = 120
	name_field.text_changed.connect(func(value: String) -> void: _change("name", value))
	_field("Название", name_field)
	match _kind:
		"active": _active_form()
		"passive": _passive_form()
		"effect":
			_label("Шаблон добавляется в активный навык как независимая копия. Уже добавленные эффекты редактируются в самом навыке.")
			_effect_form(_document.effect)
	_sync = false
	_update_status()

func _active_form() -> void:
	_label("ЭФФЕКТЫ НАВЫКА — выполняются по порядку")
	var choices := {}
	for index: int in range(_document.effects.size()):
		choices[index] = "%d. %s" % [index + 1, _effect_summary(_document.effects[index])]
	_effect_index = clampi(_effect_index, 0, maxi(0, _document.effects.size() - 1))
	_choice("Редактируемый эффект", {"index": _effect_index}, "index", choices, func(_key: String, value: int) -> void:
		_effect_index = value
		_render()
	)
	var buttons := HFlowContainer.new()
	_form.add_child(buttons)
	buttons.add_child(_button("Добавить эффект", func() -> void:
		var effects: Array = _document.effects.duplicate(true)
		effects.append(SkillLibrary.new_effect())
		_change("effects", effects)
		_effect_index = effects.size() - 1
		_render()
	))
	buttons.add_child(_button("Удалить эффект", func() -> void:
		var effects: Array = _document.effects.duplicate(true)
		if effects.size() <= 1: return
		effects.remove_at(_effect_index)
		_change("effects", effects)
		_render()
	))
	buttons.add_child(_button("Выше", func() -> void: _move_effect(-1)))
	buttons.add_child(_button("Ниже", func() -> void: _move_effect(1)))
	var templates := SkillLibrary.names("effect")
	if not templates.is_empty():
		var menu := MenuButton.new()
		menu.text = "Добавить из шаблона ▾"
		menu.flat = false
		for id: String in templates:
			menu.get_popup().add_item(templates[id])
			menu.get_popup().set_item_metadata(menu.get_popup().item_count - 1, id)
		menu.get_popup().index_pressed.connect(func(index: int) -> void:
			var id: String = menu.get_popup().get_item_metadata(index)
			var effects: Array = _document.effects.duplicate(true)
			effects.append(SkillLibrary.catalog()[id].effect.duplicate(true))
			_change("effects", effects)
			_effect_index = effects.size() - 1
			_render()
		)
		_form.add_child(menu)
	if not _document.effects.is_empty(): _effect_form(_document.effects[_effect_index])
	_label("ПАРАМЕТРЫ ПРИМЕНЕНИЯ НАВЫКА")
	_number("Дальность (гексы)", _document, "range", 1, 99, _change)
	_number("Радиус области (гексы)", _document, "area_radius", 0, 8, _change)
	_choice("Цель", _document, "target_mode", {0: "Автоматически", 1: "Противник", 2: "Гекс", 3: "Пустой гекс (призыв)", 4: "Линия", 5: "Путь", 6: "Свой гекс"}, _change)
	_number("Перезарядка (ходы юнита)", _document, "cooldown_turns", 1, 99, _change)
	_number("Начальная перезарядка", _document, "initial_cooldown_turns", 0, 99, _change)
	_check("Использовать дальность базовой атаки", _document, "uses_attack_range", _change)
	_check("Ближняя атака (допускает ответный удар)", _document, "melee_attack", _change)
	_check("Возврат оружия в следующий ход (только путь и урон)", _document, "returns_next_turn", _change)
	_label("Каждый активный навык расходует основное действие и завершает ход.")
	var presentations := {"": "Автоматическое отображение"}
	for package: ContentPackage in SkillLibrary.packages():
		for definition: AbilityPresentationDefinition in package.ability_presentations:
			presentations[String(definition.id)] = String(definition.id)
	_choice("Отображение в бою", _document, "presentation_id", presentations, _change)

func _passive_form() -> void:
	_label("Пассивные свойства действуют постоянно. Состояние накладывается базовой атакой и ответным ударом.")
	_number("Бонус урона базовой атаки", _document, "attack_bonus", 0, 9999, _change)
	var types := {"": "Не менять тип урона"}
	types.merge(SkillLibrary.DAMAGE_TYPES)
	_choice("Тип урона базовой атаки", _document, "damage_type", types, _change)
	_choice("Накладываемое состояние", _document, "status", _status_choices(), _change)
	_number("Количество уровней состояния за удар", _document, "levels", 1, 99, _change)
	_choice("Невосприимчивость к состоянию", _document, "immunity", _status_choices(), _change)
	_check("Ответный удар в ближнем бою", _document, "retaliation", _change)

func _status_choices() -> Dictionary:
	var choices := {"": "Нет"}
	for id: StringName in UnitStatusCatalog.RULES: choices[String(id)] = UnitStatusCatalog.display_name(id)
	return choices

func _effect_form(effect: Dictionary) -> void:
	_choice("Тип эффекта", effect, "type", {"core:damage": "Урон", "core:unit_status": "Состояние юнита", "core:hex_state": "Состояние гекса", "core:summon": "Призыв"}, func(_key: String, value: String) -> void:
		_replace_effect(SkillLibrary.new_effect(value))
		_render()
	)
	var params: Dictionary = effect.parameters.duplicate(true)
	if effect.type == "core:damage" and not params.has("secondary_amount"):
		params["secondary_amount"] = params.get("amount", 1)
	match effect.type:
		"core:damage":
			_number("Количество урона основной цели", params, "amount", 1, 9999, _effect_change)
			_number("Урон остальных целей в области", params, "secondary_amount", 1, 9999, _effect_change)
			_choice("Тип урона", params, "damage_type", SkillLibrary.DAMAGE_TYPES, _effect_change)
			_check("Брать урон из базовой атаки вместо чисел выше", params, "use_base_attack", _effect_change)
			_check("Повреждать препятствия", params, "affects_obstacles", _effect_change)
		"core:unit_status":
			var choices := _status_choices()
			choices.erase("")
			_choice("Состояние", params, "status_id", choices, _effect_change)
			_number("Количество накладываемых уровней", params, "levels", 1, 9999, _effect_change)
			_label("Правила состояний:")
			for id: StringName in UnitStatusCatalog.RULES:
				_label(UnitStatusCatalog.display_name(id) + ": " + UnitStatusCatalog.description(id))
		"core:hex_state":
			var choices := {}
			for id: StringName in HexStateCatalog.RULES: choices[String(id)] = HexStateCatalog.get_display_name(id)
			_choice("Состояние гекса", params, "state_id", choices, _effect_change)
			_label("Состояние гекса использует общие правила реакций и живёт три полных раунда.")
		"core:summon":
			var choices := {}
			for package: ContentPackage in SkillLibrary.packages():
				for unit: UnitDefinition in package.units:
					if unit.ability_ids.is_empty(): choices[String(unit.id)] = unit.display_name
			_choice("Призываемый юнит", params, "unit_id", choices, _effect_change)
			_label("Для призыва выберите цель «Пустой гекс», радиус 0 и один эффект.")

func _effect_change(key: String, value: Variant) -> void:
	var effect: Dictionary = (_document.effect if _kind == "effect" else _document.effects[_effect_index]).duplicate(true)
	effect.parameters[key] = value
	_replace_effect(effect)

func _replace_effect(effect: Dictionary) -> void:
	if _kind == "effect": _change("effect", effect)
	else:
		var effects: Array = _document.effects.duplicate(true)
		effects[_effect_index] = effect
		_change("effects", effects)

func _move_effect(direction: int) -> void:
	var next := _effect_index + direction
	if next < 0 or next >= _document.effects.size(): return
	var effects: Array = _document.effects.duplicate(true)
	var effect: Dictionary = effects[_effect_index]
	effects[_effect_index] = effects[next]
	effects[next] = effect
	_change("effects", effects)
	_effect_index = next
	_render()

func _effect_summary(effect: Dictionary) -> String:
	var params: Dictionary = effect.parameters
	match effect.type:
		"core:damage": return "Урон %s / %s (%s)" % [params.get("amount", 1), params.get("secondary_amount", params.get("amount", 1)), SkillLibrary.DAMAGE_TYPES.get(params.get("damage_type", "physical"), "?")]
		"core:unit_status": return "%s ×%s" % [UnitStatusCatalog.display_name(StringName(params.status_id)), params.levels]
		"core:hex_state": return "Гекс: " + String(params.state_id)
	return "Призыв: " + String(params.get("unit_id", ""))

func _update_status() -> void:
	_identity.text = "Есть несохранённые изменения" if _document != _saved else "Изменений нет"
	var error := SkillLibrary.validate(_document)
	_status.text = error if not error.is_empty() else "Данные корректны. Сохранение действует при следующей загрузке библиотеки или боя."

func _refresh_list() -> void:
	_list.clear()
	var authored := SkillLibrary.read_all()
	var catalog := SkillLibrary.builtin_documents()
	catalog.merge(authored.documents, true)
	for data: Dictionary in catalog.values():
		if data.kind != _kind: continue
		if not _search.text.is_empty() and not (String(data.name) + String(data.id)).to_lower().contains(_search.text.to_lower()): continue
		var index := _list.add_item(String(data.name) + (" *" if authored.documents.has(data.id) else " [встроенный]"))
		_list.set_item_metadata(index, data.id)
		_list.set_item_tooltip(index, data.id)
		if data.id == _document.get("id"): _list.select(index)
	if not authored.errors.is_empty(): _status.text = "\n".join(authored.errors)

func _select(index: int) -> void:
	var id: String = _list.get_item_metadata(index)
	_refresh_list()
	_request(func() -> void: _set_document(SkillLibrary.catalog()[id]))

func _save() -> void:
	var error := SkillLibrary.save_document(_document)
	if not error.is_empty():
		_status.text = error
		return
	_saved = _document.duplicate(true)
	_update_status()
	_refresh_list()
	_status.text = "Сохранено: " + ProjectSettings.globalize_path(SkillLibrary.ROOT.path_join(SkillLibrary.filename_for(_document)))

func _copy() -> void:
	var data := _document.duplicate(true)
	data.id = SkillLibrary.new_document(_kind).id
	data.name = String(data.name).left(110) + " — копия"
	_request(func() -> void: _set_document(data, false))

func _undo_edit() -> void:
	if _undo.is_empty(): return
	_redo.append(_document.duplicate(true))
	_document = _undo.pop_back()
	_render()

func _redo_edit() -> void:
	if _redo.is_empty(): return
	_undo.append(_document.duplicate(true))
	_document = _redo.pop_back()
	_render()

func _request(action: Callable) -> void:
	if _document != _saved:
		_pending = action
		_confirm.popup_centered()
	else: action.call()

func _leave() -> void:
	if embedded:
		closed.emit()
		queue_free()
	else: get_tree().quit()
