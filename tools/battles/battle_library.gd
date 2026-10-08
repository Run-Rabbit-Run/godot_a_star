class_name BattleLibrary
extends RefCounted


static func list_documents(directory: String = GameContentSettings.BATTLES) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var files := DirAccess.get_files_at(directory)
	files.sort()
	for filename: String in files:
		if filename.get_extension().to_lower() != "json":
			continue
		var path := directory.path_join(filename)
		var loaded := BattleDocumentSerializer.load_result(path)
		var label := filename.get_basename()
		if loaded.document != null and not loaded.document.display_name.strip_edges().is_empty():
			label = loaded.document.display_name
		entries.append({"path": path, "label": label, "error": loaded.error_message})
	return entries


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
