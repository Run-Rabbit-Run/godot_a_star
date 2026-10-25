class_name EditorGridLayoutControls
extends VBoxContainer

signal offset_changed(value: int, custom: bool)
signal default_saved(value: int)
signal save_failed(message: String)

var settings_path := BattleGridLayoutSettings.DEFAULT_PATH
var default_offset_y := 0
var _height: SpinBox
var _summary: Label
var _map: BattleMapDefinition


func _ready() -> void:
	var title := Label.new()
	title.text = "Высота гексагональной сетки"
	add_child(title)
	var row := HBoxContainer.new()
	add_child(row)
	_height = SpinBox.new()
	_height.min_value = BattleMapDefinition.MIN_GRID_OFFSET_Y
	_height.max_value = BattleMapDefinition.MAX_GRID_OFFSET_Y
	_height.step = 1
	_height.suffix = "px"
	_height.tooltip_text = "Смещение на холсте 1920×1080: минус — вверх, плюс — вниз. Фон остаётся на месте."
	_height.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_height.value_changed.connect(func(value: float) -> void: offset_changed.emit(int(value), true))
	row.add_child(_height)
	for entry: Array in [["Выше", -10], ["Ниже", 10]]:
		var button := Button.new()
		button.text = entry[0]
		var delta: int = entry[1]
		button.pressed.connect(func() -> void: _height.value += delta)
		row.add_child(button)
	var save := Button.new()
	save.name = "SaveDefaultHeight"
	save.text = "Сделать высотой по умолчанию"
	save.pressed.connect(_save_default)
	add_child(save)
	var inherit := Button.new()
	inherit.name = "UseDefaultHeight"
	inherit.text = "Использовать высоту по умолчанию"
	inherit.pressed.connect(func() -> void: offset_changed.emit(default_offset_y, false))
	add_child(inherit)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)
	sync(_map)


func sync(map: BattleMapDefinition) -> void:
	_map = map
	default_offset_y = BattleGridLayoutSettings.load_default(settings_path)
	if _height == null:
		return
	_height.set_value_no_signal(BattleGridLayoutSettings.resolve_offset(map, default_offset_y) if map != null else default_offset_y)
	var source := "Своя высота" if map != null and map.has_custom_grid_offset else "Общая высота"
	_summary.text = "%s · по умолчанию: %d px" % [source, default_offset_y]


func _save_default() -> void:
	var value := int(_height.value)
	var error := BattleGridLayoutSettings.save_default(value, settings_path)
	if error != OK:
		save_failed.emit("Не удалось сохранить высоту по умолчанию: %s" % error_string(error))
		return
	sync(_map)
	default_saved.emit(value)
