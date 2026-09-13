class_name AreaAbilityUsedEvent
extends BattleEvent


var user_id: StringName
var ability_id: StringName
var target_hex: Vector2i
var affected_hexes: Array[Vector2i] = []


func _init(
	p_user_id: StringName,
	p_ability_id: StringName,
	p_target_hex: Vector2i,
	p_affected_hexes: Array[Vector2i]
) -> void:
	user_id = p_user_id
	ability_id = p_ability_id
	target_hex = p_target_hex
	affected_hexes.assign(p_affected_hexes)
