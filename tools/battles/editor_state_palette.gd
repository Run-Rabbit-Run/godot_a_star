class_name EditorStatePalette
extends VBoxContainer
## Hex state brush picker of the map editor. Selection only; painting belongs to the shell.

signal state_selected(state_id: StringName)
signal erase_selected

var _buttons: Dictionary[StringName, Button] = {}
var _eraser: Button


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	_eraser = Button.new()
	_eraser.text = "Ластик слоёв"
	_eraser.toggle_mode = true
	_eraser.button_group = group
	_eraser.tooltip_text = "ЛКМ стирает жидкость и энергию гекса"
	_eraser.pressed.connect(func() -> void: erase_selected.emit())
	add_child(_eraser)
	for layer: HexStateCatalog.Layer in [HexStateCatalog.Layer.LIQUID, HexStateCatalog.Layer.ENERGY]:
		var caption := Label.new()
		caption.text = "Жидкость — новая вытесняет прежнюю" if layer == HexStateCatalog.Layer.LIQUID else "Энергия — ложится поверх жидкости"
		caption.add_theme_font_size_override("font_size", 12)
		add_child(caption)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		add_child(grid)
		for state_id: StringName in HexStateCatalog.RULES:
			if HexStateCatalog.layer_of(state_id) == layer:
				grid.add_child(_state_button(state_id, group))


func _state_button(state_id: StringName, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.text = HexStateCatalog.get_display_name(state_id)
	button.icon = HexStateArt.texture(state_id)
	button.expand_icon = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.add_theme_constant_override("icon_max_width", 38)
	button.custom_minimum_size = Vector2(0, 44)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 13)
	button.toggle_mode = true
	button.button_group = group
	button.tooltip_text = "%s
%s" % [button.text, HexStateCatalog.description(state_id)]
	button.pressed.connect(func() -> void: state_selected.emit(state_id))
	_buttons[state_id] = button
	return button


## Mirrors the active brush when it was chosen elsewhere (tool bar or shortcut).
func show_brush(state_id: StringName, erasing: bool) -> void:
	_eraser.set_pressed_no_signal(erasing)
	for id: StringName in _buttons:
		_buttons[id].set_pressed_no_signal(not erasing and id == state_id)
