class_name EditorDocumentSerializer
extends RefCounted


static func save(document: EditorDocument, path: String) -> String:
	if document == null:
		return "EditorDocument is missing."

	var file := FileAccess.open(path, FileAccess.WRITE)

	if file == null:
		return "Could not open document for writing: %s." % path

	file.store_string(JSON.stringify(to_dictionary(document), "  "))
	return ""


static func load(path: String) -> EditorDocument:
	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		return null

	var parsed: Variant = JSON.parse_string(file.get_as_text())

	if not (parsed is Dictionary):
		return null

	return from_dictionary(parsed)


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
	if int(data.get("schema_version", -1)) != EditorDocument.SCHEMA_VERSION:
		return null

	var map_data: Dictionary = data.get("map", {})
	var battle_data: Dictionary = data.get("battle", {})
	var map := BattleMapDefinition.new()
	map.id = StringName(map_data.get("id", ""))

	for cell_data: Dictionary in map_data.get("cells", []):
		map.cells.append(BattleMapCellDefinition.new(
			Vector2i(int(cell_data.get("q", 0)), int(cell_data.get("r", 0))),
			int(cell_data.get("movement_cost", 1)),
			StringName(cell_data.get("terrain_id", "core:default")),
			bool(cell_data.get("traversable", true))
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