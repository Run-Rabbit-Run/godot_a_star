extends RefCounted
## Review regressions of the battle editor workflow: tools, inspector context, drag moves, selection and saving.

const FIXTURE := "res://features/battle/tests/fixtures/regression_battle.json"


func run(editor: BattleEditorShell, expect: Callable) -> void:
	var document := BattleDocumentSerializer.load(FIXTURE)
	editor.call("_replace_document", document, "", true)
	_check_tools(editor, expect)
	await _check_shortcuts(editor, document, expect)
	_check_drag(editor, document, expect)
	_check_selection(editor, document, expect)
	_check_rename(editor, document, expect)
	_check_obstacle_ids(editor, document, expect)
	_check_history_merge(document, expect)
	_check_first_save(editor, expect)
	editor.call("_replace_document", BattleDocumentSerializer.load(FIXTURE), "", true)
	await editor.get_tree().process_frame


func _check_tools(editor: BattleEditorShell, expect: Callable) -> void:
	var view: EditorBattleView = editor.get("_view")
	var tool_bar: EditorToolBar = editor.get("_tool_bar")
	editor.call("_select_tool", EditorBattleView.Tool.PAINT_STATE)
	editor.call("_select_tool", EditorBattleView.Tool.PAINT_OBSTACLE)
	var pressed := 0
	for button: Button in tool_bar.get_children():
		pressed += int(button.button_pressed)
	expect.call(pressed == 1 and tool_bar.selected() == EditorBattleView.Tool.PAINT_OBSTACLE and view.active_tool == EditorBattleView.Tool.PAINT_OBSTACLE, "Programmatic tool selection leaves exactly one tool button pressed")
	expect.call(_card_visible(editor, "_obstacle_card") and not _card_visible(editor, "_states_card") and not _card_visible(editor, "_unit_card"), "Obstacle tool shows only obstacle settings")
	editor.call("_select_tool", EditorBattleView.Tool.PAINT_STATE)
	expect.call(_card_visible(editor, "_states_card") and not _card_visible(editor, "_obstacle_card"), "State brush shows the state palette")
	editor.call("_select_tool", EditorBattleView.Tool.PLACE_UNIT)
	expect.call(_card_visible(editor, "_unit_card") and (editor.get("_inspector") as BattleEditorInspector).palette_box.visible, "Unit tool shows the unit palette")
	editor.call("_select_tool", EditorBattleView.Tool.SELECT)
	expect.call(not _card_visible(editor, "_hex_card") and not _card_visible(editor, "_unit_card"), "Selection tool without a selection hides property cards")
	editor.call("_set_status", "Marker status")
	editor.call("_frame_map")
	expect.call((editor.get("_status") as Label).text == "Marker status", "Fitting the map never replaces the status message")


## Real key events through the viewport reach the tool and history shortcuts.
func _check_shortcuts(editor: BattleEditorShell, document: BattleDocument, expect: Callable) -> void:
	var view: EditorBattleView = editor.get("_view")
	_press(editor, KEY_B)
	expect.call(view.active_tool == EditorBattleView.Tool.PAINT_STATE and _card_visible(editor, "_states_card"), "Key B selects the state brush")
	_press(editor, KEY_V)
	expect.call(view.active_tool == EditorBattleView.Tool.SELECT, "Key V returns to the selection tool")
	var id := document.battle_definition.unit_placements[0].placement_id
	editor.call("_on_placement_selected", id)
	_press(editor, KEY_DELETE)
	expect.call(editor.call("_find_placement", id) == null, "Delete removes the selected unit")
	_press(editor, KEY_Z, true)
	expect.call(editor.call("_find_placement", id) != null, "Ctrl+Z undoes the removal")
	_press(editor, KEY_ESCAPE)
	expect.call(String(editor.get("_selected_placement_id")).is_empty(), "Escape clears the selection")
	var name_edit: LineEdit = editor.get("_name_edit")
	var before := document.display_name
	name_edit.grab_focus()
	_press(editor, KEY_B)
	# LineEdit reports text changes at the end of the frame.
	await editor.get_tree().process_frame
	expect.call(view.active_tool == EditorBattleView.Tool.SELECT and document.display_name == before + "b", "Typing in a text field edits the text instead of switching tools")
	name_edit.release_focus()
	editor.call("_undo")
	expect.call(document.display_name == before and not editor.has_unsaved_changes(), "Undo restores the name typed through the field")


func _press(editor: BattleEditorShell, keycode: Key, ctrl := false) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.unicode = 0 if ctrl or keycode in [KEY_DELETE, KEY_ESCAPE] else String.chr(keycode).to_lower().unicode_at(0)
		event.ctrl_pressed = ctrl
		event.pressed = pressed
		editor.get_viewport().push_input(event)


func _check_drag(editor: BattleEditorShell, document: BattleDocument, expect: Callable) -> void:
	var view: EditorBattleView = editor.get("_view")
	var placement: UnitPlacementDefinition = document.battle_definition.unit_placements[0]
	var id := placement.placement_id
	var origin := placement.start_hex
	var target: Vector2i = editor.call("_free_hex_near", origin)
	view.frame_document((editor.get("_map_workspace") as Control).size)
	view.handle_input(_click(view, origin, true))
	expect.call(editor.get("_selected_placement_id") == id and view.is_dragging_placement(), "Pressing a unit with the selection tool selects it and starts a drag")
	view.handle_input(_click(view, target, false))
	expect.call(_placement(editor, id).start_hex == target and not view.is_dragging_placement(), "Releasing over a free hex moves the unit through a command")
	editor.call("_undo")
	expect.call(_placement(editor, id).start_hex == origin, "Drag move is undoable")
	var other := document.battle_definition.unit_placements[1].start_hex
	view.handle_input(_click(view, origin, true))
	view.handle_input(_click(view, other, false))
	expect.call(_placement(editor, id).start_hex == origin and editor.has_unsaved_changes() == false, "Dropping onto another unit is rejected without a document change")


func _check_selection(editor: BattleEditorShell, document: BattleDocument, expect: Callable) -> void:
	var id := document.battle_definition.unit_placements[0].placement_id
	editor.call("_on_placement_selected", id)
	editor.call("_select_hex", _missing_hex(editor))
	expect.call(String(editor.get("_selected_placement_id")).is_empty(), "Clicking a missing hex also clears the unit selection")
	editor.call("_on_placement_selected", id)
	editor.call("_delete_selected")
	expect.call(String(editor.get("_selected_placement_id")).is_empty() and (editor.get("_view") as EditorBattleView).selected_placement_id.is_empty(), "Deleting a unit clears its stale selection")
	editor.call("_undo")
	editor.call("_on_placement_selected", id)
	editor.call("_duplicate_selected")
	var copy_id: StringName = editor.get("_selected_placement_id")
	expect.call(copy_id != id and _placement(editor, copy_id) != null, "Duplicate selects the new copy")
	editor.call("_undo")
	expect.call(String(editor.get("_selected_placement_id")).is_empty(), "Undoing a duplicate drops the selection of the removed copy")


func _check_rename(editor: BattleEditorShell, document: BattleDocument, expect: Callable) -> void:
	var original := document.display_name
	var name_edit: LineEdit = editor.get("_name_edit")
	for text: String in ["П", "По", "Пол", "Поле"]:
		name_edit.text = text
		name_edit.text_changed.emit(text)
	editor.call("_undo")
	expect.call(document.display_name == original and name_edit.text == original, "Typing a field name is undone in one step")
	editor.call("_redo")
	expect.call(document.display_name == "Поле", "Redo restores the whole typed name")
	editor.call("_undo")


func _check_obstacle_ids(editor: BattleEditorShell, document: BattleDocument, expect: Callable) -> void:
	editor.call("_select_tool", EditorBattleView.Tool.PAINT_OBSTACLE)
	(editor.get("_obstacle_size") as SpinBox).value = 1
	var placed := 0
	for cell: BattleMapCellDefinition in document.map_definition.cells:
		if placed == 2:
			break
		if cell.traversable and not editor.call("_hex_is_occupied", cell.hex) and EditorBattleView.is_in_frame(cell.hex):
			editor.call("_on_hex_activated", cell.hex)
			placed += 1
	var obstacles := document.map_definition.obstacles
	expect.call(obstacles.size() == 2 and obstacles[0].id != obstacles[1].id and String(obstacles[0].id).begins_with("obstacle:"), "Obstacles receive distinct generated IDs")
	editor.call("_undo")
	editor.call("_undo")
	editor.call("_select_tool", EditorBattleView.Tool.SELECT)


func _check_history_merge(document: BattleDocument, expect: Callable) -> void:
	var copy := document.duplicate_document()
	var original := copy.display_name
	var history := EditorCommandHistory.new()
	for text: String in ["A", "AB", "ABC"]:
		history.execute(EditCommand.rename_document(text), copy)
	history.undo(copy)
	expect.call(copy.display_name == original and not history.undo(copy), "Consecutive renames form one history step")
	history.redo(copy)
	history.undo(copy)
	history.execute(EditCommand.rename_document("X"), copy)
	history.execute(EditCommand.set_background(&"alien_arena"), copy)
	history.execute(EditCommand.rename_document("XY"), copy)
	history.undo(copy)
	expect.call(copy.display_name == "X", "A rename after another edit starts a new history step")


func _check_first_save(editor: BattleEditorShell, expect: Callable) -> void:
	var folder := "user://battle_save_guard_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	editor.battles_directory = folder
	var snapshot: ContentSnapshot = editor.get("_snapshot")
	var fresh := BattleLibrary.create_document(snapshot, editor.initial_battle_id)
	editor.call("_replace_document", fresh, "", false)
	var path := folder.path_join(editor.call("_suggested_document_filename"))
	var stranger := BattleLibrary.create_document(snapshot, editor.initial_battle_id)
	stranger.display_name = "Чужое поле"
	BattleDocumentSerializer.save(stranger, path)
	var before := FileAccess.get_file_as_string(path)
	editor.call("_save")
	var dialog: FileDialog = editor.get("_save_dialog")
	expect.call(FileAccess.get_file_as_string(path) == before and dialog.visible and String(editor.get("_current_document_path")).is_empty(), "First save asks for a name instead of replacing another battle")
	dialog.hide()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	editor.call("_save")
	expect.call(editor.get("_current_document_path") == path and not editor.has_unsaved_changes(), "First save of a new field writes its own file")
	editor.call("_save")
	expect.call(not dialog.visible and FileAccess.file_exists(path), "Saving the same field again keeps its file")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
	editor.battles_directory = GameContentSettings.BATTLES


func _click(view: EditorBattleView, hex: Vector2i, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.global_position = view.to_global(view.call("_hex_center", hex))
	return event


func _placement(editor: BattleEditorShell, id: StringName) -> UnitPlacementDefinition:
	return editor.call("_find_placement", id)


func _card_visible(editor: BattleEditorShell, property: String) -> bool:
	var card: Control = (editor.get("_inspector") as BattleEditorInspector).get(property.trim_prefix("_"))
	return (card.get_parent() as Control).visible


func _missing_hex(editor: BattleEditorShell) -> Vector2i:
	for row in range(12):
		for column in range(18):
			var hex := HexCoordinateMapper.offset_to_axial(Vector2i(column, row))
			if editor.call("_find_cell", hex) == null:
				return hex
	return Vector2i(999999, 999999)
