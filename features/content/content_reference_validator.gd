class_name ContentReferenceValidator
extends RefCounted

const REFERENCE_FIELDS := ["map_id", "definition_id", "race_id", "presentation_id", "ai_profile_id", "ai_profile_override_id", "battle_id", "entry_scenario_id", "target_scenario_id", "ability_ids", "unit_ids", "scenario_ids", "entry_battle_ids", "entry_campaign_ids", "state_id", "status_id"]

static func validate(packages: Array[ContentPackage], result: ContentLoadResult) -> void:
	for package: ContentPackage in packages:
		var allowed: Array[StringName] = [package.manifest.package_id]
		for dependency: ContentPackageDependency in package.manifest.dependencies:
			allowed.append(dependency.package_id)
		var visited: Dictionary[int, bool] = {}
		_walk(package, allowed, package.manifest.package_id, result, visited)

static func _walk(value: Variant, allowed: Array[StringName], owner: StringName, result: ContentLoadResult, visited: Dictionary[int, bool], field := "") -> void:
	if value is Resource:
		if value is Texture2D or value is PackedScene or value is Script:
			return
		if visited.has(value.get_instance_id()):
			return
		visited[value.get_instance_id()] = true
		for property: Dictionary in value.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE and property.name not in ["script", "resource_path", "resource_name", "resource_local_to_scene"]:
				_walk(value.get(property.name), allowed, owner, result, visited, property.name)
	elif value is Array:
		for item: Variant in value:
			_walk(item, allowed, owner, result, visited, field)
	elif value is Dictionary:
		for key: Variant in value:
			_walk(value[key], allowed, owner, result, visited, str(key))
	elif field in REFERENCE_FIELDS and (value is String or value is StringName) and not str(value).is_empty():
		var parts := str(value).split(":", false)
		if parts.size() < 2 or not allowed.has(StringName(parts[0])):
			result.add_error("Package %s has undeclared reference %s (%s)." % [owner, value, field])
