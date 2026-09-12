class_name ContentLoader
extends RefCounted


const CONTENT_SCHEMA_VERSION := 1


static func load_packages(
	packages: Array[ContentPackage],
	mod_api: ModAPI = null
) -> ContentLoadResult:
	var result := ContentLoadResult.new()
	var api := mod_api if mod_api != null else ModAPI.create_default()
	var packages_by_id: Dictionary[StringName, ContentPackage] = {}

	for package: ContentPackage in packages:
		_validate_manifest(package, packages_by_id, result)

	if not result.errors.is_empty():
		return result

	for package: ContentPackage in packages:
		_validate_dependencies(package, packages_by_id, result)

	if not result.errors.is_empty():
		return result

	var ordered := _resolve_order(packages_by_id, result)

	if not result.errors.is_empty():
		return result

	var battles: Array[BattleDefinition] = []
	var maps: Array[BattleMapDefinition] = []
	var units: Array[UnitDefinition] = []
	var ai_profiles: Array[AIProfileDefinition] = []
	var races: Array[RaceDefinition] = []
	var abilities: Array[AbilityDefinition] = []
	var scenarios: Array[ScenarioDefinition] = []
	var campaigns: Array[CampaignDefinition] = []
	var lock_entries: Array[ContentLockEntry] = []
	var ids_by_type: Dictionary[String, Dictionary] = {}

	for package: ContentPackage in ordered:
		_collect_package(
			package,
			battles,
			maps,
			units,
			ai_profiles,
			races,
			abilities,
			scenarios,
			campaigns,
			ids_by_type,
			result
		)
		lock_entries.append(_create_lock_entry(package))

	if not result.errors.is_empty():
		return result

	var snapshot := ContentSnapshot.new(
		battles,
		maps,
		units,
		ai_profiles,
		races,
		abilities,
		scenarios,
		campaigns,
		ContentLock.new(ModAPI.VERSION, lock_entries),
		api
	)

	if not snapshot.is_valid:
		result.add_error(snapshot.error_message)
		return result

	_validate_references(snapshot, api, result)

	if result.errors.is_empty():
		result.snapshot = snapshot

	return result


static func _validate_manifest(
	package: ContentPackage,
	packages_by_id: Dictionary[StringName, ContentPackage],
	result: ContentLoadResult
) -> void:
	if package == null or package.manifest == null:
		result.add_error("Content package requires a manifest.")
		return

	var manifest := package.manifest

	if manifest.package_id.is_empty():
		result.add_error("Content package has an empty package_id.")
		return

	if packages_by_id.has(manifest.package_id):
		result.add_error("Duplicate package_id: %s." % manifest.package_id)
		return

	if manifest.package_version.is_empty():
		result.add_error(
			"Package %s has an empty package_version." % manifest.package_id
		)

	if manifest.content_schema_version != CONTENT_SCHEMA_VERSION:
		result.add_error(
			"Package %s uses unsupported content schema %s."
			% [manifest.package_id, manifest.content_schema_version]
		)

	if manifest.rules_api_version != ModAPI.VERSION:
		result.add_error(
			"Package %s requires rules API %s, current is %s."
			% [manifest.package_id, manifest.rules_api_version, ModAPI.VERSION]
		)

	if manifest.has_executable_extensions:
		result.add_warning(
			"Package %s declares executable extensions; data loader does not execute them."
			% manifest.package_id
		)

	packages_by_id[manifest.package_id] = package


static func _validate_dependencies(
	package: ContentPackage,
	packages_by_id: Dictionary[StringName, ContentPackage],
	result: ContentLoadResult
) -> void:
	for dependency: ContentPackageDependency in package.manifest.dependencies:
		if dependency == null:
			result.add_error(
				"Package %s contains a null dependency."
				% package.manifest.package_id
			)
			continue

		var required := packages_by_id.get(dependency.package_id) as ContentPackage

		if required == null:
			result.add_error(
				"Package %s is missing dependency %s."
				% [package.manifest.package_id, dependency.package_id]
			)
			continue

		if (
			not dependency.exact_version.is_empty()
			and required.manifest.package_version != dependency.exact_version
		):
			result.add_error(
				"Package %s requires %s version %s, found %s."
				% [
					package.manifest.package_id,
					dependency.package_id,
					dependency.exact_version,
					required.manifest.package_version,
				]
			)


static func _resolve_order(
	packages_by_id: Dictionary[StringName, ContentPackage],
	result: ContentLoadResult
) -> Array[ContentPackage]:
	var ordered: Array[ContentPackage] = []
	var resolved: Dictionary[StringName, bool] = {}
	var package_ids: Array[StringName] = []
	package_ids.assign(packages_by_id.keys())
	package_ids.sort()

	while ordered.size() < packages_by_id.size():
		var made_progress := false

		for package_id: StringName in package_ids:
			if resolved.has(package_id):
				continue

			var package := packages_by_id[package_id]
			var dependencies_ready := true

			for dependency: ContentPackageDependency in package.manifest.dependencies:
				if not resolved.has(dependency.package_id):
					dependencies_ready = false
					break

			if not dependencies_ready:
				continue

			ordered.append(package)
			resolved[package_id] = true
			made_progress = true

		if not made_progress:
			result.add_error("Content package dependency cycle detected.")
			return []

	return ordered


static func _collect_package(
	package: ContentPackage,
	battles: Array[BattleDefinition],
	maps: Array[BattleMapDefinition],
	units: Array[UnitDefinition],
	ai_profiles: Array[AIProfileDefinition],
	races: Array[RaceDefinition],
	abilities: Array[AbilityDefinition],
	scenarios: Array[ScenarioDefinition],
	campaigns: Array[CampaignDefinition],
	ids_by_type: Dictionary[String, Dictionary],
	result: ContentLoadResult
) -> void:
	_collect_definitions(package, "battle", package.battles, battles, ids_by_type, result)
	_collect_definitions(package, "map", package.maps, maps, ids_by_type, result)
	_collect_definitions(package, "unit", package.units, units, ids_by_type, result)
	_collect_definitions(package, "ai_profile", package.ai_profiles, ai_profiles, ids_by_type, result)
	_collect_definitions(package, "race", package.races, races, ids_by_type, result)
	_collect_definitions(package, "ability", package.abilities, abilities, ids_by_type, result)
	_collect_definitions(package, "scenario", package.scenarios, scenarios, ids_by_type, result)
	_collect_definitions(package, "campaign", package.campaigns, campaigns, ids_by_type, result)


static func _collect_definitions(
	package: ContentPackage,
	type_name: String,
	definitions: Array,
	target: Array,
	ids_by_type: Dictionary[String, Dictionary],
	result: ContentLoadResult
) -> void:
	var known_ids: Dictionary = ids_by_type.get(type_name, {})
	ids_by_type[type_name] = known_ids
	var namespace_prefix := "%s:" % package.manifest.package_id

	for definition: Resource in definitions:
		if definition == null:
			result.add_error(
				"Package %s contains a null %s definition."
				% [package.manifest.package_id, type_name]
			)
			continue

		var definition_id: StringName = definition.get("id")

		if not String(definition_id).begins_with(namespace_prefix):
			result.add_error(
				"Package %s definition %s must use namespace %s."
				% [package.manifest.package_id, definition_id, namespace_prefix]
			)
			continue

		if known_ids.has(definition_id):
			result.add_error(
				"Duplicate %s definition_id %s in package %s."
				% [type_name, definition_id, package.manifest.package_id]
			)
			continue

		known_ids[definition_id] = package.manifest.package_id
		target.append(definition)


static func _validate_references(
	snapshot: ContentSnapshot,
	api: ModAPI,
	result: ContentLoadResult
) -> void:
	for race_id: StringName in snapshot.get_race_definition_ids():
		var race := snapshot.get_race_definition(race_id)

		for unit_id: StringName in race.unit_ids:
			if snapshot.get_unit_definition(unit_id) == null:
				result.add_error(
					"RaceDefinition %s references missing UnitDefinition %s."
					% [race.id, unit_id]
				)

	for unit: UnitDefinition in snapshot.get_all_unit_definitions():
		if not unit.race_id.is_empty() and snapshot.get_race_definition(unit.race_id) == null:
			result.add_error(
				"UnitDefinition %s references missing RaceDefinition %s."
				% [unit.id, unit.race_id]
			)

		for ability_id: StringName in unit.ability_ids:
			if snapshot.get_ability_definition(ability_id) == null:
				result.add_error(
					"UnitDefinition %s references missing AbilityDefinition %s."
					% [unit.id, ability_id]
				)

	for ability_id: StringName in snapshot.get_ability_definition_ids():
		var ability := snapshot.get_ability_definition(ability_id)

		if ability.effects.is_empty():
			result.add_error("AbilityDefinition %s has no effects." % ability.id)

		for effect: AbilityEffectDefinition in ability.effects:
			if effect == null:
				result.add_error("AbilityDefinition %s contains a null effect." % ability.id)
				continue

			var handler := api.get_effect_handler(effect.effect_type_id)

			if handler == null:
				result.add_error(
					"AbilityDefinition %s requires missing effect handler %s."
					% [ability.id, effect.effect_type_id]
				)
				continue

			var error := handler.validate(effect)

			if not error.is_empty():
				result.add_error("AbilityDefinition %s: %s" % [ability.id, error])

	_validate_scenarios(snapshot, result)


static func _validate_scenarios(
	snapshot: ContentSnapshot,
	result: ContentLoadResult
) -> void:
	for campaign_id: StringName in snapshot.get_campaign_definition_ids():
		var campaign := snapshot.get_campaign_definition(campaign_id)

		if snapshot.get_scenario_definition(campaign.entry_scenario_id) == null:
			result.add_error(
				"CampaignDefinition %s has missing entry scenario %s."
				% [campaign.id, campaign.entry_scenario_id]
			)

		for scenario_id: StringName in campaign.scenario_ids:
			if snapshot.get_scenario_definition(scenario_id) == null:
				result.add_error(
					"CampaignDefinition %s references missing scenario %s."
					% [campaign.id, scenario_id]
				)

	for scenario_id: StringName in snapshot.get_scenario_definition_ids():
		var scenario := snapshot.get_scenario_definition(scenario_id)

		if snapshot.get_battle_definition(scenario.battle_id) == null:
			result.add_error(
				"ScenarioDefinition %s references missing battle %s."
				% [scenario.id, scenario.battle_id]
			)

		for transition: ScenarioTransitionDefinition in scenario.transitions:
			if transition == null:
				result.add_error("ScenarioDefinition %s contains a null transition." % scenario.id)
			elif (
				not transition.ends_campaign
				and snapshot.get_scenario_definition(transition.target_scenario_id) == null
			):
				result.add_error(
					"ScenarioDefinition %s transition references missing scenario %s."
					% [scenario.id, transition.target_scenario_id]
				)


static func _create_lock_entry(package: ContentPackage) -> ContentLockEntry:
	var ids: Array[String] = []

	for definitions: Array in [
		package.battles,
		package.maps,
		package.units,
		package.ai_profiles,
		package.races,
		package.abilities,
		package.scenarios,
		package.campaigns,
	]:
		for definition: Resource in definitions:
			if definition != null:
				ids.append(String(definition.get("id")))

	ids.sort()
	var fingerprint := "%s|%s|%s" % [
		package.manifest.package_id,
		package.manifest.package_version,
		",".join(ids),
	]
	return ContentLockEntry.new(
		package.manifest.package_id,
		package.manifest.package_version,
		fingerprint.sha256_text()
	)