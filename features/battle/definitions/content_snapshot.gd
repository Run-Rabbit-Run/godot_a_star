class_name ContentSnapshot
extends RefCounted


var is_valid := true
var error_message := ""

var _battle_definitions: Dictionary[StringName, BattleDefinition] = {}
var _map_definitions: Dictionary[StringName, BattleMapDefinition] = {}
var _unit_definitions: Dictionary[StringName, UnitDefinition] = {}
var _ai_profile_definitions: Dictionary[StringName, AIProfileDefinition] = {}


func _init(
	p_battle_definitions: Array[BattleDefinition],
	p_map_definitions: Array[BattleMapDefinition],
	p_unit_definitions: Array[UnitDefinition],
	p_ai_profile_definitions: Array[AIProfileDefinition]
) -> void:
	_register_battles(p_battle_definitions)
	_register_maps(p_map_definitions)
	_register_units(p_unit_definitions)
	_register_ai_profiles(p_ai_profile_definitions)


func get_battle_definition(definition_id: StringName) -> BattleDefinition:
	return _battle_definitions.get(definition_id) as BattleDefinition


func get_map_definition(definition_id: StringName) -> BattleMapDefinition:
	return _map_definitions.get(definition_id) as BattleMapDefinition


func get_unit_definition(definition_id: StringName) -> UnitDefinition:
	return _unit_definitions.get(definition_id) as UnitDefinition


func get_ai_profile_definition(
	definition_id: StringName
) -> AIProfileDefinition:
	return _ai_profile_definitions.get(definition_id) as AIProfileDefinition


func get_unit_definition_ids() -> Dictionary[StringName, bool]:
	return _collect_ids(_unit_definitions)


func get_ai_profile_definition_ids() -> Dictionary[StringName, bool]:
	return _collect_ids(_ai_profile_definitions)


func _register_battles(definitions: Array[BattleDefinition]) -> void:
	for definition: BattleDefinition in definitions:
		if definition == null:
			_invalidate("ContentSnapshot contains a null BattleDefinition.")
			continue

		_register_definition(
			definition.id,
			definition,
			_battle_definitions,
			"BattleDefinition"
		)


func _register_maps(definitions: Array[BattleMapDefinition]) -> void:
	for definition: BattleMapDefinition in definitions:
		if definition == null:
			_invalidate("ContentSnapshot contains a null BattleMapDefinition.")
			continue

		_register_definition(
			definition.id,
			definition,
			_map_definitions,
			"BattleMapDefinition"
		)


func _register_units(definitions: Array[UnitDefinition]) -> void:
	for definition: UnitDefinition in definitions:
		if definition == null:
			_invalidate("ContentSnapshot contains a null UnitDefinition.")
			continue

		_register_definition(
			definition.id,
			definition,
			_unit_definitions,
			"UnitDefinition"
		)


func _register_ai_profiles(
	definitions: Array[AIProfileDefinition]
) -> void:
	for definition: AIProfileDefinition in definitions:
		if definition == null:
			_invalidate("ContentSnapshot contains a null AIProfileDefinition.")
			continue

		_register_definition(
			definition.id,
			definition,
			_ai_profile_definitions,
			"AIProfileDefinition"
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
