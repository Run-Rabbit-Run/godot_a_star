class_name AbilityDefinition
extends Resource


@export var id: StringName
@export var display_name: String
@export var presentation_id: StringName
@export var range := 1
@export_range(0, 8) var area_radius := 0
@export var ends_main_action := true
@export var effects: Array[AbilityEffectDefinition] = []

enum TargetMode { AUTO, ENEMY, HEX, EMPTY_HEX, LINE }
@export var target_mode: TargetMode = TargetMode.AUTO
@export var uses_attack_range := false
@export_range(1, 99) var cooldown_turns := 1
@export_range(0, 99) var initial_cooldown_turns := 0

func targets_hex() -> bool:
	return target_mode in [TargetMode.HEX, TargetMode.EMPTY_HEX, TargetMode.LINE] or (target_mode == TargetMode.AUTO and area_radius > 0)

func get_range(unit: UnitState) -> int:
	return unit.basic_attack_range if uses_attack_range else range

func validate() -> String:
	if range < 1 or area_radius < 0 or area_radius > 8 or cooldown_turns < 1 or initial_cooldown_turns < 0:
		return "Invalid ability range, radius or cooldown."
	if target_mode < TargetMode.AUTO or target_mode > TargetMode.LINE:
		return "Unknown ability target mode."
	if not ends_main_action:
		return "Every active ability must spend the main action and end the turn."
	if effects.is_empty():
		return "Ability must have effects."
	for effect: AbilityEffectDefinition in effects:
		if effect == null:
			return "Ability contains a null effect."
		if effect.effect_type_id == &"core:summon" and (target_mode != TargetMode.EMPTY_HEX or effects.size() != 1 or area_radius != 0):
			return "Summoning requires a single effect on an empty hex with radius zero."
	return ""
