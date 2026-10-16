class_name BattleVisualTheme
extends RefCounted
## Shared visual skin. No battle queries, commands, or data mutations.

const PANEL := preload("res://features/battle/ui/art/classic_panel.svg")
const IVORY := Color("eadbb9")
const GOLD := Color("c5a15a")
const MUTED := Color("a99b7e")

static func panel(tint := Color.WHITE, padding := 12.0) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = PANEL
	style.modulate_color = tint
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, 16.0)
		style.set_content_margin(side, padding)
	return style

static func apply_to(root: Control) -> void:
	var theme := Theme.new()
	theme.set_color("font_color", "Label", IVORY)
	theme.set_color("default_color", "RichTextLabel", IVORY)
	theme.set_stylebox("panel", "TooltipPanel", panel())
	theme.set_color("font_color", "TooltipLabel", IVORY)
	theme.set_font_size("font_size", "TooltipLabel", 15)
	root.theme = theme
	for path: String in ["StrategistPanel", "ActiveUnitPanel", "ActionPanel", "TargetPanel", "SpeedPanel", "BattleLogPanel", "SystemPanel"]:
		var container := root.get_node(path) as PanelContainer
		container.add_theme_stylebox_override("panel", panel())
	# Individual queue cards carry the frame, leaving unused queue space clear.
	(root.get_node("TurnQueuePanel") as PanelContainer).add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	for button: BaseButton in root.find_children("*", "BaseButton", true, false):
		style_button(button)
	for path: String in ["ActiveUnitPanel/Content/UnitHeader/Stats/ActiveUnitLabel", "StrategistPanel/Margin/Content/Info/RoundLabel", "TargetPanel/Content/TargetContent/TargetInfo/TargetNameLabel"]:
		var label := root.get_node(path) as Label
		label.add_theme_color_override("font_color", Color("f4dfac"))
	var action_label := root.get_node("ActionLabel") as Label
	action_label.add_theme_color_override("font_outline_color", Color("201a16"))
	action_label.add_theme_constant_override("outline_size", 3)
	action_label.add_theme_color_override("font_color", IVORY)

static func style_button(button: BaseButton) -> void:
	button.add_theme_color_override("font_color", IVORY)
	button.add_theme_color_override("font_hover_color", Color("fff0c2"))
	button.add_theme_color_override("font_pressed_color", Color("fff0c2"))
	button.add_theme_color_override("font_disabled_color", Color("887d69"))
	button.add_theme_color_override("icon_normal_color", Color.WHITE)
	button.add_theme_color_override("icon_disabled_color", Color(0.50, 0.47, 0.41))
	button.add_theme_stylebox_override("normal", panel(Color.WHITE, 9.0))
	button.add_theme_stylebox_override("hover", panel(Color(1.30, 1.23, 1.10), 9.0))
	button.add_theme_stylebox_override("pressed", panel(Color(0.78, 0.72, 0.60), 9.0))
	button.add_theme_stylebox_override("disabled", panel(Color(0.56, 0.54, 0.49), 9.0))
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color("f7d88b")
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(2)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_font_size_override("font_size", 15)
	if button is Button:
		button.add_theme_constant_override("icon_max_width", 28)
		button.add_theme_constant_override("h_separation", 8)
		button.expand_icon = true
