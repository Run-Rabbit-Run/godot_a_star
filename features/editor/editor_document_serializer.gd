class_name EditorDocumentSerializer
extends RefCounted


class LoadResult extends RefCounted:
	var document: EditorDocument
	var error_message := ""


static func save(document: EditorDocument, path: String) -> String:
	if document == null:
		return "EditorDocument is missing."

	var file := FileAccess.open(path, FileAccess.WRITE)

	if file == null:
		return "Could not open document for writing: %s." % path

	file.store_string(JSON.stringify(to_dictionary(document), "  "))
	return ""


static func load(path: String) -> EditorDocument:
	return load_result(path).document


static func load_result(path: String) -> LoadResult:
	var result := LoadResult.new()
	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		result.error_message = "Could not open %s (error %s)." % [path, FileAccess.get_open_error()]
		return result

	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		result.error_message = "JSON line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
		return result
	var parsed: Variant = parser.data

	if not (parsed is Dictionary):
		result.error_message = "Document root must be an object."
		return result

	result.error_message = _validate_structure(parsed)
	if result.error_message.is_empty():
		result.document = from_dictionary(parsed)
	return result


static func to_dictionary(document: EditorDocument) -> Dictionary:
	var cells: Array[Dictionary] = []
	var sides: Array[Dictionary] = []
	var placements: Array[Dictionary] = []

	for cell: BattleMapCellDefinition in document.map_definition.cells:
		cells.append({
			"q": cell.hex.x,
			"r": cell.hex.y,
			"movement_cost": cell.movement_cost,
			"terrain_id": String(cell.terrain_id),
			"traversable": cell.traversable,
			"hex_state_id": String(cell.hex_state_id),
		})

	for side: BattleSideDefinition in document.battle_definition.sides:
		sides.append({
			"side_id": String(side.side_id),
			"faction": side.faction,
			"control_source": side.control_source,
			"ai_profile_id": String(side.ai_profile_id),
		})

	for placement: UnitPlacementDefinition in document.battle_definition.unit_placements:
		placements.append({
			"placement_id": String(placement.placement_id),
			"definition_id": String(placement.definition_id),
			"side_id": String(placement.side_id),
			"q": placement.start_hex.x,
			"r": placement.start_hex.y,
			"facing": placement.facing,
			"modifiers": placement.modifiers,
			"ai_profile_override_id": String(placement.ai_profile_override_id),
			"character_binding": String(placement.character_binding),
		})

	var objective: Dictionary = {}

	if document.battle_definition.primary_objective != null:
		objective = {
			"type": document.battle_definition.primary_objective.type,
			"description": document.battle_definition.primary_objective.description,
			"target_faction": document.battle_definition.primary_objective.target_faction,
		}

	var package_versions: Dictionary = {}

	for package_id: StringName in document.package_versions:
		package_versions[String(package_id)] = document.package_versions[package_id]

	return {
		"document_id": String(document.document_id),
		"schema_version": document.schema_version,
		"package_versions": package_versions,
		"editor_metadata": document.editor_metadata,
		"map": {
			"id": String(document.map_definition.id),
			"background_id": String(document.map_definition.background_id),
			"presentation_frame": [document.map_definition.presentation_frame.x, document.map_definition.presentation_frame.y],
			"cells": cells,
		},
		"battle": {
			"id": String(document.battle_definition.id),
			"map_id": String(document.battle_definition.map_id),
			"protected_faction": document.battle_definition.protected_faction,
			"objective": objective,
			"sides": sides,
			"placements": placements,
		},
	}


static func from_dictionary(data: Dictionary) -> EditorDocument:
	if not _validate_structure(data).is_empty():
		return null

	var map_data: Dictionary = data.get("map", {})
	var battle_data: Dictionary = data.get("battle", {})
	var map := BattleMapDefinition.new()
	map.id = StringName(map_data.get("id", ""))
	map.background_id = StringName(map_data.get("background_id", "plateau"))
	var frame: Array = map_data.get("presentation_frame", [0, 0])
	if frame.size() == 2:
		map.presentation_frame = Vector2i(int(frame[0]), int(frame[1]))

	for cell_data: Dictionary in map_data.get("cells", []):
		map.cells.append(BattleMapCellDefinition.new(
			Vector2i(int(cell_data.get("q", 0)), int(cell_data.get("r", 0))),
			int(cell_data.get("movement_cost", 1)),
			StringName(cell_data.get("terrain_id", "core:default")),
			bool(cell_data.get("traversable", true)),
			StringName(cell_data.get("hex_state_id", ""))
		))

	var battle := BattleDefinition.new()
	battle.id = StringName(battle_data.get("id", ""))
	battle.map_id = StringName(battle_data.get("map_id", ""))
	battle.protected_faction = int(battle_data.get("protected_faction", 0)) as BattleFaction.Value
	var objective_data: Dictionary = battle_data.get("objective", {})

	if not objective_data.is_empty():
		battle.primary_objective = BattleObjectiveDefinition.new()
		battle.primary_objective.type = int(objective_data.get("type", 0)) as BattleObjectiveType.Value
		battle.primary_objective.description = objective_data.get("description", "")
		battle.primary_objective.target_faction = int(objective_data.get("target_faction", 1)) as BattleFaction.Value

	for side_data: Dictionary in battle_data.get("sides", []):
		var side := BattleSideDefinition.new()
		side.side_id = StringName(side_data.get("side_id", ""))
		side.faction = int(side_data.get("faction", 0)) as BattleFaction.Value
		side.control_source = int(side_data.get("control_source", 0)) as BattleControlSource.Value
		side.ai_profile_id = StringName(side_data.get("ai_profile_id", ""))
		battle.sides.append(side)

	for placement_data: Dictionary in battle_data.get("placements", []):
		var placement := UnitPlacementDefinition.new()
		placement.placement_id = StringName(placement_data.get("placement_id", ""))
		placement.definition_id = StringName(placement_data.get("definition_id", ""))
		placement.side_id = StringName(placement_data.get("side_id", ""))
		placement.start_hex = Vector2i(
			int(placement_data.get("q", 0)),
			int(placement_data.get("r", 0))
		)
		placement.facing = int(placement_data.get("facing", 0))
		placement.modifiers = placement_data.get("modifiers", {}).duplicate(true)
		placement.ai_profile_override_id = StringName(placement_data.get("ai_profile_override_id", ""))
		placement.character_binding = StringName(placement_data.get("character_binding", ""))
		battle.unit_placements.append(placement)

	var document := EditorDocument.new(
		StringName(data.get("document_id", "")),
		map,
		battle
	)
	document.editor_metadata = data.get("editor_metadata", {}).duplicate(true)

	for package_id: String in data.get("package_versions", {}):
		document.package_versions[StringName(package_id)] = data["package_versions"][package_id]

	return document


static func _validate_structure(data: Dictionary) -> String:
	var error := _validate_fields(data, {
		"schema_version": TYPE_INT, "document_id": TYPE_STRING,
		"map": TYPE_DICTIONARY, "battle": TYPE_DICTIONARY,
		"package_versions": TYPE_DICTIONARY, "editor_metadata": TYPE_DICTIONARY,
	}, "document")
	if not error.is_empty():
		return error
	if int(data.get("schema_version", -1)) != EditorDocument.SCHEMA_VERSION:
		return "Unsupported or missing schema_version."
	if not data.has("map") or not data.has("battle"):
		return "Document requires map and battle objects."
	var map: Dictionary = data["map"]
	var battle: Dictionary = data["battle"]
	error = _validate_fields(map, {
		"id": TYPE_STRING, "background_id": TYPE_STRING,
		"presentation_frame": TYPE_ARRAY, "cells": TYPE_ARRAY,
	}, "map")
	if not error.is_empty():
		return error
	if map.has("presentation_frame"):
		var frame: Array = map["presentation_frame"]
		if frame.size() != 2 or not _is_integer(frame[0]) or not _is_integer(frame[1]):
			return "map.presentation_frame requires two integers."
	error = _validate_fields(battle, {
		"id": TYPE_STRING, "map_id": TYPE_STRING, "protected_faction": TYPE_INT,
		"objective": TYPE_DICTIONARY, "sides": TYPE_ARRAY, "placements": TYPE_ARRAY,
	}, "battle")
	if not error.is_empty():
		return error
	error = _validate_fields(battle.get("objective", {}), {
		"type": TYPE_INT, "description": TYPE_STRING, "target_faction": TYPE_INT,
	}, "battle.objective")
	if not error.is_empty():
		return error
	var arrays: Array[Dictionary] = [
		{"path": "map.cells", "items": map.get("cells", []), "fields": {
			"q": TYPE_INT, "r": TYPE_INT, "movement_cost": TYPE_INT,
			"terrain_id": TYPE_STRING, "hex_state_id": TYPE_STRING, "traversable": TYPE_BOOL,
		}},
		{"path": "battle.sides", "items": battle.get("sides", []), "fields": {
			"side_id": TYPE_STRING, "faction": TYPE_INT, "control_source": TYPE_INT,
			"ai_profile_id": TYPE_STRING,
		}},
		{"path": "battle.placements", "items": battle.get("placements", []), "fields": {
			"placement_id": TYPE_STRING, "definition_id": TYPE_STRING, "side_id": TYPE_STRING,
			"q": TYPE_INT, "r": TYPE_INT, "facing": TYPE_INT, "modifiers": TYPE_DICTIONARY,
			"ai_profile_override_id": TYPE_STRING, "character_binding": TYPE_STRING,
		}},
	]
	for entry: Dictionary in arrays:
		var items: Array = entry["items"]
		for index in range(items.size()):
			var path := "%s[%d]" % [entry["path"], index]
			if not (items[index] is Dictionary):
				return "%s must be an object." % path
			error = _validate_fields(items[index], entry["fields"], path)
			if not error.is_empty():
				return error
	var versions: Dictionary = data.get("package_versions", {})
	for key: Variant in versions:
		if not (key is String) or not (versions[key] is String):
			return "package_versions must map string IDs to string versions."
	return ""


static func _validate_fields(data: Dictionary, fields: Dictionary, path: String) -> String:
	for key: String in fields:
		if not data.has(key):
			continue
		var expected: int = fields[key]
		if expected == TYPE_INT:
			if not _is_integer(data[key]):
				return "%s.%s must be an integer." % [path, key]
		elif typeof(data[key]) != expected:
			return "%s.%s must have type %s." % [path, key, type_string(expected)]
	return ""


static func _is_integer(value: Variant) -> bool:
	if value is int:
		return true
	# JSON numbers are floats. Reject NaN, infinity and unsafe conversions.
	return value is float and is_finite(value) and absf(value) <= 9007199254740991.0 and value == floorf(value)
