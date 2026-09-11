class_name UnitSpawnData
extends RefCounted


var unit_id: StringName
var placement_id: StringName
var definition_id: StringName
var unit_definition: UnitDefinition
var side_id: StringName
var faction: BattleFaction.Value
var control_source: BattleControlSource.Value
var ai_profile_id: StringName
var ai_profile_definition: AIProfileDefinition
var hex: Vector2i
var modifiers: Dictionary


func _init(
	p_unit_id: StringName,
	p_placement_id: StringName,
	p_definition_id: StringName,
	p_unit_definition: UnitDefinition,
	p_side_id: StringName,
	p_faction: BattleFaction.Value,
	p_control_source: BattleControlSource.Value,
	p_ai_profile_id: StringName,
	p_ai_profile_definition: AIProfileDefinition,
	p_hex: Vector2i,
	p_modifiers: Dictionary = {}
) -> void:
	unit_id = p_unit_id
	placement_id = p_placement_id
	definition_id = p_definition_id
	unit_definition = p_unit_definition
	side_id = p_side_id
	faction = p_faction
	control_source = p_control_source
	ai_profile_id = p_ai_profile_id
	ai_profile_definition = p_ai_profile_definition
	hex = p_hex
	modifiers = p_modifiers.duplicate(true)
