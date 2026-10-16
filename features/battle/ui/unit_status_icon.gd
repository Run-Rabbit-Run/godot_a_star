class_name UnitStatusIcon
extends TextureRect

func _make_custom_tooltip(for_text: String) -> Object:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", BattleVisualTheme.panel())
	var label := Label.new()
	label.custom_minimum_size.x = 310
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", BattleVisualTheme.IVORY)
	label.text = for_text
	panel.add_child(label)
	return panel
