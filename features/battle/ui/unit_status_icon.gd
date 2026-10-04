class_name UnitStatusIcon
extends TextureRect

func _make_custom_tooltip(for_text: String) -> Object:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("191f25")
	style.border_color = Color("a99b79")
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	style.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.custom_minimum_size.x = 310
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.text = for_text
	panel.add_child(label)
	return panel
