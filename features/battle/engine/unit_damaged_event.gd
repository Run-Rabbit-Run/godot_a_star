class_name UnitDamagedEvent
extends BattleEvent


var attacker_id: StringName
var target_id: StringName
var damage: int
var target_health_remaining: int
var target_defeated: bool
var source_hex_state_id: StringName
var source_ability_id: StringName
var source_status_id: StringName
var damage_type: StringName = &"physical"
## Calculation captured at impact, before later status/terrain changes.
var base_damage: int
var calculated_damage: int
## Ordered signed adjustments: {source_id: StringName, amount: int}.
var damage_modifiers: Array[Dictionary] = []


func _init(
	p_attacker_id: StringName,
	p_target_id: StringName,
	p_damage: int,
	p_target_health_remaining: int,
	p_target_defeated: bool,
	p_source_hex_state_id: StringName = StringName(),
	p_source_ability_id: StringName = StringName()
) -> void:
	attacker_id = p_attacker_id
	target_id = p_target_id
	damage = maxi(p_damage, 0)
	base_damage = damage
	calculated_damage = damage
	target_health_remaining = maxi(p_target_health_remaining, 0)
	target_defeated = p_target_defeated
	source_hex_state_id = p_source_hex_state_id
	source_ability_id = p_source_ability_id
