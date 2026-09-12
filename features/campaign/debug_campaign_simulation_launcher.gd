class_name DebugCampaignSimulationLauncher
extends Node


@export var content_packages: Array[ContentPackage] = []
@export var campaign_id: StringName
@export var fallback_ai_profile: AIProfileDefinition


func _ready() -> void:
	var load_result := ContentLoader.load_packages(content_packages)

	if not load_result.is_successful:
		for error: String in load_result.errors:
			push_error(error)
		get_tree().quit(1)
		return

	var result := CampaignSimulationRunner.new().run(
		load_result.snapshot,
		campaign_id,
		fallback_ai_profile
	)

	if not result.completed:
		push_error(result.error_message)
		get_tree().quit(1)
		return

	print(
		"Campaign completed: %s; scenarios: %s; battles: %s"
		% [campaign_id, result.visited_scenario_ids, result.battle_results.size()]
	)
	get_tree().quit()