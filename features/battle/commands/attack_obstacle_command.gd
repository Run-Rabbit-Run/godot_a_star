class_name AttackObstacleCommand
extends BattleCommand

var attacker_id: StringName
var target_hex: Vector2i

func _init(p_attacker_id: StringName, p_target_hex: Vector2i) -> void:
	attacker_id = p_attacker_id
	target_hex = p_target_hex
