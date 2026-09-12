class_name EditorDocument
extends RefCounted


const SCHEMA_VERSION := 1

var document_id: StringName
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
) -> EditorDocument:
	if snapshot == null:
		return null

	var battle := snapshot.get_battle_definition(battle_id)

	if battle == null:
		return null

	var map := snapshot.get_map_definition(battle.map_id)

	if map == null:
		return null

	var document := EditorDocument.new(
		StringName("document:%s" % battle.id),
		map.duplicate(true) as BattleMapDefinition,
		battle.duplicate(true) as BattleDefinition
	)

	if snapshot.content_lock != null:
		for entry: ContentLockEntry in snapshot.content_lock.packages:
			document.package_versions[entry.package_id] = entry.package_version

	return document


func duplicate_document() -> EditorDocument:
	var copy := EditorDocument.new(
		document_id,
		map_definition.duplicate(true) as BattleMapDefinition,
		battle_definition.duplicate(true) as BattleDefinition
	)
	copy.schema_version = schema_version
	copy.package_versions = package_versions.duplicate(true)
	copy.editor_metadata = editor_metadata.duplicate(true)
	return copy


func copy_from(other: EditorDocument) -> void:
	document_id = other.document_id
	schema_version = other.schema_version
	map_definition = other.map_definition.duplicate(true) as BattleMapDefinition
	battle_definition = other.battle_definition.duplicate(true) as BattleDefinition
	package_versions = other.package_versions.duplicate(true)
	editor_metadata = other.editor_metadata.duplicate(true)


func validate(snapshot: ContentSnapshot) -> BattleAuthoringValidationResult:
	var grid := BattleMapFactory.create_hex_grid(map_definition)
	return BattleAuthoringValidator.validate(
		battle_definition,
		grid,
		snapshot.get_unit_definition_ids(),
		snapshot.get_ai_profile_definition_ids()
	)


func create_trial_request(
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