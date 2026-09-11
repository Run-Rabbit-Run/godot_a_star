class_name BattleSideData
extends RefCounted


var side_id: StringName
var faction: BattleFaction.Value
var control_source: BattleControlSource.Value
var ai_profile_definition: AIProfileDefinition


func _init(
	p_side_id: StringName,
	p_faction: BattleFaction.Value,
	p_control_source: BattleControlSource.Value,
	p_ai_profile_definition: AIProfileDefinition
) -> void:
	side_id = p_side_id
	faction = p_faction
	control_source = p_control_source
	ai_profile_definition = p_ai_profile_definition
