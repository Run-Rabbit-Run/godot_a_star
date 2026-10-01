class_name UILayoutInspector
extends VBoxContainer
## Property form emits edits; it never owns document state.

signal applied(id: String, properties: Dictionary)
signal reset_requested(id: String)
signal asset_requested

var element_id := ""
var _fields: Dictionary = {}
var _properties: Dictionary = {}
var _asset: LineEdit
var _initial: Dictionary = {}


func inspect(id: String, presenter: UILayoutPresenter, document: UILayoutDocument) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_fields.clear()
	_initial.clear()
	element_id = id
	if id.is_empty() or presenter == null or not presenter.controls.has(id):
		_label("Выбери блок на холсте или в дереве.")
		return
	var node: Control = presenter.controls[id]
	_properties = document.elements.get(id, {}).duplicate(true)
	_label(id.get_file(), 22)
	_label(id + "\n" + node.get_class())
	_label("Положение относительно родителя · px")
	var rect := presenter.local_rect(id)
	_number("X", rect.position.x, -20000, 20000)
	_number("Y", rect.position.y, -20000, 20000)
	_number("Ширина", rect.size.x, 8, 20000)
	_number("Высота", rect.size.y, 8, 20000)
	_label("Минимальный размер ограничен содержимым.")
	if node is Label or node is Button:
		_label("Текст · {value} = данные боя")
		var text := TextEdit.new()
		text.custom_minimum_size.y = 90
		text.text = _properties.get("text", "{value}")
		add_child(text)
		_fields.text = text
		_label("Сейчас: " + node.text)
		_number("Шрифт", _properties.get("font_size", node.get_theme_font_size("font_size")), 1, 256)
		_color("font_color", "Цвет текста", node.get_theme_color("font_color"))
	_color("tint", "Тонировка / прозрачность", node.self_modulate)
	var style := node.get_theme_stylebox("panel" if node is PanelContainer or node is Panel else "normal") as StyleBoxFlat
	_color("background", "Фон", style.bg_color if style != null else Color.TRANSPARENT)
	_color("border_color", "Рамка", style.border_color if style != null else Color.WHITE)
	_number("Рамка, px", _properties.get("border_width", style.border_width_left if style != null else 0), 0, 64)
	_label("Изображение / иконка / фон блока")
	_asset = LineEdit.new()
	_asset.text = _properties.get("asset", "")
	_asset.placeholder_text = "Исходный ассет (нет переопределения)"
	_asset.editable = false
	add_child(_asset)
	var asset_row := HBoxContainer.new()
	add_child(asset_row)
	_button(asset_row, "Выбрать…", func(): asset_requested.emit())
	_button(asset_row, "Убрать", func(): _asset.text = ""; _properties.asset = "")
	_label("Видимость")
	var visibility := OptionButton.new()
	for caption: String in ["Управляет бой", "Всегда показывать", "Всегда скрывать"]:
		visibility.add_item(caption)
	visibility.select(["inherit", "show", "hide"].find(_properties.get("visibility", "inherit")))
	add_child(visibility)
	_fields.visibility = visibility
	_button(self, "Применить свойства", _apply)
	_button(self, "Сбросить блок к исходному", func(): reset_requested.emit(element_id))


func set_asset(path: String) -> void:
	if is_instance_valid(_asset):
		_asset.text = path
		_properties.asset = path


func _apply() -> void:
	var result := _properties.duplicate(true)
	var rect := [_fields.X.value, _fields.Y.value, _fields["Ширина"].value, _fields["Высота"].value]
	if result.has("rect") or rect != [_initial.X, _initial.Y, _initial["Ширина"], _initial["Высота"]]:
		result.rect = rect
	if _fields.has("text"):
		if result.has("text") or _fields.text.text != "{value}":
			result.text = _fields.text.text
		if result.has("font_size") or _fields["Шрифт"].value != _initial["Шрифт"]:
			result.font_size = _fields["Шрифт"].value
	for key: String in ["font_color", "background", "border_color", "tint"]:
		if _fields.has(key) and (result.has(key) or _fields[key].color != _initial[key]):
			result[key] = _fields[key].color.to_html()
	if result.has("border_width") or _fields["Рамка, px"].value != _initial["Рамка, px"]:
		result.border_width = _fields["Рамка, px"].value
	result.visibility = ["inherit", "show", "hide"][_fields.visibility.selected]
	applied.emit(element_id, result)


func _label(value: String, font_size: int = 14) -> void:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	add_child(label)


func _number(caption: String, value: float, minimum: float, maximum: float) -> void:
	var row := HBoxContainer.new()
	add_child(row)
	var label := Label.new()
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var field := SpinBox.new()
	field.min_value = minimum
	field.max_value = maximum
	field.value = value
	field.custom_minimum_size.x = 145
	row.add_child(field)
	_fields[caption] = field
	_initial[caption] = field.value


func _color(key: String, caption: String, fallback: Color) -> void:
	var row := HBoxContainer.new()
	add_child(row)
	var label := Label.new()
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var field := ColorPickerButton.new()
	field.custom_minimum_size = Vector2(120, 30)
	field.color = Color(_properties[key]) if _properties.has(key) else fallback
	row.add_child(field)
	_fields[key] = field
	_initial[key] = field.color


func _button(parent: Node, caption: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = caption
	button.pressed.connect(callback)
	parent.add_child(button)
