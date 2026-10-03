class_name EditorStatePalette
extends PanelContainer

signal state_selected(state_id: StringName)
signal erase_selected

func _ready() -> void:
	var root := VBoxContainer.new()
	add_child(root)
	var heading := HBoxContainer.new()
	root.add_child(heading)
	var label := Label.new()
	label.text = "  СОСТОЯНИЯ ГЕКСОВ · RIM     ЛКМ — нанести · ПКМ — стереть"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(label)
	var erase := Button.new()
	erase.text = "Ластик состояния"
	erase.pressed.connect(func() -> void: erase_selected.emit())
	heading.add_child(erase)
	var grid := GridContainer.new()
	grid.columns = 6
	root.add_child(grid)
	var group := ButtonGroup.new()
	for state_id: StringName in HexStateCatalog.RULES:
		var button := Button.new()
		button.text = HexStateCatalog.get_display_name(state_id)
		button.icon = HexStateArt.texture(state_id)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 46)
		button.custom_minimum_size.y = 51
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 12)
		button.toggle_mode = true
		button.button_group = group
		button.tooltip_text = button.text + " · выбрать и нажать на гекс"
		button.pressed.connect(func() -> void: state_selected.emit(state_id))
		grid.add_child(button)
