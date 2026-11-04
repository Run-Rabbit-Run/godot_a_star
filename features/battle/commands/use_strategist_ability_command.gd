class_name UseStrategistAbilityCommand
extends BattleCommand
## The faction's strategist uses one of its abilities at a hex.

var faction: BattleFaction.Value
var ability_id: StringName
var target_hex: Vector2i


func _init(p_faction: BattleFaction.Value, p_ability_id: StringName, p_target_hex: Vector2i) -> void:
	faction = p_faction
	ability_id = p_ability_id
	target_hex = p_target_hex
