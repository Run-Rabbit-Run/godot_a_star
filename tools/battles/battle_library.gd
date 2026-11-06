class_name BattleLibrary
extends RefCounted
## Battle documents of the project library: listing, new fields, file names and deletion.

const DRAFT_FILENAME := "battle_editor_draft.json"


## File name of the document in the library: its battle ID with ':' replaced.
static func filename_for(document: BattleDocument) -> String:
	if document == null or document.battle_definition.id.is_empty():
		return DRAFT_FILENAME
	return "%s.json" % String(document.battle_definition.id).replace(":", "_")


static func with_json_extension(path: String) -> String:
	return path if path.get_extension().to_lower() == "json" else "%s.json" % path


## Whether the file holds this same field, so an ordinary save may replace it.
static func holds_document(path: String, document: BattleDocument) -> bool:
	var existing := BattleDocumentSerializer.load_result(path).document
	return existing != null and existing.document_id == document.document_id


static func list_documents(directory: String = GameContentSettings.BATTLES) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for path: String in _document_paths(directory):
		var loaded := BattleDocumentSerializer.load_result(path)
		entries.append({"path": path, "label": label_for(path, loaded.document), "error": loaded.error_message})
	return entries


## Name of a field in lists and messages; fields without a name are shown by their file name.
static func label_for(path: String, document: BattleDocument) -> String:
	if document != null and not document.display_name.strip_edges().is_empty():
		return document.display_name
	return path.get_file().get_basename()


## Saved fields that place this unit: the library folder plus the starting battle wherever it lies.
static func fields_using_unit(unit_id: StringName, directory: String = GameContentSettings.BATTLES) -> Array[Dictionary]:
	var starting := _starting_battle_path()
	var paths := _document_paths(directory)
	if not starting.is_empty() and not paths.any(func(path: String) -> bool: return same_path(path, starting)):
		paths.append(starting)
	var fields: Array[Dictionary] = []
	for path: String in paths:
		var document := BattleDocumentSerializer.load_result(path).document
		if document == null:
			continue
		for placement: UnitPlacementDefinition in document.battle_definition.unit_placements:
			if placement.definition_id == unit_id:
				fields.append({"path": path, "label": label_for(path, document), "starting": same_path(path, starting)})
				break
	return fields


## Why the file of this open field may not be deleted, or "" when it may.
static func delete_error(path: String, document: BattleDocument) -> String:
	if path.is_empty():
		return "Поле ещё не сохранено: удалять нечего."
	if not FileAccess.file_exists(path):
		return "Файл поля не найден: %s" % path
	if document == null or not holds_document(path, document):
		return "Файл %s хранит другое поле или повреждён: удаление отменено." % path
	var settings := GameContentSettings.read()
	if settings == null:
		return "Не удалось прочитать %s: стартовый бой не проверен, удаление отменено." % GameContentSettings.PATH
	if same_path(settings.battle_document_path, path):
		return "Это стартовый бой игры: сначала назначьте стартовым другое поле."
	return ""


## Deletes the file of the open field after the same checks. Units and images are not touched.
static func delete_document(path: String, document: BattleDocument) -> String:
	var error := delete_error(path, document)
	if not error.is_empty():
		return error
	var removed := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return "" if removed == OK else "Не удалось удалить %s: %s" % [path, error_string(removed)]


static func same_path(first: String, second: String) -> bool:
	return (
		not first.is_empty() and not second.is_empty()
		and ProjectSettings.globalize_path(first).simplify_path() == ProjectSettings.globalize_path(second).simplify_path()
	)


static func _document_paths(directory: String) -> Array[String]:
	var paths: Array[String] = []
	if not DirAccess.dir_exists_absolute(directory):
		return paths
	var files := DirAccess.get_files_at(directory)
	files.sort()
	for filename: String in files:
		if filename.get_extension().to_lower() == "json":
			paths.append(directory.path_join(filename))
	return paths


static func _starting_battle_path() -> String:
	var settings := GameContentSettings.read()
	return settings.battle_document_path if settings != null else ""


static func create_document(snapshot: ContentSnapshot, template_id: StringName) -> BattleDocument:
	var document := BattleDocument.from_snapshot(snapshot, template_id)
	if document == null:
		return null
	var token := Crypto.new().generate_random_bytes(16).hex_encode()
	document.document_id = StringName("document:%s" % token)
	document.battle_definition.id = StringName("authored:b_%s" % token)
	document.map_definition.id = StringName("authored:m_%s" % token)
	document.battle_definition.map_id = document.map_definition.id
	document.display_name = "Новое поле боя"
	document.battle_definition.unit_placements.clear()
	document.map_definition.cells.clear()
	document.map_definition.presentation_frame = Vector2i(18, 12)
	for r in range(12):
		for q in range(18):
			var hex := HexCoordinateMapper.offset_to_axial(Vector2i(q, r))
			document.map_definition.cells.append(BattleMapCellDefinition.new(hex))
	return document
