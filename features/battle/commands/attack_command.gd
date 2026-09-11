class_name AttackCommand
extends BattleCommand


var attacker_id: StringName
var target_id: StringName


func _init(
	p_attacker_id: StringName,
	p_target_id: StringName
) -> void:
	attacker_id = p_attacker_id
	target_id = p_target_id
