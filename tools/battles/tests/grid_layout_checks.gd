extends RefCounted

const FIXTURE := "res://features/battle/tests/fixtures/regression_battle.json"


func run(editor: BattleEditorShell, expect: Callable) -> void:
	var path := "user://grid_layout_%d.cfg" % OS.get_process_id()
	var json_path := "user://grid_layout_%d.json" % OS.get_process_id()
	expect.call(BattleGridLayoutSettings.load_default(path) == 0, "Missing grid defaults keep the original height")
	expect.call(BattleGridLayoutSettings.save_default(0, path) == OK, "Grid defaults can be written to a test-only path")
	var controls: EditorGridLayoutControls = editor.get("_grid_layout_controls")
	controls.settings_path = path
	var document := BattleDocumentSerializer.load(FIXTURE)
	var original := BattleDocumentSerializer.to_dictionary(document)
	expect.call(not document.map_definition.has_custom_grid_offset and not original["map"].has("grid_offset_y"), "Old documents inherit the default without adding an override")
	editor.call("_replace_document", document, "", true)
	var view: EditorBattleView = editor.get("_view")
	var height: SpinBox = controls.get("_height")
	var hex := document.map_definition.cells[0].hex
	var center: Vector2 = view.call("_hex_center", hex)
	height.value = 96
	expect.call(document.map_definition.grid_offset_y == 96 and document.map_definition.has_custom_grid_offset, "Height control updates the document through a command")
	expect.call(editor.has_unsaved_changes(), "Moving the board marks the document as changed")
	expect.call(view.call("_hex_center", hex) == center + Vector2(0, 96), "Editor grid moves down by the requested canvas pixels")
	var picks_match := true
	for cell: BattleMapCellDefinition in document.map_definition.cells:
		picks_match = picks_match and view.screen_position_to_hex(view.to_global(view.call("_hex_center", cell.hex))) == cell.hex
	expect.call(picks_match, "All shifted cells still map cursor coordinates to their logical hexes")
	var shifted := BattleDocumentSerializer.to_dictionary(document)
	expect.call(shifted["map"]["cells"] == original["map"]["cells"] and shifted["battle"] == original["battle"], "Moving the grid preserves cells, placements and combat data")
	var copy := document.duplicate_document()
	copy.map_definition.grid_offset_y = -40
	expect.call(document.map_definition.grid_offset_y == 96 and copy.map_definition.has_custom_grid_offset, "Detached documents preserve and isolate the grid offset")
	expect.call(editor.call("_save_to_path", json_path), "Document saves its individual grid height")
	var reopened := BattleDocumentSerializer.load(json_path)
	expect.call(reopened.map_definition.grid_offset_y == 96 and reopened.map_definition.has_custom_grid_offset, "Individual height survives JSON file reload")
	editor.call("_undo")
	expect.call(not document.map_definition.has_custom_grid_offset and height.value == 0 and view.call("_hex_center", hex) == center, "Undo restores inheritance, control and original grid position")
	editor.call("_redo")
	expect.call(document.map_definition.grid_offset_y == 96 and height.value == 96, "Redo restores the custom height and control")
	(controls.get_node("SaveDefaultHeight") as Button).pressed.emit()
	expect.call(BattleGridLayoutSettings.load_default(path) == 96, "Default-height button persists the displayed height")
	var other := BattleDocumentSerializer.load(FIXTURE)
	editor.call("_replace_document", other, "", true)
	expect.call(height.value == 96 and not other.map_definition.has_custom_grid_offset and not editor.has_unsaved_changes(), "Opening another legacy document inherits the saved height without dirtying it")
	expect.call(view.call("_hex_center", hex) == center + Vector2(0, 96), "The inherited height moves the other board")
	var fresh := BattleLibrary.create_document(editor.get("_snapshot"), editor.initial_battle_id)
	editor.call("_replace_document", fresh, "", false)
	expect.call(height.value == 96 and not fresh.map_definition.has_custom_grid_offset, "New battle fields also inherit the default")
	var restarted := EditorGridLayoutControls.new()
	restarted.settings_path = path
	editor.add_child(restarted)
	restarted.sync(other.map_definition)
	expect.call(restarted.default_offset_y == 96, "A newly created editor control reads the persisted default")
	restarted.queue_free()
	editor.call("_replace_document", reopened, json_path, true)
	height.value = 0
	expect.call(reopened.map_definition.has_custom_grid_offset and BattleDocumentSerializer.to_dictionary(reopened)["map"]["grid_offset_y"] == 0, "Explicit zero remains a custom height distinct from inheritance")
	expect.call(BattleGridLayoutSettings.resolve_offset(reopened.map_definition, 96) == 0, "An explicit zero overrides a nonzero default")
	(controls.get_node("UseDefaultHeight") as Button).pressed.emit()
	expect.call(not reopened.map_definition.has_custom_grid_offset and height.value == 96 and not BattleDocumentSerializer.to_dictionary(reopened)["map"].has("grid_offset_y"), "Use-default button removes the override from JSON and updates the control")
	editor.call("_undo")
	expect.call(reopened.map_definition.has_custom_grid_offset and height.value == 0, "Returning to inheritance is undoable")
	for value: int in [-96, BattleMapDefinition.MIN_GRID_OFFSET_Y, BattleMapDefinition.MAX_GRID_OFFSET_Y]:
		height.value = value
		var shifted_center: Vector2 = view.call("_hex_center", hex)
		expect.call(shifted_center == center + Vector2(0, value) and view.screen_position_to_hex(view.to_global(shifted_center)) == hex, "Upward and boundary offsets preserve projection and picking: %d" % value)
	for invalid: Variant in ["30", 3.5, 541, -541, true]:
		var bad := original.duplicate(true)
		bad["map"]["grid_offset_y"] = invalid
		expect.call(BattleDocumentSerializer.from_dictionary(bad) == null, "Invalid grid height is rejected by JSON validation: %s" % str(invalid))
	var previous := BattleDocumentSerializer.to_dictionary(reopened)
	expect.call(not EditCommand.set_grid_offset(541).apply(reopened) and BattleDocumentSerializer.to_dictionary(reopened) == previous, "An invalid height command is rejected atomically")
	expect.call(BattleGridLayoutSettings.save_default(541, path) == ERR_INVALID_PARAMETER and BattleGridLayoutSettings.load_default(path) == 96, "Invalid defaults preserve the previous saved value")
	var missing_directory := "user://missing_grid_directory_%d/default.cfg" % OS.get_process_id()
	expect.call(BattleGridLayoutSettings.save_default(12, missing_directory) != OK, "Default save reports an unwritable destination")
	expect.call(BattleGridLayoutSettings.save_default(-20, path) == OK and BattleGridLayoutSettings.load_default(path) == -20, "Existing defaults are replaced and read back")
	expect.call(not FileAccess.file_exists(path + ".tmp") and not FileAccess.file_exists(path + ".bak"), "Successful default replacement leaves no temporary files")
	controls.settings_path = BattleGridLayoutSettings.DEFAULT_PATH
	editor.call("_replace_document", BattleDocumentSerializer.load(FIXTURE), "", true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(json_path))
	await editor.get_tree().process_frame
