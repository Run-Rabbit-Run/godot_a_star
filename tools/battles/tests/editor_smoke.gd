extends SceneTree


var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://tools/battles/battle_editor.tscn") as PackedScene
	_expect(scene != null, "Battle editor scene must load.")

	if scene == null:
		_finish()
		return

	var editor := scene.instantiate() as BattleEditorShell
	root.add_child(editor)
	await process_frame
	await process_frame

	var document: BattleDocument = editor.get("_document")
	var view: EditorBattleView = editor.get("_view")
	var workspace: Control = editor.get("_map_workspace")
	var tool_option: OptionButton = editor.get("_tool_option")
	var save_dialog: FileDialog = editor.get("_save_dialog")
	var open_dialog: FileDialog = editor.get("_open_dialog")
	_expect(document != null, "Editor must create an BattleDocument.")
	_expect(view != null and workspace != null, "Editor must create a clipped map workspace.")
	_expect(tool_option != null and tool_option.item_count == EditorBattleView.Tool.size(), "Editor must expose all map and unit tools.")
	_expect(save_dialog != null and open_dialog != null, "Editor must expose save-as and open dialogs.")

	if document == null or view == null or workspace == null:
		editor.queue_free()
		await process_frame
		_finish()
		return

	_expect(not document.map_definition.cells.is_empty(), "Editor document must contain map cells.")
	var original := document.map_definition.cells[0] as BattleMapCellDefinition
	var original_copy := original.duplicate(true) as BattleMapCellDefinition
	editor.call("_select_hex", original.hex)
	(editor.get("_terrain_id_edit") as LineEdit).text = "test:crystal"
	(editor.get("_movement_cost_spin") as SpinBox).value = 4
	(editor.get("_traversable_check") as CheckButton).button_pressed = false
	editor.call("_apply_selected_hex")
	var updated := _find_cell(document, original.hex)
	_expect(
		updated != null
		and updated.terrain_id == &"test:crystal"
		and updated.movement_cost == 4
		and not updated.traversable,
		"Selected-cell properties must update through EditCommand."
	)

	editor.call("_undo")
	var restored := _find_cell(document, original_copy.hex)
	_expect(
		restored != null
		and restored.terrain_id == original_copy.terrain_id
		and restored.movement_cost == original_copy.movement_cost
		and restored.traversable == original_copy.traversable,
		"Undo must restore all edited cell properties."
	)
	editor.call("_redo")
	updated = _find_cell(document, original.hex)
	_expect(updated != null and updated.movement_cost == 4, "Redo must reapply the cell edit.")

	var new_hex := original.hex
	editor.call("_undo") # Undo the re-applied property change.
	editor.call("_remove_hex", new_hex)
	_expect(_find_cell(document, new_hex) == null, "Remove fixture cell before testing add brush")
	view.set_tool(EditorBattleView.Tool.ADD_HEX)
	(editor.get("_terrain_id_edit") as LineEdit).text = "test:ash"
	(editor.get("_movement_cost_spin") as SpinBox).value = 2
	(editor.get("_traversable_check") as CheckButton).button_pressed = true
	editor.call("_on_hex_activated", new_hex)
	var added := _find_cell(document, new_hex)
	_expect(
		added != null
		and added.terrain_id == &"test:ash"
		and added.movement_cost == 2
		and added.traversable,
		"Add-hex brush must use the current brush properties."
	)
	editor.call("_undo")
	_expect(_find_cell(document, new_hex) == null, "Add-hex brush must participate in undo.")
	editor.call("_undo") # Restore removed fixture cell.

	view.frame_document(workspace.size)
	var sample_hex := document.map_definition.cells[0].hex
	var sample_local: Vector2 = view.call("_hex_center", sample_hex)
	var sample_screen := view.to_global(sample_local)
	_expect(
		view.screen_position_to_hex(sample_screen) == sample_hex,
		"Cursor conversion must return the same axial hex at its center."
	)

	var first_path := "user://editor_smoke_first_%d.json" % OS.get_process_id()
	var second_path := "user://editor_smoke_second_%d.json" % OS.get_process_id()
	editor.call("_save_to_path", first_path)
	editor.call("_save_to_path", second_path)
	_expect(FileAccess.file_exists(first_path), "Editor must save to the first selected path.")
	_expect(FileAccess.file_exists(second_path), "Editor must save to a second selected path.")
	_expect(BattleDocumentSerializer.load(first_path) != null, "First saved document must load.")
	_expect(BattleDocumentSerializer.load(second_path) != null, "Second saved document must load.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(first_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(second_path))
	await _check_battle_library(editor)

	editor.queue_free()
	await process_frame
	_finish()


func _check_battle_library(editor: BattleEditorShell) -> void:
	var snapshot: ContentSnapshot = editor.get("_snapshot")
	var fixture := BattleDocumentSerializer.load("res://features/battle/tests/fixtures/regression_battle.json")
	_expect(fixture != null and fixture.display_name.is_empty(), "Legacy documents must load without a name.")
	var first := BattleLibrary.create_document(snapshot, editor.initial_battle_id)
	var second := BattleLibrary.create_document(snapshot, editor.initial_battle_id)
	_expect(first != null and second != null, "New fields must be created from base content.")
	if first == null or second == null:
		return
	_expect(first.document_id != second.document_id and first.battle_definition.id != second.battle_definition.id and first.map_definition.id != second.map_definition.id, "New fields must have independent document, battle and map IDs.")
	_expect(first.battle_definition.map_id == first.map_definition.id, "New field map references must agree.")
	_expect(first.battle_definition.unit_placements.is_empty(), "New fields must have no units.")
	_expect(first.map_definition.cells.size() == 216, "New fields must have a complete 18x12 grid.")
	var clean := true
	for cell: BattleMapCellDefinition in first.map_definition.cells:
		clean = clean and EditorBattleView.is_in_frame(cell.hex) and cell.traversable and cell.hex_state_id.is_empty() and cell.movement_cost == 1
	_expect(clean, "Every new cell must be clean and within the editable frame.")
	editor.call("_replace_document", first, "", false)
	_expect(editor.has_unsaved_changes(), "New fields must be unsaved drafts.")
	var name_edit: LineEdit = editor.get("_name_edit")
	name_edit.text = "Тестовое поле"
	name_edit.caret_column = 3
	name_edit.text_changed.emit(name_edit.text)
	_expect(first.display_name == "Тестовое поле", "The name control must edit the document.")
	_expect(name_edit.caret_column == 3, "Editing a name must preserve the text caret.")
	editor.call("_undo")
	_expect(first.display_name == "Новое поле боя" and name_edit.text == first.display_name, "Undo must restore both document name and control.")
	editor.call("_redo")
	_expect(first.display_name == "Тестовое поле", "Redo must restore the new name.")
	var directory := "user://battle_library_%d" % OS.get_process_id()
	var first_path := directory.path_join("first.json")
	var second_path := directory.path_join("second.json")
	_expect(editor.call("_save_to_path", first_path), "The named draft must save.")
	_expect(not editor.has_unsaved_changes(), "Successful save must clear draft changes.")
	var original_text := FileAccess.get_file_as_string(first_path)
	editor.call("_create_new_document")
	_expect(String(editor.get("_current_document_path")).is_empty(), "Creating a field must clear the previous save path.")
	var fresh: BattleDocument = editor.get("_document")
	_expect(fresh.document_id != first.document_id, "Creating a field must replace the previous identity.")
	_expect(editor.call("_save_to_path", second_path), "The second field must save separately.")
	_expect(FileAccess.get_file_as_string(first_path) == original_text, "Saving a second field must preserve the first file.")
	var entries := BattleLibrary.list_documents(directory)
	_expect(entries.size() == 2 and entries[0].label == "Тестовое поле", "The library must list named saved fields.")
	editor.call("_load_document_path", first_path)
	var reopened: BattleDocument = editor.get("_document")
	_expect(reopened.document_id == first.document_id and reopened.display_name == "Тестовое поле" and not editor.has_unsaved_changes(), "Opening must restore name, identity and saved state.")
	name_edit.text = "Несохранённое имя"
	name_edit.text_changed.emit(name_edit.text)
	var choice: OptionButton = editor.get("_battle_option")
	var index := choice.item_count
	choice.add_item("Second fixture")
	choice.set_item_metadata(index, second_path)
	editor.call("_on_battle_selected", index)
	var discard: ConfirmationDialog = editor.get("_discard_dialog")
	_expect(discard.visible and editor.get("_document") == reopened, "Selecting a saved field must guard the unsaved draft.")
	discard.hide()
	_expect(editor.get("_document") == reopened, "Canceling a switch must retain the draft.")
	editor.call("_new_document_requested")
	_expect(discard.visible and editor.get("_document") == reopened, "New field must guard unsaved changes before replacing the document.")
	discard.hide()
	editor.call("_confirm_discard")
	_expect(editor.get("_document") != reopened, "Confirmed discard must create the requested field.")
	var invalid_data := BattleDocumentSerializer.to_dictionary(first)
	invalid_data["display_name"] = 42
	_expect(BattleDocumentSerializer.from_dictionary(invalid_data) == null, "A non-string name must be rejected by the shared format.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(first_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(second_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	await process_frame


func _find_cell(
	document: BattleDocument,
	hex: Vector2i
) -> BattleMapCellDefinition:
	for cell: BattleMapCellDefinition in document.map_definition.cells:
		if cell.hex == hex:
			return cell
	return null


func _expect(condition: bool, message: String) -> void:
	_checks += 1

	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Editor smoke passed (%d checks)" % _checks)
		quit(0)
		return

	for failure: String in _failures:
		push_error("FAIL: %s" % failure)
	quit(1)
