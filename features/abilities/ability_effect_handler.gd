class_name AbilityEffectHandler
extends RefCounted


func affects_hexes() -> bool:
	return false


func execute_hex(_effect: AbilityEffectDefinition, _context: BattleEffectContext, _source_unit_id: StringName, _hex: Vector2i) -> Array[BattleEvent]:
	var events: Array[BattleEvent] = []
	return events


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
