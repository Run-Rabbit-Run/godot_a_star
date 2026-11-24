extends RefCounted

const FIXTURE := "res://features/battle/tests/fixtures/regression_battle.json"
const PLANS := BattleMapDefinition.CameraPlan


func run(suite: Node) -> void:
	var editor := (load("res://tools/battles/battle_editor.tscn") as PackedScene).instantiate() as BattleEditorShell
	suite.get_tree().root.add_child(editor)
	await suite.get_tree().process_frame
	var document := BattleDocumentSerializer.load(FIXTURE)
	_make_small_battle(document)
	editor.call("_replace_document", document, "", true)
	var inspector := editor.get("_inspector") as BattleEditorInspector
	var option := inspector.camera_option
	suite.expect(option.item_count == 3 and option.get_selected_id() == PLANS.FAR, "Legacy fields open with the far camera")
	var original := BattleDocumentSerializer.to_dictionary(document)
	suite.expect(not original["map"].has("camera_plan"), "Default plan is implicit in schema 1")
	option.item_selected.emit(option.get_item_index(PLANS.CLOSE))
	suite.expect(document.map_definition.camera_plan == PLANS.CLOSE and editor.has_unsaved_changes(), "Selecting close edits the draft")
	editor.call("_undo")
	suite.expect(option.get_selected_id() == PLANS.FAR and not editor.has_unsaved_changes(), "Undo restores the original plan and clean state")
	editor.call("_redo")
	suite.expect(option.get_selected_id() == PLANS.CLOSE and editor.has_unsaved_changes(), "Redo restores the planned shot")
	var snapshot := editor.get("_snapshot") as ContentSnapshot
	var expected := document.create_start_request(snapshot, editor.trial_seed)
	suite.expect(expected != null, "The compact unsaved draft is valid")

	editor.call("_start_trial", true)
	var runner := editor.get("_trial") as EditorTrialRunner
	var preview := runner.screen
	suite.expect(preview != null and preview.get_viewport() is SubViewport, "Player view opens the battle scene inside its own viewport")
	if preview != null and expected != null:
		await _check_preview(suite, editor, preview, expected)
	editor.call("_return_from_trial")
	await suite.get_tree().process_frame
	suite.expect(not runner.is_running() and editor.has_unsaved_changes(), "Returning keeps the unsaved camera change")
	editor.call("_undo")
	suite.expect(document.map_definition.camera_plan == PLANS.FAR, "History still works after preview")
	editor.call("_redo")

	var path := "user://battle_camera_%d.json" % OS.get_process_id()
	suite.expect(editor.call("_save_to_path", path), "The editor saves the selected camera")
	var saved := BattleDocumentSerializer.load(path)
	suite.expect(saved != null and saved.map_definition.camera_plan == PLANS.CLOSE, "The selected plan round-trips through JSON")
	var invalid := original.duplicate(true)
	invalid["map"]["camera_plan"] = 3
	suite.expect(BattleDocumentSerializer.from_dictionary(invalid) == null, "Unknown camera plans are rejected")
	document.battle_definition.unit_placements.clear()
	editor.call("_start_trial", true)
	suite.expect(not runner.is_running() and inspector.current_tab == BattleEditorInspector.Page.CHECKS, "An invalid draft opens diagnostics instead of a partial preview")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	editor.queue_free()
	await suite.get_tree().process_frame


func _make_small_battle(document: BattleDocument) -> void:
	document.map_definition.cells.clear()
	document.map_definition.obstacles.clear()
	for row in range(2, 10):
		for column in range(4, 14):
			var hex := HexCoordinateMapper.offset_to_axial(Vector2i(column, row))
			document.map_definition.cells.append(BattleMapCellDefinition.new(hex))
	for index in range(document.battle_definition.unit_placements.size()):
		var placement := document.battle_definition.unit_placements[index]
		placement.start_hex = document.map_definition.cells[index].hex
		placement.ai_profile_override_id = &""
	for side: BattleSideDefinition in document.battle_definition.sides:
		side.control_source = BattleControlSource.Value.AI
		side.ai_profile_id = &"core:basic_enemy_ai"


func _check_preview(suite: Node, editor: BattleEditorShell, preview: BattleScreen, expected: BattleStartRequest) -> void:
	for frame in range(8):
		await suite.get_tree().process_frame
	suite.expect(preview.has_started(), "Player view reaches the normal opening shot")
	var controller := preview.get_node("BattleMap/BattleController") as BattleController
	var session := controller.get("_battle_session") as BattleSession
	var expected_session := BattleSessionFactory.create(expected).session
	suite.expect(session.is_active_unit_ai_controlled() and session.get_state_revision() == expected_session.get_state_revision(), "Player view stays on the opening shot even when the first side is AI")
	suite.expect(preview.get_viewport().gui_disable_input, "The preview viewport cannot send commands")
	var map := preview.get_node("BattleMap") as BattleMapView
	# A regular battle started from the same draft has the same projection, even with AI.
	var normal_viewport := SubViewport.new()
	normal_viewport.size = preview.get_viewport().size
	editor.add_child(normal_viewport)
	var normal := (load("res://features/battle/battle_screen.tscn") as PackedScene).instantiate() as BattleScreen
	normal.setup(expected)
	normal_viewport.add_child(normal)
	await suite.get_tree().process_frame
	var normal_map := normal.get_node("BattleMap") as BattleMapView
	suite.expect(map.scale.is_equal_approx(normal_map.scale) and map.position.is_equal_approx(normal_map.position), "Player view matches the regular battle's camera at the same resolution")
	normal_viewport.queue_free()
	await suite.get_tree().process_frame
