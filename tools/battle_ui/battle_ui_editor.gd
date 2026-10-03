extends Control
## Composes UI authoring, command history, file dialogs and trial battle.

@export_file("*.json") var initial_profile_path := ""

var _document := UILayoutDocument.new()
var _saved_data: Dictionary = {}
var _path := ""
var _undo: Array[UILayoutEditCommand] = []
var _redo: Array[UILayoutEditCommand] = []
var _canvas: UILayoutCanvas
var _inspector: UILayoutInspector
var _tree: Tree
var _status: Label
var _title: LineEdit
var _workbench: VBoxContainer
var _file_dialog: FileDialog
var _asset_dialog: FileDialog
var _confirm: ConfirmationDialog
var _pending: Callable
var _trial: Node
var _trial_bar: CanvasLayer
var _selecting := false
var _activate_after_save := false


func _ready() -> void:
	get_tree().auto_accept_quit = false
	get_tree().root.close_requested.connect(_on_close)
	_build()
	var initial_path := initial_profile_path if not initial_profile_path.is_empty() else UILayoutStore.selected_path()
	if not initial_path.is_empty():
		var result := UILayoutStore.load_document(initial_path)
		if result.error.is_empty():
			_document = result.document
			_path = initial_path
			_title.text = _document.title
		else:
			push_warning(result.error)
	_saved_data = _document.to_data()
	_canvas.display(_document)
	_status.text = "Выбери блок. Перетаскивание — ЛКМ, размер — края и углы. Ctrl+S · Ctrl+Z · Ctrl+Y."


func _build() -> void:
	var background := ColorRect.new()
	background.color = Color("202630")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_workbench = VBoxContainer.new()
	_workbench.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_workbench.add_theme_constant_override("separation", 8)
	add_child(_workbench)
	var toolbar := HBoxContainer.new()
	_workbench.add_child(toolbar)
	_button(toolbar, "Новый", func(): _guard(_new_document))
	_button(toolbar, "Открыть…", func(): _guard(_open_dialog))
	_button(toolbar, "Пример", func(): _guard(_open_example))
	_button(toolbar, "Сохранить", _save)
	_button(toolbar, "Сохранить как…", _save_as)
	_button(toolbar, "↶ Отмена", _undo_edit)
	_button(toolbar, "↷ Повтор", _redo_edit)
	_button(toolbar, "Пробный бой", _start_trial)
	_button(toolbar, "Вписать", func(): _canvas.fit())
	_button(toolbar, "1:1", func(): _canvas.actual_size())
	var options := HBoxContainer.new()
	_workbench.add_child(options)
	_title = LineEdit.new()
	_title.placeholder_text = "Название варианта UI"
	_title.text = _document.title
	_title.custom_minimum_size.x = 280
	_title.text_changed.connect(func(value: String): _document.title = value)
	options.add_child(_title)
	_button(options, "Использовать в боях", _activate)
	_button(options, "Вернуть стандартный UI", _deactivate)
	_check(options, "Показать цель", func(value: bool): _canvas.show_target = value; _refresh())
	_check(options, "Показать настройки", func(value: bool): _canvas.show_settings = value; _refresh())
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_workbench.add_child(split)
	_tree = Tree.new()
	_tree.custom_minimum_size.x = 270
	_tree.hide_root = true
	_tree.item_selected.connect(_tree_selected)
	split.add_child(_tree)
	var right := HSplitContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	_canvas = UILayoutCanvas.new()
	_canvas.selected_id = "ActiveUnitPanel"
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.selected.connect(_select)
	_canvas.edited.connect(_edit)
	_canvas.rebuilt.connect(_preview_ready)
	_canvas.gesture_cancelled.connect(_refresh)
	right.add_child(_canvas)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 350
	right.add_child(scroll)
	_inspector = UILayoutInspector.new()
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector.add_theme_constant_override("separation", 7)
	_inspector.applied.connect(_edit)
	_inspector.reset_requested.connect(func(id: String): _edit(id, {}))
	_inspector.asset_requested.connect(func(): _asset_dialog.popup_centered_ratio(0.75))
	scroll.add_child(_inspector)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 42
	_workbench.add_child(_status)
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.json ; Варианты UI"])
	_file_dialog.file_selected.connect(_file_selected)
	_file_dialog.canceled.connect(func(): _activate_after_save = false)
	add_child(_file_dialog)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(UILayoutStore.DIRECTORY))
	_file_dialog.current_dir = ProjectSettings.globalize_path(UILayoutStore.DIRECTORY)
	_asset_dialog = FileDialog.new()
	_asset_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_asset_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_asset_dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp,*.svg ; Изображения"])
	_asset_dialog.file_selected.connect(_import_asset)
	add_child(_asset_dialog)
	_confirm = ConfirmationDialog.new()
	_confirm.dialog_text = "Есть несохранённые изменения. Продолжить без сохранения?"
	_confirm.ok_button_text = "Не сохранять"
	_confirm.confirmed.connect(func(): _pending.call())
	add_child(_confirm)


func _preview_ready() -> void:
	_selecting = true
	_tree.clear()
	var root := _tree.create_item()
	var items: Dictionary = {"": root}
	for id: String in _canvas.presenter.controls:
		var parent_id := id.get_base_dir()
		var item := _tree.create_item(items.get(parent_id, root))
		items[id] = item
		var control: Control = _canvas.presenter.controls[id]
		item.set_text(0, ("● " if _document.elements.has(id) else "") + id.get_file() + (" [скрыт]" if not control.is_visible_in_tree() else ""))
		item.set_metadata(0, id)
		item.collapsed = not _canvas.selected_id.begins_with(id + "/")
		if id == _canvas.selected_id:
			item.select(0)
	_selecting = false
	_inspector.inspect(_canvas.selected_id, _canvas.presenter, _document)
	if not _canvas.presenter.diagnostics.is_empty():
		_status.text = "\n".join(_canvas.presenter.diagnostics)


func _tree_selected() -> void:
	if not _selecting and _tree.get_selected() != null:
		_select(str(_tree.get_selected().get_metadata(0)))


func _select(id: String) -> void:
	_canvas.selected_id = id
	_inspector.inspect(id, _canvas.presenter, _document)


func _edit(id: String, properties: Dictionary) -> void:
	if id.is_empty() or properties == _document.elements.get(id, {}):
		return
	var command := UILayoutEditCommand.new()
	command.element_id = id
	command.before = _document.elements.get(id, {}).duplicate(true)
	command.after = properties.duplicate(true)
	command.apply(_document)
	_undo.append(command)
	if _undo.size() > 100:
		_undo.pop_front()
	_redo.clear()
	_refresh()
	_status.text = "Изменён %s · не сохранено" % id.get_file()


func _undo_edit() -> void:
	if _undo.is_empty():
		return
	var command: UILayoutEditCommand = _undo.pop_back()
	command.revert(_document)
	_redo.append(command)
	_refresh()


func _redo_edit() -> void:
	if _redo.is_empty():
		return
	var command: UILayoutEditCommand = _redo.pop_back()
	command.apply(_document)
	_undo.append(command)
	_refresh()


func _refresh() -> void:
	_canvas.display(_document)


func _guard(action: Callable) -> void:
	if _document.to_data() == _saved_data:
		action.call()
	else:
		_pending = action
		_confirm.popup_centered()


func _new_document() -> void:
	_document = UILayoutDocument.new()
	_path = ""
	_loaded()


func _open_example() -> void:
	var result := UILayoutStore.load_document("res://content/authored/ui/compact.json")
	if not result.error.is_empty():
		_status.text = result.error
		return
	_document = result.document
	_path = ""
	_loaded()
	_status.text = "Пример «Командная панель снизу». Сохранение создаст собственный файл."


func _loaded() -> void:
	_saved_data = _document.to_data()
	_undo.clear()
	_redo.clear()
	_title.text = _document.title
	_canvas.selected_id = "ActiveUnitPanel"
	_refresh()
	_status.text = "Открыт: " + (ProjectSettings.globalize_path(_path) if not _path.is_empty() else "стандартный UI")


func _open_dialog() -> void:
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.popup_centered_ratio(0.75)


func _save() -> void:
	if _path.is_empty():
		_save_as()
	else:
		_write(_path)


func _save_as() -> void:
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.current_file = "battle_ui.json" if _path.is_empty() else _path.get_file()
	_file_dialog.popup_centered_ratio(0.75)


func _file_selected(path: String) -> void:
	if _file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
		var written := _write(path if path.ends_with(".json") else path + ".json")
		if written and _activate_after_save:
			_assign_profile()
		_activate_after_save = false
		return
	var result := UILayoutStore.load_document(path)
	if not result.error.is_empty():
		_status.text = result.error
		return
	_document = result.document
	_path = path
	_loaded()


func _write(path: String) -> bool:
	var error := UILayoutStore.save_document(path, _document)
	if not error.is_empty():
		_status.text = error
		return false
	_path = path
	_saved_data = _document.to_data()
	_status.text = "Сохранено: " + ProjectSettings.globalize_path(path)
	return true


func _activate() -> void:
	if _path.is_empty():
		_status.text = "Выбери имя файла — после сохранения UI будет назначен для боёв."
		_activate_after_save = true
		_save_as()
		return
	if not _write(_path):
		return
	_assign_profile()


func _assign_profile() -> void:
	var error := UILayoutStore.select_profile(_path)
	_status.text = "Стартовый UI игры: " + ProjectSettings.globalize_path(_path) if error == OK else "Сохрани UI внутри content/: " + error_string(error)


func _deactivate() -> void:
	var error := UILayoutStore.select_profile("")
	_status.text = "В следующих боях — стандартный UI." if error == OK else error_string(error)


func _import_asset(path: String) -> void:
	var result := UILayoutStore.import_asset(path)
	if not result.error.is_empty():
		_status.text = result.error
		return
	_inspector.set_asset(result.path)
	_status.text = "Изображение скопировано. Нажми «Применить свойства»."


func _start_trial() -> void:
	var settings := GameContentSettings.read()
	if settings == null:
		_status.text = "Не удалось прочитать content/game_content.tres."
		return
	var result := ProjectBattleLoader.load_battle(settings.content_packages, settings.battle_document_path, 1)
	if result.request == null:
		_status.text = result.error_message
		return
	var screen := load("res://features/battle/battle_screen.tscn").instantiate() as BattleScreen
	var hud := screen.get_node("BattleMap/BattleUI") as BattleHUD
	hud.ui_document_override = _document.copy()
	if not screen.setup(result.request):
		_status.text = screen.initialization_error
		screen.free()
		return
	_trial = screen
	_workbench.hide()
	add_child(_trial)
	_trial_bar = CanvasLayer.new()
	_trial_bar.layer = 120
	add_child(_trial_bar)
	var button := Button.new()
	button.position = Vector2(20, 110)
	button.text = "← Вернуться в редактор UI"
	button.pressed.connect(_end_trial)
	_trial_bar.add_child(button)


func _end_trial() -> void:
	_trial.queue_free()
	_trial = null
	_trial_bar.queue_free()
	_workbench.show()


func _on_close() -> void:
	_guard(func(): get_tree().quit())


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or _trial != null:
		return
	if event.ctrl_pressed:
		match event.keycode:
			KEY_S: _save()
			KEY_Z: _undo_edit()
			KEY_Y: _redo_edit()


func _button(parent: Node, caption: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = caption
	button.pressed.connect(callback)
	parent.add_child(button)


func _check(parent: Node, caption: String, callback: Callable) -> void:
	var check := CheckButton.new()
	check.text = caption
	check.toggled.connect(callback)
	parent.add_child(check)
