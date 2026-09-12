class_name ContentSnapshot
extends RefCounted


var is_valid := true
var error_message := ""
var content_lock: ContentLock
var mod_api: ModAPI

var _battle_definitions: Dictionary[StringName, BattleDefinition] = {}
var _map_definitions: Dictionary[StringName, BattleMapDefinition] = {}
var _unit_definitions: Dictionary[StringName, UnitDefinition] = {}
var _ai_profile_definitions: Dictionary[StringName, AIProfileDefinition] = {}
var _race_definitions: Dictionary[StringName, RaceDefinition] = {}
var _ability_definitions: Dictionary[StringName, AbilityDefinition] = {}
var _scenario_definitions: Dictionary[StringName, ScenarioDefinition] = {}
var _campaign_definitions: Dictionary[StringName, CampaignDefinition] = {}


func _init(
	p_battle_definitions: Array[BattleDefinition],
	p_map_definitions: Array[BattleMapDefinition],
	p_unit_definitions: Array[UnitDefinition],
	p_ai_profile_definitions: Array[AIProfileDefinition],
	p_race_definitions: Array[RaceDefinition] = [],
	p_ability_definitions: Array[AbilityDefinition] = [],
	p_scenario_definitions: Array[ScenarioDefinition] = [],
	p_campaign_definitions: Array[CampaignDefinition] = [],
	p_content_lock: ContentLock = null,
	p_mod_api: ModAPI = null
) -> void:
	content_lock = p_content_lock
	mod_api = p_mod_api if p_mod_api != null else ModAPI.create_default()
	_register_resources(p_battle_definitions, _battle_definitions, "BattleDefinition")
	_register_resources(p_map_definitions, _map_definitions, "BattleMapDefinition")
	_register_resources(p_unit_definitions, _unit_definitions, "UnitDefinition")
	_register_resources(p_ai_profile_definitions, _ai_profile_definitions, "AIProfileDefinition")
	_register_resources(p_race_definitions, _race_definitions, "RaceDefinition")
	_register_resources(p_ability_definitions, _ability_definitions, "AbilityDefinition")
	_register_resources(p_scenario_definitions, _scenario_definitions, "ScenarioDefinition")
	_register_resources(p_campaign_definitions, _campaign_definitions, "CampaignDefinition")


func get_battle_definition(definition_id: StringName) -> BattleDefinition:
	return _battle_definitions.get(definition_id) as BattleDefinition


func get_map_definition(definition_id: StringName) -> BattleMapDefinition:
	return _map_definitions.get(definition_id) as BattleMapDefinition


func get_unit_definition(definition_id: StringName) -> UnitDefinition:
	return _unit_definitions.get(definition_id) as UnitDefinition


func get_ai_profile_definition(definition_id: StringName) -> AIProfileDefinition:
	return _ai_profile_definitions.get(definition_id) as AIProfileDefinition


func get_race_definition(definition_id: StringName) -> RaceDefinition:
	return _race_definitions.get(definition_id) as RaceDefinition


func get_ability_definition(definition_id: StringName) -> AbilityDefinition:
	return _ability_definitions.get(definition_id) as AbilityDefinition


func get_scenario_definition(definition_id: StringName) -> ScenarioDefinition:
	return _scenario_definitions.get(definition_id) as ScenarioDefinition


func get_campaign_definition(definition_id: StringName) -> CampaignDefinition:
	return _campaign_definitions.get(definition_id) as CampaignDefinition


func get_unit_definition_ids() -> Dictionary[StringName, bool]:
	return _collect_ids(_unit_definitions)


func get_ai_profile_definition_ids() -> Dictionary[StringName, bool]:
	return _collect_ids(_ai_profile_definitions)


func get_race_definition_ids() -> Dictionary[StringName, bool]:
	return _collect_ids(_race_definitions)


func get_ability_definition_ids() -> Dictionary[StringName, bool]:
	return _collect_ids(_ability_definitions)


func get_scenario_definition_ids() -> Dictionary[StringName, bool]:
	return _collect_ids(_scenario_definitions)


func get_campaign_definition_ids() -> Dictionary[StringName, bool]:
	return _collect_ids(_campaign_definitions)


func get_all_unit_definitions() -> Array[UnitDefinition]:
	var result: Array[UnitDefinition] = []

	for definition: UnitDefinition in _unit_definitions.values():
		result.append(definition)

	result.sort_custom(func(left: UnitDefinition, right: UnitDefinition) -> bool:
		return String(left.id) < String(right.id)
	)
	return result


func with_battle_document(
	map_definition: BattleMapDefinition,
	battle_definition: BattleDefinition
) -> ContentSnapshot:
	var battles: Array[BattleDefinition] = []
	var maps: Array[BattleMapDefinition] = []
	var units: Array[UnitDefinition] = []
	var ai_profiles: Array[AIProfileDefinition] = []
	var races: Array[RaceDefinition] = []
	var abilities: Array[AbilityDefinition] = []
	var scenarios: Array[ScenarioDefinition] = []
	var campaigns: Array[CampaignDefinition] = []

	for existing: BattleDefinition in _battle_definitions.values():
		if existing.id != battle_definition.id:
			battles.append(existing)

	for existing: BattleMapDefinition in _map_definitions.values():
		if existing.id != map_definition.id:
			maps.append(existing)

	for definition: UnitDefinition in _unit_definitions.values():
		units.append(definition)
	for definition: AIProfileDefinition in _ai_profile_definitions.values():
		ai_profiles.append(definition)
	for definition: RaceDefinition in _race_definitions.values():
		races.append(definition)
	for definition: AbilityDefinition in _ability_definitions.values():
		abilities.append(definition)
	for definition: ScenarioDefinition in _scenario_definitions.values():
		scenarios.append(definition)
	for definition: CampaignDefinition in _campaign_definitions.values():
		campaigns.append(definition)

	battles.append(battle_definition)
	maps.append(map_definition)
	return ContentSnapshot.new(
		battles,
		maps,
		units,
		ai_profiles,
		races,
		abilities,
		scenarios,
		campaigns,
		content_lock,
		mod_api
	)

func _register_resources(
	definitions: Array,
	registry: Dictionary,
	type_name: String
) -> void:
	for definition: Resource in definitions:
		if definition == null:
			_invalidate("ContentSnapshot contains a null %s." % type_name)
			continue

		_register_definition(
			definition.get("id"),
			definition,
			registry,
			type_name
		)


func _register_definition(
	definition_id: StringName,
	definition: Resource,
	registry: Dictionary,
	type_name: String
) -> void:
	if definition_id.is_empty():
		_invalidate("ContentSnapshot contains %s without an id." % type_name)
		return

	if registry.has(definition_id):
		_invalidate("Duplicate %s id: %s." % [type_name, definition_id])
		return

	registry[definition_id] = definition


func _collect_ids(registry: Dictionary) -> Dictionary[StringName, bool]:
	var result: Dictionary[StringName, bool] = {}

	for definition_id: StringName in registry:
		result[definition_id] = true

	return result


func _invalidate(message: String) -> void:
	if is_valid:
		error_message = message

	is_valid = false