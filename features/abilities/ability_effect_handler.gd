class_name AbilityEffectHandler
extends RefCounted


func validate(_effect: AbilityEffectDefinition) -> String:
	return "Ability effect handler does not implement validation."


func execute(
	_effect: AbilityEffectDefinition,
	_context: BattleEffectContext,
	_source_unit_id: StringName,
	_target_unit_id: StringName
) -> Array[BattleEvent]:
	var events: Array[BattleEvent] = []
	return events