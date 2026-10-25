class_name EditorToolBar
extends HBoxContainer
## Toggle buttons of the map tools with single-key shortcuts. Shows the active tool only.

signal tool_selected(tool: EditorBattleView.Tool)

## Tool, caption, shortcut key, mouse help.
const TOOLS := [
	[EditorBattleView.Tool.SELECT, "Выбор", KEY_V, "ЛКМ — выбрать гекс или юнита; перетащите юнита, чтобы переместить. ПКМ — удалить юнита или препятствие."],
	[EditorBattleView.Tool.PLACE_UNIT, "Юниты", KEY_U, "Выберите тип справа, ЛКМ по свободному гексу ставит юнита. ПКМ удаляет юнита."],
	[EditorBattleView.Tool.PAINT_STATE, "Состояния", KEY_B, "Выберите состояние справа. ЛКМ с протягиванием наносит, ПКМ стирает."],
	[EditorBattleView.Tool.ERASE_STATE, "Ластик", KEY_E, "ЛКМ с протягиванием стирает состояния гексов."],
	[EditorBattleView.Tool.ADD_HEX, "+ Гексы", KEY_A, "ЛКМ с протягиванием восстанавливает клетки рамки 18×12 с параметрами кисти."],
	[EditorBattleView.Tool.REMOVE_HEX, "− Гексы", KEY_D, "ЛКМ с протягиванием удаляет клетки. Занятые клетки сначала освободите."],
	[EditorBattleView.Tool.PAINT_TERRAIN, "Поверхность", KEY_T, "ЛКМ с протягиванием назначает ID поверхности из панели справа."],
	[EditorBattleView.Tool.PAINT_COST, "Стоимость", KEY_C, "ЛКМ с протягиванием назначает стоимость движения. На клетке с состоянием стоимость задаёт состояние."],
	[EditorBattleView.Tool.PAINT_OBSTACLE, "Препятствия", KEY_O, "ЛКМ ставит препятствие целиком, ПКМ удаляет. Подсветка показывает занимаемые гексы."],
]

var _buttons: Dictionary[int, Button] = {}


func _init() -> void:
	add_theme_constant_override("separation", 4)
	var group := ButtonGroup.new()
	for entry: Array in TOOLS:
		var tool: EditorBattleView.Tool = entry[0]
		var button := Button.new()
		button.name = "Tool%d" % tool
		button.text = "%s  %s" % [entry[1], OS.get_keycode_string(entry[2])]
		button.theme_type_variation = &"ToolButton"
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = entry[3]
		button.shortcut = EditorUi.shortcut(entry[2])
		button.shortcut_in_tooltip = true
		button.pressed.connect(func() -> void: tool_selected.emit(tool))
		_buttons[tool] = button
		add_child(button)
	_buttons[EditorBattleView.Tool.SELECT].button_pressed = true


## Silent selection; set_pressed_no_signal() alone does not release the other buttons of a group.
func select(tool: EditorBattleView.Tool) -> void:
	for key: int in _buttons:
		_buttons[key].set_pressed_no_signal(key == tool)


func selected() -> EditorBattleView.Tool:
	for key: int in _buttons:
		if _buttons[key].button_pressed:
			return key as EditorBattleView.Tool
	return EditorBattleView.Tool.SELECT


func tool_count() -> int:
	return _buttons.size()


static func caption(tool: EditorBattleView.Tool) -> String:
	for entry: Array in TOOLS:
		if entry[0] == tool:
			return entry[1]
	return ""


static func help(tool: EditorBattleView.Tool) -> String:
	for entry: Array in TOOLS:
		if entry[0] == tool:
			return entry[3]
	return ""
