class_name BattleResultPanel
extends PanelContainer
## Outcome of a finished battle and the player's next step. Reads only the BattleResult.

signal restart_requested
signal quit_requested

const TITLE_COLOR := Color("f4dfac")


static func create(result: BattleResult) -> BattleResultPanel:
	var panel := BattleResultPanel.new()
	panel._build(result)
	return panel


func _build(result: BattleResult) -> void:
	name = "BattleResultPanel"
	custom_minimum_size = Vector2(560, 0)
	add_theme_stylebox_override("panel", BattleVisualTheme.panel(Color.WHITE, 28.0))
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	add_child(content)
	var victory := result.outcome == BattleOutcome.Value.VICTORY
	content.add_child(_label("Title", "ПОБЕДА" if victory else "ПОРАЖЕНИЕ", 40, TITLE_COLOR))
	var objective := result.objective_result.description if result.objective_result != null else ""
	if not objective.is_empty():
		content.add_child(_label("Objective", ("Цель выполнена: %s" if victory else "Цель провалена: %s") % objective, 18, BattleVisualTheme.IVORY))
	var summary := "Раундов: %d\nПотери отряда: %d из %d\nПотери противника: %d из %d" % [
		result.round_number,
		result.defeated.get(BattleFaction.Value.PLAYER, 0), result.participants.get(BattleFaction.Value.PLAYER, 0),
		result.defeated.get(BattleFaction.Value.ENEMY, 0), result.participants.get(BattleFaction.Value.ENEMY, 0),
	]
	content.add_child(_label("Summary", summary, 18, BattleVisualTheme.IVORY))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	content.add_child(buttons)
	buttons.add_child(_button("Restart", "СЫГРАТЬ ЕЩЁ РАЗ", restart_requested.emit))
	buttons.add_child(_button("Quit", "ВЫЙТИ ИЗ ИГРЫ", quit_requested.emit))


func _label(node_name: String, text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(node_name: String, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(220, 48)
	BattleVisualTheme.style_button(button)
	button.pressed.connect(action)
	return button
