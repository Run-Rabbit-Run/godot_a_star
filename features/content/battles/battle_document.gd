class_name BattleDocument
extends RefCounted


const SCHEMA_VERSION := 1

var document_id: StringName
var display_name := ""
var schema_version := SCHEMA_VERSION
var map_definition: BattleMapDefinition
var battle_definition: BattleDefinition
var package_versions: Dictionary[StringName, String] = {}
var editor_metadata: Dictionary = {}


func _init(
	p_document_id: StringName,
	p_map_definition: BattleMapDefinition,
	p_battle_definition: BattleDefinition
) -> void:
	document_id = p_document_id
	map_definition = p_map_definition
	battle_definition = p_battle_definition


static func from_snapshot(
	snapshot: ContentSnapshot,
	battle_id: StringName
) -> BattleDocument:
	if snapshot == null:
		return null

	var battle := snapshot.get_battle_definition(battle_id)

	if battle == null:
		return null

	var map := snapshot.get_map_definition(battle.map_id)

	if map == null:
		return null

	var document := BattleDocument.new(
		StringName("document:%s" % battle.id),
		map.duplicate(true) as BattleMapDefinition,
		battle.duplicate(true) as BattleDefinition
	)

	if snapshot.content_lock != null:
		for entry: ContentLockEntry in snapshot.content_lock.packages:
			document.package_versions[entry.package_id] = entry.package_version

	return document


func duplicate_document() -> BattleDocument:
	var copy := BattleDocument.new(
		document_id,
		map_definition.duplicate(true) as BattleMapDefinition,
		battle_definition.duplicate(true) as BattleDefinition
	)
	copy.schema_version = schema_version
	copy.display_name = display_name
	copy.package_versions = package_versions.duplicate(true)
	copy.editor_metadata = editor_metadata.duplicate(true)
	return copy


func copy_from(other: BattleDocument) -> void:
	document_id = other.document_id
	display_name = other.display_name
	schema_version = other.schema_version
	map_definition = other.map_definition.duplicate(true) as BattleMapDefinition
	battle_definition = other.battle_definition.duplicate(true) as BattleDefinition
	package_versions = other.package_versions.duplicate(true)
	editor_metadata = other.editor_metadata.duplicate(true)


func validate(snapshot: ContentSnapshot) -> BattleAuthoringValidationResult:
	var invalid := BattleAuthoringValidationResult.new()
	if snapshot == null or not snapshot.is_valid or map_definition == null or battle_definition == null:
		invalid.add_error("Document requires valid content, map and battle definitions.")
		return invalid
	if schema_version != SCHEMA_VERSION or document_id.is_empty() or map_definition.id.is_empty():
		invalid.add_error("Document requires supported schema and nonempty IDs.")
	if battle_definition.map_id != map_definition.id:
		invalid.add_error("Battle map_id must match the document map ID.")
	var grid := BattleMapFactory.create_hex_grid(map_definition)
	var result := BattleAuthoringValidator.validate(
		battle_definition,
		grid,
		snapshot.get_unit_definition_ids(),
		snapshot.get_ai_profile_definition_ids()
	)
	var full := BattleDefinitionValidator.validate(battle_definition, grid, snapshot.get_unit_definition_ids(), snapshot.get_ai_profile_definition_ids())
	if not full.is_valid and not result.errors.has(full.error_message):
		result.add_error(full.error_message)
	for error: String in invalid.errors:
		result.add_error(error)
	var versions: Dictionary[StringName, String] = {}
	if snapshot.content_lock != null:
		for entry: ContentLockEntry in snapshot.content_lock.packages:
			versions[entry.package_id] = entry.package_version
	for id: StringName in package_versions:
		if versions.get(id, "") != package_versions[id]:
			result.add_error("Не найдена требуемая версия пакета %s: %s." % [id, package_versions[id]])
	return result


func create_start_request(
	snapshot: ContentSnapshot,
	seed: int
) -> BattleStartRequest:
	var validation := validate(snapshot)

	if not validation.is_valid:
		return null

	var document_snapshot := duplicate_document()
	var trial_content := snapshot.with_battle_document(
		document_snapshot.map_definition,
		document_snapshot.battle_definition
	)
	return BattleStartRequest.new(
		document_snapshot.battle_definition.id,
		trial_content,
		seed
	)
