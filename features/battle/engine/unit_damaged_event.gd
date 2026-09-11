class_name UnitDamagedEvent
extends BattleEvent


var attacker_id: StringName
var target_id: StringName
var damage: int
var target_health_remaining: int
var target_defeated: bool


func _init(
	p_attacker_id: StringName,
	p_target_id: StringName,
	p_damage: int,
	p_target_health_remaining: int,
	p_target_defeated: bool
) -> void:
	attacker_id = p_attacker_id
	target_id = p_target_id
	damage = maxi(p_damage, 0)
	target_health_remaining = maxi(p_target_health_remaining, 0)
	target_defeated = p_target_defeated