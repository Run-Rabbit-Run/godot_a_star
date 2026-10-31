class_name UnitEditor
extends Control
## Authoring form of one project unit JSON. The dictionary draft is the source of truth.

signal closed
signal unit_saved

const HISTORY_LIMIT := 100
const STATS := [
	["hp", "ОЗ", 1, 9999, "Максимальные очки здоровья."],
	["armor", "Броня", 0, 9999, "Каждый уровень блокирует 1 физического урона. Кислота разрушает броню."],
	["damage", "Базовый урон", 0, 9999, "Урон обычной атаки без пассивных бонусов."],
	["movement", "Передвижение", 0, 100, "Очки передвижения за ход. Дорогие клетки расходуют больше очков."],
]

var embedded := false
var _document: Dictionary = {}
var _saved: Dictionary = {}
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _sync := false
## Consecutive edits of this key share one undo step (typing a name).
var _last_change := ""
## Skill catalog read once per refresh; validation and menus never touch the disk per keystroke.
var _skills: Dictionary = {}
var _list: ItemList
var _search: LineEdit
var _library_count: Label
var _name: LineEdit
var _assets: OptionButton
var _attack: OptionButton
var _numbers: Dictionary[String, SpinBox] = {}
var _range_hint: Label
var _active_menu: MenuButton
var _passive_menu: MenuButton
var _ability_summaries: Dictionary[String, Label] = {}
var _corpse_status: Label
var _preview: TextureRect
var _corpse_preview: TextureRect
var _stats_summary: Label
var _identity: Label
var _dirty: Label
var _status: Label
var _validation: Label
var _effective_damage: Label
var _confirm: ConfirmationDialog
var _pending: Callable
var _previous_auto_accept := true
var _preview_asset := ""


func _ready() -> void:
	_build_ui()
	var error := UnitLibrary.ensure_folders()
	_skills = SkillLibrary.catalog()
	_refresh_assets()
	_fill_ability_menus()
	_new_document()
	if not error.is_empty():
		EditorUi.set_status(_status, error, EditorUi.Severity.ERROR)
	_previous_auto_accept = get_tree().auto_accept_quit
	get_tree().auto_accept_quit = false


func _exit_tree() -> void:
	get_tree().auto_accept_quit = _previous_auto_accept


func _notification(what: int) -> void:
	# An embedding host owns window closing and asks this editor first via request_close().
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not embedded:
		_request(func() -> void: get_tree().quit())


## Runs the action at once when the unit is saved, otherwise after the discard confirmation.
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
	_build_form(body)
	_build_preview(body)
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
	_confirm = EditorUi.confirm_discard(self, "Отбросить несохранённые изменения юнита?", func() -> void: _pending.call())


func _build_header(root: Control) -> void:
	var header := EditorUi.bar(root)
	header.add_child(EditorUi.label("Редактор юнитов", &"TitleLabel"))
	_dirty = EditorUi.label("")
	header.add_child(_dirty)
	header.add_child(EditorUi.spacer())
	var create := EditorUi.button("Новый", func() -> void: _request(_new_document), "Создать нового юнита")
	EditorUi.add_shortcut(create, KEY_N, true)
	header.add_child(create)
	header.add_child(EditorUi.button("Копия", _copy_document, "Создать независимую копию с новым ID"))
	header.add_child(EditorUi.separator())
	var undo := EditorUi.button("Отменить", _undo_edit)
	EditorUi.add_shortcut(undo, KEY_Z, true)
	header.add_child(undo)
	var redo := EditorUi.button("Повторить", _redo_edit)
	EditorUi.add_shortcut(redo, KEY_Y, true)
	EditorUi.add_shortcut(redo, KEY_Z, true, true)
	header.add_child(redo)
	header.add_child(EditorUi.separator())
	var folders := MenuButton.new()
	folders.text = "Папки ▾"
	folders.flat = false
	folders.get_popup().add_item("Открыть папку юнитов", 0)
	folders.get_popup().add_item("Открыть папку изображений", 1)
	folders.get_popup().id_pressed.connect(func(id: int) -> void:
		_open_folder(UnitLibrary.UNITS if id == 0 else UnitLibrary.ASSETS)
	)
	header.add_child(folders)
	var refresh := EditorUi.button("Обновить", _refresh, "Перечитать юнитов, изображения и навыки с диска")
	EditorUi.add_shortcut(refresh, KEY_R, true)
	header.add_child(refresh)
	var save := EditorUi.button("Сохранить", _save, "", &"PrimaryButton")
	EditorUi.add_shortcut(save, KEY_S, true)
	header.add_child(save)
	header.add_child(EditorUi.button("Вернуться к бою" if embedded else "Закрыть", func() -> void: _request(_leave)))


func _build_library(body: Control) -> void:
	var library := EditorUi.card(body, "БИБЛИОТЕКА ЮНИТОВ")
	(library.get_parent() as Control).custom_minimum_size.x = 330
	_search = LineEdit.new()
	_search.placeholder_text = "Поиск по имени или ID"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_text: String) -> void: _refresh_list())
	library.add_child(_search)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.fixed_icon_size = Vector2i(40, 40)
	_list.item_selected.connect(_select_file)
	library.add_child(_list)
	_library_count = EditorUi.hint("")
	library.add_child(_library_count)


func _build_form(body: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 14)
	scroll.add_child(column)

	var basics := EditorUi.form(EditorUi.card(column, "ОСНОВНОЕ"))
	_name = LineEdit.new()
	_name.max_length = 120
	_name.placeholder_text = "Имя юнита"
	_name.text_changed.connect(func(value: String) -> void: _change("name", value))
	EditorUi.row(basics, "Имя", _name)
	_assets = OptionButton.new()
	_assets.fit_to_longest_item = false
	_assets.add_theme_constant_override("icon_max_width", 28)
	_assets.item_selected.connect(func(index: int) -> void: _change("image", _assets.get_item_text(index)))
	EditorUi.row(basics, "Изображение", _assets, "PNG, WebP или JPG из папки изображений проекта. Используется для фигуры и портрета.")
	_corpse_status = EditorUi.hint("")
	EditorUi.row(basics, "Погибший вариант", _corpse_status, "Тело с тем же именем файла в content/authored/assets/corpses/.")
	_identity = EditorUi.label("", &"MutedLabel")
	EditorUi.row(basics, "ID", _identity, "Стабильный ID. Переименование его не меняет, копия получает новый.")

	var stats := EditorUi.form(EditorUi.card(column, "ХАРАКТЕРИСТИКИ"), 4)
	for entry: Array in STATS:
		_number(stats, entry[1], entry[0], entry[2], entry[3], entry[4])

	var attack_card := EditorUi.card(column, "АТАКА")
	var attack := EditorUi.form(attack_card)
	_attack = OptionButton.new()
	_attack.add_item("Ближняя атака")
	_attack.add_item("Дальняя атака")
	_attack.item_selected.connect(_set_attack_type)
	EditorUi.row(attack, "Тип атаки", _attack)
	_number(attack, "Дальность", "attack_range", 2, 20, "Дальняя атака: 2–20 гексов, включая соседнюю клетку.")
	_range_hint = EditorUi.hint("")
	attack_card.add_child(_range_hint)
	_effective_damage = EditorUi.label("", &"FieldLabel")
	attack_card.add_child(_effective_damage)

	var abilities_card := EditorUi.card(column, "УМЕНИЯ")
	var abilities := EditorUi.form(abilities_card)
	_active_menu = _ability_menu(abilities, "Активные", "abilities")
	_passive_menu = _ability_menu(abilities, "Пассивные", "passives")
	abilities_card.add_child(EditorUi.hint("Активное умение расходует основное действие и завершает ход. Тип урона базовой атаки меняет только одно пассивное умение. Сами умения настраиваются в редакторе навыков."))


func _build_preview(body: Control) -> void:
	var preview := EditorUi.card(body, "ПРЕДПРОСМОТР")
	(preview.get_parent() as Control).custom_minimum_size.x = 400
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.add_child(_preview)
	var corpse := HBoxContainer.new()
	corpse.add_theme_constant_override("separation", 10)
	preview.add_child(corpse)
	_corpse_preview = TextureRect.new()
	_corpse_preview.custom_minimum_size = Vector2(150, 90)
	_corpse_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_corpse_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	corpse.add_child(_corpse_preview)
	corpse.add_child(EditorUi.hint("Погибший вариант на поле боя"))
	preview.add_child(HSeparator.new())
	_stats_summary = EditorUi.label("", &"FieldLabel", true)
	preview.add_child(_stats_summary)


func _number(grid: GridContainer, title: String, key: String, minimum: int, maximum: int, tooltip: String) -> void:
	var spin := EditorUi.spin(minimum, maximum)
	spin.value_changed.connect(func(value: float) -> void: _change(key, int(value)))
	_numbers[key] = spin
	EditorUi.row(grid, title, spin, tooltip)


## Checkable dropdowns preserve multiple abilities and the document's undo/redo.
func _ability_menu(grid: GridContainer, title: String, key: String) -> MenuButton:
	var column := VBoxContainer.new()
	var menu := MenuButton.new()
	menu.flat = false
	menu.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var popup := menu.get_popup()
	popup.hide_on_checkable_item_selection = false
	# Descriptions depend on the unit's attack, so they are filled when the list opens.
	popup.about_to_popup.connect(_refresh_skill_tooltips.bind(popup))
	popup.index_pressed.connect(func(index: int) -> void:
		_toggle(key, popup.get_item_metadata(index), not popup.is_item_checked(index))
	)
	column.add_child(menu)
	var summary := EditorUi.hint("")
	column.add_child(summary)
	_ability_summaries[key] = summary
	EditorUi.row(grid, title, column)
	return menu


func _fill_ability_menus() -> void:
	for pair: Array in [[_active_menu, "active"], [_passive_menu, "passive"]]:
		var popup: PopupMenu = (pair[0] as MenuButton).get_popup()
		popup.clear()
		var entries: Array[Dictionary] = []
		for data: Dictionary in _skills.values():
			if data.kind == pair[1]:
				entries.append(data)
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
		for data: Dictionary in entries:
			popup.add_check_item(String(data.name))
			var index := popup.item_count - 1
			popup.set_item_metadata(index, String(data.id))
			popup.set_item_tooltip(index, _skill_tooltip(data))


func _skill_tooltip(data: Dictionary) -> String:
	var lines := PackedStringArray()
	var description := ""
	if data.kind == "active":
		description = AbilityDescription.render(SkillLibrary.to_ability(data), _unit_context())
	else:
		description = AbilityDescription.render_passive(SkillLibrary.passive_definitions({data.id: data}).values()[0])
	if not description.strip_edges().is_empty():
		lines.append(description.strip_edges())
	if data.kind == "active":
		lines.append("Дальность %s · радиус %s · перезарядка %s" % ["атаки" if data.uses_attack_range else str(data.range), data.area_radius, data.cooldown_turns])
	lines.append(String(data.id))
	return "\n".join(lines)


## Attack of the edited unit as battle will see it, for unit-dependent skill description variables.
func _unit_context() -> Dictionary:
	if _document.is_empty():
		return {}
	var ids: Array[StringName] = []
	ids.assign(_document.passives)
	var bonus := PassiveAbilityCatalog.attack_bonus(ids, SkillLibrary.passive_definitions(_skills))
	return {"attack_damage": int(_document.damage) + bonus, "attack_range": int(_document.attack_range) if _document.attack_type == "ranged" else 1}


func _refresh_skill_tooltips(popup: PopupMenu) -> void:
	for index in range(popup.item_count):
		var data: Dictionary = _skills.get(String(popup.get_item_metadata(index)), {})
		if not data.is_empty():
			popup.set_item_tooltip(index, _skill_tooltip(data))


func _new_document() -> void:
	_set_document(UnitLibrary.new_document())
	EditorUi.set_status(_status, "Новый юнит. Сохраните его, чтобы добавить в палитру редактора боя.")


func _set_document(data: Dictionary) -> void:
	_document = data.duplicate(true)
	_saved = data.duplicate(true)
	_undo.clear()
	_redo.clear()
	_last_change = ""
	_render()
	_refresh_list()


func _remember(key := "") -> void:
	if key == "name" and _last_change == "name" and not _undo.is_empty() and _redo.is_empty():
		return
	_last_change = key
	_undo.append(_document.duplicate(true))
	if _undo.size() > HISTORY_LIMIT:
		_undo.pop_front()
	_redo.clear()


func _change(key: String, value: Variant) -> void:
	if _sync or _document.get(key) == value:
		return
	_remember(key)
	_document[key] = value
	_refresh_state()


## Switching to ranged attack keeps the stored range inside its 2–20 rule in the same undo step.
func _set_attack_type(index: int) -> void:
	var value := "melee" if index == 0 else "ranged"
	if _sync or _document.attack_type == value:
		return
	_remember("attack_type")
	_document.attack_type = value
	if value == "ranged" and int(_document.attack_range) < 2:
		_document.attack_range = 2
	_render()


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
	if _name.text != _document.name:
		_name.text = _document.name
	_attack.select(0 if _document.attack_type == "melee" else 1)
	_assets.select(-1)
	for index: int in range(_assets.item_count):
		if _assets.get_item_text(index) == _document.image:
			_assets.select(index)
	for key: String in _numbers:
		_numbers[key].value = _document.get(key, 0)
	_sync = false
	_refresh_state()


func _refresh_state() -> void:
	EditorUi.set_dirty(_dirty, _document != _saved, FileAccess.file_exists(_path_for(_document)))
	_identity.text = String(_document.id)
	var ranged: bool = _document.attack_type == "ranged"
	_numbers["attack_range"].editable = ranged
	_range_hint.text = "" if ranged else "Ближняя атака всегда бьёт по соседнему гексу; дальность не используется."
	_range_hint.visible = not ranged
	if _preview_asset != _document.image:
		_preview_asset = _document.image
		_preview.texture = UnitLibrary.texture_for(_document.image)
		_corpse_preview.texture = UnitLibrary.corpse_for(_document.image)
		_corpse_status.text = (
			"Найден: corpses/%s.png" % String(_document.image).get_basename()
			if _corpse_preview.texture != null
			else "Не добавлен — в бою используется запасное тело."
		)
	_sync_ability_menu(_active_menu, "abilities")
	_sync_ability_menu(_passive_menu, "passives")
	var ids: Array[StringName] = []
	ids.assign(_document.passives)
	var bonus := PassiveAbilityCatalog.attack_bonus(ids, SkillLibrary.passive_definitions(_skills))
	_effective_damage.text = "Урон обычной атаки в бою: %s + %s (пассивные) = %s" % [_document.damage, bonus, int(_document.damage) + bonus]
	_stats_summary.text = "%s\nОЗ %s · броня %s · урон %s · передвижение %s\n%s" % [
		_document.name, _document.hp, _document.armor, int(_document.damage) + bonus, _document.movement,
		"Дальняя атака, %s гексов" % _document.attack_range if ranged else "Ближняя атака",
	]
	var error := UnitLibrary.validate(_document, _skills)
	if error.is_empty() and _preview.texture == null:
		error = "Изображение не найдено в папке изображений."
	if error.is_empty():
		EditorUi.set_status(_validation, "✓ Данные корректны", EditorUi.Severity.OK)
	else:
		EditorUi.set_status(_validation, "✗ " + error, EditorUi.Severity.ERROR)
	_validation.tooltip_text = error


func _sync_ability_menu(menu: MenuButton, key: String) -> void:
	var popup := menu.get_popup()
	# References to deleted skills stay visible so they can be unchecked and the unit repaired.
	var listed: Array = []
	for index in range(popup.item_count):
		listed.append(popup.get_item_metadata(index))
	for id: String in _document[key]:
		if id not in listed:
			popup.add_check_item("⚠ %s — нет в библиотеке навыков" % id)
			popup.set_item_metadata(popup.item_count - 1, id)
			popup.set_item_tooltip(popup.item_count - 1, "Снимите отметку, чтобы убрать ссылку на отсутствующий навык.")
	var names: PackedStringArray = []
	for index in range(popup.item_count):
		var selected: bool = popup.get_item_metadata(index) in _document[key]
		popup.set_item_checked(index, selected)
		if selected:
			names.append(popup.get_item_text(index))
	menu.text = ("Выбрано: %d ▾" % names.size()) if not names.is_empty() else "Выбрать умения ▾"
	menu.tooltip_text = "\n".join(names)
	_ability_summaries[key].text = " · ".join(names) if not names.is_empty() else "Не выбрано"


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


func _save() -> void:
	var error := UnitLibrary.save_document(_document)
	if not error.is_empty():
		EditorUi.set_status(_status, "Не сохранено: " + error, EditorUi.Severity.ERROR)
		return
	_saved = _document.duplicate(true)
	_refresh_state()
	_refresh_list()
	EditorUi.set_status(_status, "Сохранено: %s" % ProjectSettings.globalize_path(_path_for(_document)), EditorUi.Severity.OK)
	unit_saved.emit()


func _copy_document() -> void:
	var copy := _document.duplicate(true)
	copy.id = UnitLibrary.new_document().id
	copy.name = String(copy.name).left(110) + " — копия"
	_request(func() -> void:
		_set_document(copy)
		_saved = {}
		_refresh_state()
		EditorUi.set_status(_status, "Копия создана; сохраните её как отдельного юнита.")
	)


func _select_file(index: int) -> void:
	var path: String = _list.get_item_metadata(index)
	# Restore the highlight of the open unit until a replacement is confirmed.
	_refresh_list()
	if path == _path_for(_document):
		return
	_request(func() -> void:
		var result := UnitLibrary.read_document(path, _skills)
		if not result.has("document"):
			EditorUi.set_status(_status, result.error, EditorUi.Severity.ERROR)
			return
		_set_document(result.document)
		if String(result.error).is_empty():
			EditorUi.set_status(_status, "Открыт: %s" % path)
		else:
			EditorUi.set_status(_status, "Открыт с ошибкой ссылок: исправьте умения и сохраните. " + result.error, EditorUi.Severity.WARN)
	)


func _refresh_list() -> void:
	_list.clear()
	var filter := _search.text.strip_edges().to_lower()
	var entries: Array[Dictionary] = []
	var broken := 0
	for filename: String in DirAccess.get_files_at(UnitLibrary.UNITS):
		if filename.get_extension().to_lower() != "json":
			continue
		var path := UnitLibrary.UNITS.path_join(filename)
		var result := UnitLibrary.read_document(path, _skills)
		var error := String(result.error)
		var readable: bool = result.has("document")
		broken += int(not error.is_empty())
		entries.append({
			"path": path, "error": error,
			"title": String(result.document.name) if readable else filename,
			"id": String(result.document.id) if readable else "",
			"image": String(result.document.image) if readable else "",
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.title).naturalnocasecmp_to(String(b.title)) < 0)
	var current := _path_for(_document)
	for entry: Dictionary in entries:
		if not filter.is_empty() and not (String(entry.title) + " " + String(entry.id)).to_lower().contains(filter):
			continue
		var broken_entry := not String(entry.error).is_empty()
		var index := _list.add_item(("⚠ " if broken_entry else "") + String(entry.title), UnitLibrary.texture_for(entry.image))
		_list.set_item_metadata(index, entry.path)
		_list.set_item_tooltip(index, String(entry.error) if broken_entry else "%s\n%s" % [entry.id, entry.path])
		if broken_entry:
			_list.set_item_custom_fg_color(index, EditorUi.ERROR)
		if entry.path == current:
			_list.select(index)
	_library_count.text = "Юнитов: %d%s" % [entries.size(), " · с ошибками: %d" % broken if broken > 0 else ""]


func _refresh_assets() -> void:
	_assets.clear()
	for filename: String in UnitLibrary.asset_names():
		_assets.add_icon_item(UnitLibrary.texture_for(filename), filename)


func _refresh() -> void:
	_skills = SkillLibrary.catalog()
	_preview_asset = ""
	_refresh_assets()
	_fill_ability_menus()
	_render()
	_refresh_list()
	EditorUi.set_status(_status, "Списки юнитов, изображений и навыков перечитаны с диска.")


func _request(action: Callable) -> void:
	if _document != _saved:
		_pending = action
		_confirm.popup_centered()
	else:
		action.call()


func _open_folder(path: String) -> void:
	var error := OS.shell_open(ProjectSettings.globalize_path(path))
	if error != OK:
		EditorUi.set_status(_status, "Не удалось открыть папку: %s" % error_string(error), EditorUi.Severity.ERROR)


func _leave() -> void:
	if embedded:
		closed.emit()
		queue_free()
	else:
		get_tree().quit()


func _path_for(data: Dictionary) -> String:
	return UnitLibrary.UNITS.path_join(String(data.get("id", "")).trim_prefix("custom_units:") + ".json")
