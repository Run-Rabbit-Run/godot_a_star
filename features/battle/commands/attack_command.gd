class_name AttackCommand
extends BattleCommand


var attacker_id: StringName
var target_id: StringName
## The damage type the attacker chooses, "" for its current one. Another type needs the
## attacker's choice passive; the chosen type stays the attacker's type after the attack.
var damage_type: StringName


func _init(
	p_attacker_id: StringName,
	p_target_id: StringName,
	p_damage_type: StringName = &""
) -> void:
	attacker_id = p_attacker_id
	target_id = p_target_id
	damage_type = p_damage_type
