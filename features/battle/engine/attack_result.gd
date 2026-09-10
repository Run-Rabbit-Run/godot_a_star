class_name AttackResult
extends RefCounted


var is_successful: bool
var attacker_id: StringName
var target_id: StringName
var damage: int
var target_health_remaining: int


func _init(
	p_is_successful: bool,
	p_attacker_id: StringName,
	p_target_id: StringName,
	p_damage: int,
	p_target_health_remaining: int
) -> void:
	is_successful = p_is_successful
	attacker_id = p_attacker_id
	target_id = p_target_id
	damage = maxi(p_damage, 0)
	target_health_remaining = maxi(p_target_health_remaining, 0)


static func failure() -> AttackResult:
	return AttackResult.new(
		false,
		StringName(),
		StringName(),
		0,
		0
	)


static func success(
	p_attacker_id: StringName,
	p_target_id: StringName,
	p_damage: int,
	p_target_health_remaining: int
) -> AttackResult:
	return AttackResult.new(
		true,
		p_attacker_id,
		p_target_id,
		p_damage,
		p_target_health_remaining
	)


func is_target_defeated() -> bool:
	return is_successful and target_health_remaining == 0
