extends RefCounted
## Battle editor objective: the command with undo, marks of removed units and the panel.

const BATTLE_PATH := "res://content/authored/battles/first_custom_battle.json"


func run(suite: Node) -> void:
	_check_commands(suite)
	await _check_panel(suite)


func _check_commands(suite: Node) -> void:
	var document := BattleDocumentSerializer.load(BATTLE_PATH)
	var history := EditorCommandHistory.new()
	var objective := document.battle_definition.primary_objective.duplicate(true) as BattleObjectiveDefinition
	objective.type = BattleObjectiveType.Value.SURVIVE_ROUNDS
	objective.rounds = 4
	suite.expect(history.execute(EditCommand.set_objective(objective), document) and document.battle_definition.primary_objective.type == BattleObjectiveType.Value.SURVIVE_ROUNDS, "The objective command sets the battle objective")
	suite.expect(history.undo(document) and document.battle_definition.primary_objective.type == BattleObjectiveType.Value.ELIMINATE_FACTION, "Undo restores the previous objective")
	objective = document.battle_definition.primary_objective.duplicate(true) as BattleObjectiveDefinition
	objective.type = BattleObjectiveType.Value.ELIMINATE_TARGETS
	objective.target_placement_ids = [&"author:placement_3"]
	history.execute(EditCommand.set_objective(objective), document)
	history.execute(EditCommand.remove_placement(&"author:placement_3"), document)
	suite.expect(document.battle_definition.primary_objective.target_placement_ids.is_empty(), "Removing a unit removes its commander mark")


func _check_panel(suite: Node) -> void:
	var editor := (load("res://tools/battles/battle_editor.tscn") as PackedScene).instantiate() as BattleEditorShell
	suite.get_tree().root.add_child(editor)
	await suite.get_tree().process_frame
	await suite.get_tree().process_frame
	var document: BattleDocument = editor.get("_document")
	var panel := (editor.get("_inspector") as BattleEditorInspector).objective_panel
	var description := document.battle_definition.primary_objective.description
	_select_type(panel, BattleObjectiveType.Value.SURVIVE_ROUNDS)
	suite.expect(document.battle_definition.primary_objective.type == BattleObjectiveType.Value.SURVIVE_ROUNDS and document.battle_definition.primary_objective.description == description, "Choosing a type in the panel edits the objective and keeps an authored description")
	_select_type(panel, BattleObjectiveType.Value.ELIMINATE_TARGETS)
	editor.call("_on_placement_selected", &"author:placement_3")
	suite.expect(not panel.commander_check.disabled and panel.protected_check.disabled, "An enemy unit can be a commander, not a protected unit")
	panel.commander_check.button_pressed = true
	suite.expect(document.battle_definition.primary_objective.target_placement_ids == [&"author:placement_3"], "Marking the selected unit makes it a commander")
	editor.call("_on_placement_selected", &"author:placement_2")
	suite.expect(panel.commander_check.disabled and not panel.protected_check.disabled and not panel.commander_check.button_pressed, "A player unit can be protected, not a commander")
	editor.queue_free()
	await suite.get_tree().process_frame


func _select_type(panel: EditorObjectivePanel, type: BattleObjectiveType.Value) -> void:
	for index in range(panel.type_option.item_count):
		if panel.type_option.get_item_metadata(index) == type:
			panel.type_option.select(index)
			panel.type_option.item_selected.emit(index)
