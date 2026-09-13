class_name UseAbilityCommand
extends BattleCommand


var user_id: StringName
var target_id: StringName
var ability_id: StringName
var target_hex := Vector2i.ZERO
var targets_hex := false


func _init(
	p_user_id: StringName,
	p_target_id: StringName,
	p_ability_id: StringName
) -> void:
	user_id = p_user_id
	target_id = p_target_id
	ability_id = p_ability_id


static func at_hex(
	p_user_id: StringName,
	p_target_hex: Vector2i,
	p_ability_id: StringName
) -> UseAbilityCommand:
	var command := UseAbilityCommand.new(
		p_user_id,
		StringName(),
		p_ability_id
	)
	command.target_hex = p_target_hex
	command.targets_hex = true
	return command
