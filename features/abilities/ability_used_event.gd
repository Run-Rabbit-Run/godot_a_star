class_name AbilityUsedEvent
extends BattleEvent


var user_id: StringName
var target_id: StringName
var ability_id: StringName


func _init(
	p_user_id: StringName,
	p_target_id: StringName,
	p_ability_id: StringName
) -> void:
	user_id = p_user_id
	target_id = p_target_id
	ability_id = p_ability_id