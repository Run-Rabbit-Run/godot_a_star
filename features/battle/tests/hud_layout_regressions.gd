extends RefCounted
## HUD layout: bindings follow unique names, not tree paths, and authored overrides react
## to changes instead of being re-applied every frame.
const HUD_LAYOUT := preload("res://features/battle/ui/battle_hud_layout.tscn")


func run(suite: Node) -> void:
	await _check_bindings_survive_restructuring(suite)
	await _check_overrides_follow_changes(suite)


func _check_bindings_survive_restructuring(suite: Node) -> void:
	var layout := HUD_LAYOUT.instantiate() as Control
	layout.name = "HUDRoot"
	# An author moves a bound label into another panel of the layout scene.
	var round_label := layout.get_node("%RoundLabel") as Label
	var action_column := (layout.get_node("%ActionPanel") as Node).get_child(0)
	# The editor keeps the scene owner of a moved node, so its unique name stays registered.
	round_label.owner = null
	round_label.reparent(action_column)
	round_label.owner = layout
	var hud := BattleHUD.new()
	hud.add_child(layout)
	suite.add_child(hud)
	await _frames(suite, 1)
	hud.show_round(7)
	suite.expect(round_label.get_parent() == action_column and round_label.text == "РАУНД 07", "A moved label stays bound to the HUD")
	var section := Label.new()
	section.name = "ProbeSection"
	hud.add_settings_section(section)
	suite.expect(section.get_parent() == layout.get_node("%SettingsContent"), "Other screen parts add settings through the HUD, not by its paths")
	var outsider := Control.new()
	suite.expect(hud.contains_control(section) and not hud.contains_control(outsider) and not hud.contains_control(null), "The HUD tells which controls belong to it")
	outsider.free()
	hud.queue_free()
	await _frames(suite, 1)


func _check_overrides_follow_changes(suite: Node) -> void:
	var document := UILayoutDocument.new()
	document.elements = {
		"ActionPanel/Content/SkillButtons/EndTurnButton": {"text": "Готово · {value}"},
		"TargetPanel": {"visibility": "hide"},
		"ActiveUnitPanel": {"rect": [100, 200, 300, 150]},
	}
	var hud := BattleHUD.new()
	hud.ui_document_override = document
	suite.add_child(hud)
	await _frames(suite, 3)
	var presenter := hud.layout_presenter
	var end_turn := hud.get_node("HUDRoot/%EndTurnButton") as Button
	var target_panel := hud.get_node("HUDRoot/%TargetPanel") as Control
	var unit_panel := hud.get_node("HUDRoot/%ActiveUnitPanel") as Control
	var hud_root := hud.get_node("HUDRoot") as Control
	suite.expect(end_turn.text == "Готово · Защита" and not target_panel.visible, "Overrides apply when the HUD mounts its profile")
	suite.expect(not presenter.is_processing(), "An idle HUD layout does no per-frame work")
	end_turn.text = "Пас"
	await _frames(suite, 2)
	suite.expect(end_turn.text == "Готово · Пас", "A HUD text change is formatted by its template")
	hud.show_target("Страж", null, "Противник", 60, 100, 12, 1, 3, 5, true)
	await _frames(suite, 2)
	suite.expect(not target_panel.visible, "A HUD visibility change yields to the hidden override")
	hud_root.position += Vector2(40, 0)
	await _frames(suite, 2)
	suite.expect(unit_panel.global_position.is_equal_approx(hud_root.get_global_transform() * Vector2(100, 200)), "A detached control follows its moved parent")
	await _frames(suite, 3)
	suite.expect(not presenter.is_processing(), "The layout settles after the changes")
	hud.queue_free()
	await _frames(suite, 1)


func _frames(suite: Node, count: int) -> void:
	for _index in range(count):
		await suite.get_tree().process_frame
