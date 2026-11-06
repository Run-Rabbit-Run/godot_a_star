extends RefCounted
## Battle editor deletion: the starting, unsaved and replaced fields stay; the open draft survives.


func run(suite: Node) -> void:
	var editor := (load("res://tools/battles/battle_editor.tscn") as PackedScene).instantiate() as BattleEditorShell
	suite.get_tree().root.add_child(editor)
	await suite.get_tree().process_frame
	await suite.get_tree().process_frame
	var dialog: ConfirmationDialog = editor.get("_delete_dialog")
	var inspector: BattleEditorInspector = editor.get("_inspector")
	var settings := GameContentSettings.read()
	var starting := settings.battle_document_path
	suite.expect(BattleLibrary.same_path(editor.get("_current_document_path"), starting), "Deletion checks start from the opened starting battle")
	editor.call("_delete_field_requested")
	suite.expect(not dialog.visible and FileAccess.file_exists(starting) and (editor.get("_status") as Label).text.contains("стартовый бой"), "The starting battle of the game cannot be deleted")

	editor.set("_selected_definition_id", &"custom_units:u_deleted_elsewhere")
	editor.call("_reload_unit_library")
	suite.expect(String(editor.get("_selected_definition_id")).is_empty(), "Reloading the library drops a palette choice whose unit was deleted")

	var folder := "user://battle_delete_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	editor.battles_directory = folder
	editor.call("_create_new_document")
	editor.call("_delete_field_requested")
	suite.expect(not dialog.visible and inspector.delete_field_button.disabled, "An unsaved field has no file to delete")
	editor.call("_save")
	var path: String = editor.get("_current_document_path")
	var document: BattleDocument = editor.get("_document")
	suite.expect(FileAccess.file_exists(path) and not inspector.delete_field_button.disabled, "A saved field can be deleted")

	editor.call("_delete_field_requested")
	suite.expect(dialog.visible and dialog.dialog_text.contains("«Новое поле боя»") and dialog.dialog_text.contains(path), "Deletion asks first and names the field and its file")
	await suite.get_tree().process_frame
	suite.expect(dialog.get_cancel_button().has_focus(), "The field deletion dialog focuses Cancel")
	dialog.hide()
	suite.expect(FileAccess.file_exists(path), "Closing the deletion dialog keeps the field file")
	editor.call("_delete_field_requested")
	dialog.confirmed.emit()
	dialog.hide()
	suite.expect(not FileAccess.file_exists(path) and String(editor.get("_current_document_path")).is_empty(), "Confirmed deletion removes the field file and forgets its path")
	suite.expect(editor.get("_document") == document and not editor.has_unsaved_changes() and (editor.get("_dirty_label") as Label).text.begins_with("○"), "The deleted field stays open as a new draft without a discard prompt")
	suite.expect(inspector.delete_field_button.disabled, "A deleted field offers no second deletion")
	editor.call("_save")
	suite.expect(FileAccess.file_exists(path) and editor.get("_current_document_path") == path, "Saving the open draft restores a deleted field")

	var stranger := BattleLibrary.create_document(editor.get("_snapshot"), editor.initial_battle_id)
	BattleDocumentSerializer.save(stranger, path)
	editor.call("_delete_field_requested")
	suite.expect(not dialog.visible and BattleLibrary.holds_document(path, stranger), "A file replaced by another field is not deleted")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
	editor.queue_free()
	await suite.get_tree().process_frame
