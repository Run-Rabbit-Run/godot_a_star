extends RefCounted
## Unit editor deletion: confirmation, fields that place the unit, the open draft and broken files.

const FIXTURE := "res://features/battle/tests/fixtures/regression_battle.json"


func run(suite: Node) -> void:
	var folder := "user://unit_delete_%d" % OS.get_process_id()
	var battles := folder.path_join("battles")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(battles))
	var editor := preload("res://tools/units/unit_editor.tscn").instantiate() as UnitEditor
	editor.embedded = true
	editor.units_directory = folder
	editor.battles_directory = battles
	suite.add_child(editor)
	await suite.get_tree().process_frame
	var dialog: ConfirmationDialog = editor.get("_delete_dialog")

	editor._request_delete(editor._path_for(editor._document))
	suite.expect(not dialog.visible, "An unsaved unit has no file to delete")
	editor._change("name", "Удаляемый")
	editor._save()
	var path: String = editor._path_for(editor._document)
	suite.expect(FileAccess.file_exists(path), "Unit deletion fixture is saved to the test folder")
	var unit_id := StringName(editor._document.id)
	suite.expect(UnitLibrary.id_for_path(path) == unit_id, "A unit file names its unit ID")

	var field := BattleDocumentSerializer.load(FIXTURE)
	field.display_name = "Поле с юнитом"
	field.battle_definition.unit_placements[0].definition_id = unit_id
	BattleDocumentSerializer.save(field, battles.path_join("field.json"))
	var fields := BattleLibrary.fields_using_unit(unit_id, battles)
	suite.expect(fields.size() == 1 and fields[0].label == "Поле с юнитом" and not fields[0].starting, "Fields that place a unit are found before its deletion")
	_check_starting_usage(suite, battles)

	editor._request_delete(path)
	suite.expect(dialog.visible and dialog.dialog_text.contains("«Удаляемый»") and dialog.dialog_text.contains("«Поле с юнитом»"), "Deletion asks first and names the unit and the fields that place it")
	await suite.get_tree().process_frame
	suite.expect(dialog.get_cancel_button().has_focus(), "The deletion dialog focuses Cancel, so Enter never deletes")
	dialog.hide()
	suite.expect(FileAccess.file_exists(path), "Closing the deletion dialog keeps the unit file")
	editor._request_delete(path)
	dialog.confirmed.emit()
	dialog.hide()
	suite.expect(not FileAccess.file_exists(path), "Confirmed deletion removes the open unit's file")
	var dirty: Label = editor.get("_dirty")
	suite.expect(editor._document.name == "Удаляемый" and editor._document == editor._saved and dirty.text.begins_with("○"), "The deleted unit stays in the form as a new unit without a discard prompt")
	suite.expect((editor.get("_list") as ItemList).item_count == 0, "The deleted unit leaves the library list")
	editor._save()
	suite.expect(FileAccess.file_exists(path), "Saving the open draft restores a deleted unit")

	await _check_broken_file(suite, editor, folder, path)
	_check_foreign_paths(suite, folder)
	editor.queue_free()
	await suite.get_tree().process_frame
	for file: String in [path, battles.path_join("field.json")]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(battles))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))


## A broken file cannot be opened, so the list's context menu deletes it without opening.
func _check_broken_file(suite: Node, editor: UnitEditor, folder: String, open_path: String) -> void:
	var broken := folder.path_join("u_broken.json")
	var file := FileAccess.open(broken, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	editor._refresh_list()
	var list: ItemList = editor.get("_list")
	var index := -1
	for item in range(list.item_count):
		if list.get_item_metadata(item) == broken:
			index = item
	suite.expect(index >= 0, "A broken unit file is listed")
	if index < 0:
		return
	list.force_update_list_size()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	click.position = list.get_item_rect(index).get_center()
	editor._on_list_input(click)
	var menu: PopupMenu = editor.get("_list_menu")
	suite.expect(menu.visible and editor.get("_menu_path") == broken and list.get_selected_items().has(index) == false, "Right click on a listed unit opens the delete menu without opening the unit")
	menu.hide()
	menu.id_pressed.emit(0)
	var dialog: ConfirmationDialog = editor.get("_delete_dialog")
	suite.expect(dialog.visible and dialog.dialog_text.contains("u_broken.json"), "A broken unit file is named in the deletion dialog")
	dialog.confirmed.emit()
	dialog.hide()
	suite.expect(not FileAccess.file_exists(broken) and FileAccess.file_exists(open_path) and editor._document == editor._saved, "Deleting another file keeps the open unit and its file")


func _check_foreign_paths(suite: Node, folder: String) -> void:
	var outside := "%s_outside.json" % folder
	var file := FileAccess.open(outside, FileAccess.WRITE)
	file.store_string("{}")
	file.close()
	var text := folder.path_join("notes.txt")
	file = FileAccess.open(text, FileAccess.WRITE)
	file.store_string("notes")
	file.close()
	suite.expect(
		not UnitLibrary.delete_document(outside, folder).is_empty() and FileAccess.file_exists(outside)
		and not UnitLibrary.delete_document(text, folder).is_empty() and FileAccess.file_exists(text),
		"Unit deletion refuses files outside the unit folder and non-JSON files",
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(outside))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(text))


## The starting battle counts even outside the scanned folder: deleting its unit breaks the game start.
func _check_starting_usage(suite: Node, battles: String) -> void:
	var settings := GameContentSettings.read()
	var starting := BattleDocumentSerializer.load(settings.battle_document_path) if settings != null else null
	if starting == null or starting.battle_definition.unit_placements.is_empty():
		suite.expect(false, "The starting battle places units for the usage check")
		return
	var fields := BattleLibrary.fields_using_unit(starting.battle_definition.unit_placements[0].definition_id, battles)
	suite.expect(fields.any(func(entry: Dictionary) -> bool: return entry.starting), "A unit placed in the starting battle is reported as such")
