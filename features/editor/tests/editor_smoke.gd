extends SceneTree


var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://features/editor/battle_editor.tscn") as PackedScene
	_expect(scene != null, "Battle editor scene must load.")

	if scene == null:
		_finish()
		return

	var editor := scene.instantiate() as BattleEditorShell
	root.add_child(editor)
	await process_frame
	await process_frame

	var document: EditorDocument = editor.get("_document")
	var view: EditorBattleView = editor.get("_view")
	var workspace: Control = editor.get("_map_workspace")
	var tool_option: OptionButton = editor.get("_tool_option")
	var save_dialog: FileDialog = editor.get("_save_dialog")
	var open_dialog: FileDialog = editor.get("_open_dialog")
	_expect(document != null, "Editor must create an EditorDocument.")
	_expect(view != null and workspace != null, "Editor must create a clipped map workspace.")
	_expect(tool_option != null and tool_option.item_count == 7, "Editor must expose all map and unit tools.")
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

	var new_hex := Vector2i(80, 80)
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

	view.frame_document(workspace.size)
	var sample_hex := document.map_definition.cells[0].hex
	var sample_local: Vector2 = view.call("_hex_center", sample_hex)
	var sample_screen := view.to_global(sample_local)
	_expect(
		view.screen_position_to_hex(sample_screen) == sample_hex,
		"Cursor conversion must return the same axial hex at its center."
	)

	var first_path := "user://editor_smoke_first.json"
	var second_path := "user://editor_smoke_second.json"
	editor.call("_save_to_path", first_path)
	editor.call("_save_to_path", second_path)
	_expect(FileAccess.file_exists(first_path), "Editor must save to the first selected path.")
	_expect(FileAccess.file_exists(second_path), "Editor must save to a second selected path.")
	_expect(EditorDocumentSerializer.load(first_path) != null, "First saved document must load.")
	_expect(EditorDocumentSerializer.load(second_path) != null, "Second saved document must load.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(first_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(second_path))

	editor.queue_free()
	await process_frame
	_finish()


func _find_cell(
	document: EditorDocument,
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
