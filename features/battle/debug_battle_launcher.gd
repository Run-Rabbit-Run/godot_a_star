class_name DebugBattleLauncher
extends Node


signal battle_finished(result: BattleResult)


@export var battle_id: StringName
@export var content_packages: Array[ContentPackage] = []
@export var battle_definitions: Array[BattleDefinition] = []
@export var map_definitions: Array[BattleMapDefinition] = []
@export var unit_definitions: Array[UnitDefinition] = []
@export var ai_profile_definitions: Array[AIProfileDefinition] = []
@export var deterministic_seed := 1

@onready var _battle_screen: BattleScreen = %BattleScreen


func _ready() -> void:
	if not _battle_screen.battle_finished.is_connected(_on_battle_finished):
		_battle_screen.battle_finished.connect(_on_battle_finished)

	var content_snapshot := _load_content()

	if content_snapshot == null:
		return

	var request := BattleStartRequest.new(
		battle_id,
		content_snapshot,
		deterministic_seed
	)

	if not _battle_screen.setup(request):
		push_error("Debug battle could not be started.")


func _load_content() -> ContentSnapshot:
	if content_packages.is_empty():
		return ContentSnapshot.new(
			battle_definitions,
			map_definitions,
			unit_definitions,
			ai_profile_definitions
		)

	var load_result := ContentLoader.load_packages(content_packages)

	if not load_result.is_successful:
		for error: String in load_result.errors:
			push_error("Content loading failed: %s" % error)
		return null

	return load_result.snapshot


func _on_battle_finished(result: BattleResult) -> void:
	battle_finished.emit(result)