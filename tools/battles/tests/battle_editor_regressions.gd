extends RefCounted
## Battle editor: unsaved-document guard, embedded unit editor, trial errors and obstacle editing.


func run(suite: Node) -> void:
	await _check_document_guard(suite)
	await _check_embedded_editors(suite)
	_check_obstacle_commands(suite)
	await _check_obstacle_brush(suite)


func _check_document_guard(suite: Node) -> void:
	var editor := (load("res://tools/battles/battle_editor.tscn") as PackedScene).instantiate() as BattleEditorShell
	suite.get_tree().root.add_child(editor)
	await suite.get_tree().process_frame
	await suite.get_tree().process_frame
	var document: BattleDocument = editor.get("_document")
	suite.expect(document != null, "Editor loads configured document")
	if document != null:
		suite.expect(not editor.has_unsaved_changes(), "Loaded editor document is clean")
		var original_name := document.battle_definition.primary_objective.description
		document.battle_definition.primary_objective.description = "Unsaved change"
		var called := [false]
		editor.call("_guard_discard", func() -> void: called[0] = true)
		suite.expect(not called[0] and editor.has_unsaved_changes(), "Unsaved document is not replaced before confirmation")
		editor.call("_confirm_discard")
		suite.expect(called[0], "Confirmed discard executes pending action")
		document.battle_definition.primary_objective.description = original_name
		var occupied := document.battle_definition.unit_placements[0].start_hex
		editor.call("_select_hex", occupied)
		(editor.get("_traversable_check") as CheckButton).button_pressed = false
		editor.call("_apply_selected_hex")
		suite.expect((editor.call("_find_cell", occupied) as BattleMapCellDefinition).traversable, "Editor cannot block occupied cell")
		editor.set("_document", null)
		(editor.get("_side_option") as OptionButton).clear()
		editor.call("_reload_unit_library")
		suite.expect((editor.get("_side_option") as OptionButton).item_count > 0, "Recovery populates sides")
		var settings := GameContentSettings.read()
		var expected := BattleDocumentSerializer.load_result(settings.battle_document_path).document
		suite.expect((editor.get("_document") as BattleDocument).document_id == expected.document_id, "Recovery loads configured document rather than debug battle")
	editor.queue_free()
	await suite.get_tree().process_frame


func _check_embedded_editors(suite: Node) -> void:
	var editor := (load("res://tools/battles/battle_editor.tscn") as PackedScene).instantiate() as BattleEditorShell
	suite.get_tree().root.add_child(editor)
	await suite.get_tree().process_frame
	await suite.get_tree().process_frame
	var document: BattleDocument = editor.get("_document")
	suite.expect(document != null, "Editor loads configured document for review checks")
	if document == null:
		editor.queue_free()
		await suite.get_tree().process_frame
		return

	var view := editor.get("_view") as EditorBattleView
	var definition_id := document.battle_definition.unit_placements[0].definition_id
	var presentation: UnitPresentationDefinition = view.call("_presentation_for", definition_id)
	suite.expect(presentation != null and view.call("_presentation_for", definition_id) == presentation, "Editor drawing resolves presentations once per snapshot")

	editor.call("_open_unit_editor")
	await suite.get_tree().process_frame
	var unit_editor := editor.get("_unit_editor") as UnitEditor
	suite.expect(unit_editor != null, "Battle editor tracks the embedded unit editor")
	if unit_editor != null:
		var draft: Dictionary = unit_editor.get("_document")
		draft["name"] = "Unsaved review draft"
		var unit_confirm := unit_editor.get("_confirm") as ConfirmationDialog
		unit_editor.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		suite.expect(not unit_confirm.visible, "Embedded unit editor leaves window closing to its host")
		editor.request_quit()
		suite.expect(unit_confirm.visible and not (editor.get("_discard_dialog") as ConfirmationDialog).visible, "Closing the window asks the embedded unit editor first")
		unit_confirm.hide()
		unit_editor.set("_pending", Callable())
		unit_editor.set("_document", (unit_editor.get("_saved") as Dictionary).duplicate(true))
		unit_editor.call("_leave")
		await suite.get_tree().process_frame
		suite.expect(editor.get("_unit_editor") == null, "Closed unit editor is released")

	editor.call("_start_trial")
	var runner := editor.get("_trial") as EditorTrialRunner
	var trial := runner.screen
	suite.expect(trial != null, "Trial starts from the configured document")
	if trial != null:
		if not trial.has_started():
			await trial.battle_started
		trial.battle_failed.emit("Injected runtime failure")
		var layer := runner.return_layer
		suite.expect(runner.screen == trial and layer != null and layer.has_node("TrialError"), "Stopped trial stays visible with its error")
		editor.call("_return_from_trial")
		suite.expect((editor.get("_status") as Label).text.contains("остановлен ошибкой"), "Editor status reports the stopped trial")
	var editor_ui := editor.get("_ui") as Control
	editor.call("_start_trial")
	suite.expect(runner.is_running() and not editor_ui.visible, "A running trial covers the editor")
	editor.call("_return_from_trial")
	suite.expect(not runner.is_running() and editor_ui.visible and (editor.get("_status") as Label).text.begins_with("Пробный бой завершён"), "Returning from a trial shows the editor and reports the end")
	editor.queue_free()
	await suite.get_tree().process_frame


## Obstacles are placed, rejected and removed as whole editor commands with undo.
func _check_obstacle_commands(suite: Node) -> void:
	var cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0)]
	var obstacle := BattleObstacleDefinition.new()
	obstacle.id = &"test:obstacle"
	obstacle.max_hp = 5
	obstacle.hexes.assign([Vector2i(1, 0), Vector2i(2, 0)])
	var overlap := obstacle.duplicate(true) as BattleObstacleDefinition
	overlap.id = &"test:overlap"
	var map := BattleMapDefinition.new()
	map.id = &"test:map"
	for hex: Vector2i in cells:
		map.cells.append(BattleMapCellDefinition.new(hex))
	var battle := BattleDefinition.new()
	battle.id = &"test:battle"
	battle.map_id = map.id
	var document := BattleDocument.new(&"test:document", map, battle)
	var history := EditorCommandHistory.new()
	obstacle.destructible = true
	suite.expect(history.execute(EditCommand.put_obstacle(obstacle), document), "Place obstacle through editor command")
	suite.expect(history.undo(document) and document.map_definition.obstacles.is_empty(), "Undo obstacle placement")
	suite.expect(history.redo(document) and document.map_definition.obstacles.size() == 1, "Redo obstacle placement")
	var baseline := BattleDocumentSerializer.to_dictionary(document)
	suite.expect(not history.execute(EditCommand.put_obstacle(overlap), document) and baseline == BattleDocumentSerializer.to_dictionary(document), "Rejected overlap leaves entire document unchanged")
	suite.expect(not history.execute(EditCommand.remove_hex(Vector2i(1, 0)), document), "Editor cannot delete part of obstacle")
	var changed := document.map_definition.cells[1].duplicate(true) as BattleMapCellDefinition
	changed.energy_id = &"core:fire"
	changed.movement_cost = HexStateCatalog.get_movement_cost(changed.liquid_id)
	suite.expect(not history.execute(EditCommand.update_hex(changed), document), "Editor cannot paint state over obstacle")
	suite.expect(history.execute(EditCommand.remove_obstacle(obstacle.id), document), "Delete obstacle as one command")
	suite.expect(history.undo(document) and document.map_definition.obstacles.size() == 1, "Undo restores whole obstacle")


func _check_obstacle_brush(suite: Node) -> void:
	var editor := (load("res://tools/battles/battle_editor.tscn") as PackedScene).instantiate() as BattleEditorShell
	suite.get_tree().root.add_child(editor)
	await suite.get_tree().process_frame
	editor.call("_create_new_document")
	var origin := HexCoordinateMapper.offset_to_axial(Vector2i(4, 4))
	var document: BattleDocument = editor.get("_document")
	editor.call("_paint_state", origin, &"core:fire")
	(editor.get("_obstacle_size") as SpinBox).value = 4
	(editor.get("_obstacle_destructible") as CheckButton).button_pressed = true
	(editor.get("_obstacle_hp") as SpinBox).value = 12
	editor.call("_select_tool", EditorBattleView.Tool.PAINT_OBSTACLE)
	editor.call("_on_hex_activated", origin)
	suite.expect(document.map_definition.obstacles.size() == 1 and document.map_definition.obstacles[0].hexes.size() == 4, "Editor obstacle brush places whole configured footprint")
	suite.expect(not (editor.call("_find_cell", origin) as BattleMapCellDefinition).has_layers(), "Obstacle placement clears painted state")
	editor.call("_undo")
	suite.expect(document.map_definition.obstacles.is_empty() and (editor.call("_find_cell", origin) as BattleMapCellDefinition).energy_id == &"core:fire", "Undo restores state under removed obstacle")
	editor.call("_redo")
	editor.call("_select_hex", origin + Vector2i(2, 0))
	suite.expect((editor.get("_obstacle_size") as SpinBox).value == 4 and (editor.get("_obstacle_hp") as SpinBox).value == 12, "Selecting any occupied hex loads shared obstacle properties")
	(editor.get("_obstacle_size") as SpinBox).value = 2
	editor.call("_apply_selected_obstacle")
	suite.expect(document.map_definition.obstacles[0].hexes.size() == 2 and document.map_definition.obstacles[0].hexes[0] == origin, "Updating obstacle from middle hex preserves its anchor")
	editor.call("_paint_state", origin, &"core:water")
	suite.expect(not (editor.call("_find_cell", origin) as BattleMapCellDefinition).has_layers(), "Editor state brush skips obstacles")
	editor.call("_on_hex_erased", origin + Vector2i(1, 0))
	suite.expect(document.map_definition.obstacles.is_empty(), "Right click deletes whole footprint")
	editor.queue_free()
	await suite.get_tree().process_frame
