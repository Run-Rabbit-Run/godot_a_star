class_name UnitStatsDefinition
extends Resource


@export_range(0, 100, 1)
var movement_points := 0

@export_range(1, 9999, 1)
var max_health := 1

@export_range(0, 9999, 1)
var basic_attack_damage := 0

@export_range(1, 20, 1)
var basic_attack_range := 1

@export_range(0, 9999, 1)
var armor_levels := 0


func validate() -> String:
	if movement_points < 0 or movement_points > 100:
		return "Movement points must be between 0 and 100."
	if max_health < 1 or max_health > 9999 or basic_attack_damage < 0 or basic_attack_damage > 9999:
		return "Invalid health or attack damage."
	if basic_attack_range < 1 or basic_attack_range > 20:
		return "Attack range must be between 1 and 20."
	if armor_levels < 0 or armor_levels > 9999:
		return "Armor levels must be between 0 and 9999."
	return ""
