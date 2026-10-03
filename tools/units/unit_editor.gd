class_name UnitEditor
extends Control

signal closed
signal unit_saved

var embedded := false
var _document: Dictionary = {}
var _saved: Dictionary = {}
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _sync := false
var _list: ItemList
var _name: LineEdit
var _assets: OptionButton
var _attack: OptionButton
var _numbers: Dictionary[String, SpinBox] = {}
var _ability_checks: Dictionary[String, CheckBox] = {}
var _passive_checks: Dictionary[String, CheckBox] = {}
var _preview: TextureRect
var _status: Label
var _identity: Label
var _effective_damage: Label
var _confirm: ConfirmationDialog
var _pending: Callable
var _previous_auto_accept := true
var _preview_asset := ""

func _ready() -> void:
	_build_ui()
	var error := UnitLibrary.ensure_folders()
	_refresh_assets()
	_refresh_list()
	_new_document()
	if not error.is_empty():
		_status.text = error
	_previous_auto_accept = get_tree().auto_accept_quit
	get_tree().auto_accept_quit = false

func _exit_tree() -> void:
	get_tree().auto_accept_quit = _previous_auto_accept

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_request(func() -> void: get_tree().quit())

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "РЕДАКТОР ЮНИТОВ"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button("Вернуться к бою" if embedded else "Закрыть", func() -> void: _request(_leave)))
	var actions := HFlowContainer.new()
	root.add_child(actions)
	actions.add_child(_button("Новый", func() -> void: _request(_new_document)))
	actions.add_child(_button("Сохранить", _save))
	actions.add_child(_button("Создать копию", _copy_document))
	actions.add_child(_button("Отменить", _undo_edit))
	actions.add_child(_button("Повторить", _redo_edit))
	actions.add_child(_button("Папка юнитов", func() -> void: _open_folder(UnitLibrary.UNITS)))
	actions.add_child(_button("Папка изображений", func() -> void: _open_folder(UnitLibrary.ASSETS)))
	actions.add_child(_button("Обновить списки", _refresh))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	root.add_child(body)
	_list = ItemList.new()
	_list.custom_minimum_size.x = 230
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_select_file)
	body.add_child(_list)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 390
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 9)
	scroll.add_child(form)
	_identity = Label.new()
	_identity.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	form.add_child(_identity)
	_name = LineEdit.new()
	_name.max_length = 120
	_name.text_changed.connect(func(value: String) -> void: _change("name", value))
	_field(form, "Имя юнита", _name)
	_assets = OptionButton.new()
	_assets.item_selected.connect(func(index: int) -> void: _change("image", _assets.get_item_text(index)))
	_field(form, "Изображение из папки assets", _assets)
	_number(form, "ОЗ", "hp", 1, 9999)
	_number(form, "Базовый урон", "damage", 0, 9999)
	_attack = OptionButton.new()
	_attack.add_item("Ближняя атака")
	_attack.add_item("Дальняя атака")
	_attack.item_selected.connect(func(index: int) -> void: _change("attack_type", "melee" if index == 0 else "ranged"))
	_field(form, "Тип атаки", _attack)
	_number(form, "Дальность дальней атаки (2–20 гексов)", "attack_range", 2, 20)
	_number(form, "Дальность передвижения (очки)", "movement", 0, 100)
	for id: String in UnitLibrary.ACTIVE_ABILITIES:
		var check := CheckBox.new()
		check.text = UnitLibrary.ACTIVE_ABILITIES[id]
		check.toggled.connect(func(enabled: bool) -> void: _toggle("abilities", id, enabled))
		_ability_checks[id] = check
		form.add_child(check)
	for id: StringName in PassiveAbilityCatalog.DEFINITIONS:
		var check := CheckBox.new()
		check.text = PassiveAbilityCatalog.DEFINITIONS[id].name
		check.toggled.connect(func(enabled: bool) -> void: _toggle("passives", String(id), enabled))
		_passive_checks[String(id)] = check
		form.add_child(check)
	_effective_damage = Label.new()
	form.add_child(_effective_damage)
	var preview_column := VBoxContainer.new()
	preview_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_column.custom_minimum_size.x = 160
	body.add_child(preview_column)
	var caption := Label.new()
	caption.text = "ИЗОБРАЖЕНИЕ ЮНИТА"
	preview_column.add_child(caption)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_column.add_child(_preview)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Несохранённые изменения"
	_confirm.dialog_text = "Отбросить несохранённые изменения юнита?"
	_confirm.ok_button_text = "Отбросить"
	_confirm.cancel_button_text = "Продолжить редактирование"
	_confirm.confirmed.connect(func() -> void: _pending.call())
	add_child(_confirm)

func _field(parent: Control, title: String, control: Control) -> void:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	parent.add_child(control)

func _number(parent: Control, title: String, key: String, minimum: int, maximum: int) -> void:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1
	spin.value_changed.connect(func(value: float) -> void: _change(key, int(value)))
	_numbers[key] = spin
	_field(parent, title, spin)

func _button(title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(action)
	return button

func _new_document() -> void:
	_set_document(UnitLibrary.new_document())
	_status.text = "Новый юнит. Сохраните его, чтобы добавить в палитру редактора боя."

func _set_document(data: Dictionary) -> void:
	_document = data.duplicate(true)
	_saved = data.duplicate(true)
	_undo.clear()
	_redo.clear()
	_render()

func _change(key: String, value: Variant) -> void:
	if _sync or _document.get(key) == value:
		return
	_undo.append(_document.duplicate(true))
	if _undo.size() > 100:
		_undo.pop_front()
	_redo.clear()
	_document[key] = value
	_update_preview()

func _toggle(key: String, id: String, enabled: bool) -> void:
	if _sync:
		return
	var values: Array = _document[key].duplicate()
	if enabled and id not in values:
		values.append(id)
	elif not enabled:
		values.erase(id)
	_change(key, values)

func _render() -> void:
	_sync = true
	_name.text = _document.name
	_attack.select(0 if _document.attack_type == "melee" else 1)
	_assets.select(-1)
	for index: int in range(_assets.item_count):
		if _assets.get_item_text(index) == _document.image:
			_assets.select(index)
	for key: String in _numbers:
		_numbers[key].value = _document[key]
	for id: String in _ability_checks:
		_ability_checks[id].button_pressed = id in _document.abilities
	for id: String in _passive_checks:
		_passive_checks[id].button_pressed = id in _document.passives
	_sync = false
	_update_preview()

func _update_preview() -> void:
	_identity.text = "Есть несохранённые изменения" if _document != _saved else "Параметры юнита"
	_identity.tooltip_text = String(_document.id)
	_numbers["attack_range"].editable = _document.attack_type == "ranged"
	if _preview_asset != _document.image:
		_preview_asset = _document.image
		_preview.texture = UnitLibrary.texture_for(_document.image)
	var ids: Array[StringName] = []
	ids.assign(_document.passives)
	var bonus := PassiveAbilityCatalog.attack_bonus(ids)
	_effective_damage.text = "Урон обычной атаки в бою: %s + %s = %s" % [_document.damage, bonus, int(_document.damage) + bonus]

func _undo_edit() -> void:
	if _undo.is_empty():
		return
	_redo.append(_document.duplicate(true))
	_document = _undo.pop_back()
	_render()

func _redo_edit() -> void:
	if _redo.is_empty():
		return
	_undo.append(_document.duplicate(true))
	_document = _redo.pop_back()
	_render()

func _save() -> void:
	var error := UnitLibrary.save_document(_document)
	if not error.is_empty():
		_status.text = error
		return
	_saved = _document.duplicate(true)
	_update_preview()
	_refresh_list()
	_status.text = "Сохранено: %s" % ProjectSettings.globalize_path(
		UnitLibrary.UNITS.path_join(String(_document.id).trim_prefix("custom_units:") + ".json")
	)
	unit_saved.emit()

func _copy_document() -> void:
	var copy := _document.duplicate(true)
	copy.id = UnitLibrary.new_document().id
	copy.name = String(copy.name).left(110) + " — копия"
	_request(func() -> void:
		_set_document(copy)
		_saved = {}
		_update_preview()
		_status.text = "Копия создана; сохраните её как отдельного юнита."
	)

func _select_file(index: int) -> void:
	var path: String = _list.get_item_metadata(index)
	_refresh_list()
	_request(func() -> void:
		var result := UnitLibrary.read_document(path)
		if not String(result.error).is_empty():
			_status.text = result.error
			return
		_set_document(result.document)
		_refresh_list()
		_status.text = "Открыт: %s" % path
	)

func _refresh_list() -> void:
	_list.clear()
	for filename: String in DirAccess.get_files_at(UnitLibrary.UNITS):
		if filename.get_extension().to_lower() != "json":
			continue
		var path := UnitLibrary.UNITS.path_join(filename)
		var result := UnitLibrary.read_document(path)
		var title := filename if not String(result.error).is_empty() else String(result.document.name)
		var index := _list.add_item(title)
		_list.set_item_metadata(index, path)
		_list.set_item_tooltip(index, path if String(result.error).is_empty() else result.error)
		if String(result.error).is_empty() and result.document.id == _document.get("id"):
			_list.select(index)

func _refresh_assets() -> void:
	_assets.clear()
	for filename: String in UnitLibrary.asset_names():
		_assets.add_item(filename)

func _refresh() -> void:
	_preview_asset = ""
	_refresh_assets()
	_refresh_list()
	_render()
	_status.text = "Списки обновлены."

func _request(action: Callable) -> void:
	if _document != _saved:
		_pending = action
		_confirm.popup_centered()
	else:
		action.call()

func _open_folder(path: String) -> void:
	var error := OS.shell_open(ProjectSettings.globalize_path(path))
	if error != OK:
		_status.text = "Не удалось открыть папку: %s" % error_string(error)

func _leave() -> void:
	if embedded:
		closed.emit()
		queue_free()
	else:
		get_tree().quit()
