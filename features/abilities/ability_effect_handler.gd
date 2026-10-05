class_name AbilityEffectHandler
extends RefCounted


func affects_hexes() -> bool:
	return false


func execute_hex(_effect: AbilityEffectDefinition, _context: BattleEffectContext, _source_unit_id: StringName, _hex: Vector2i) -> Array[BattleEvent]:
	var events: Array[BattleEvent] = []
	return events


## Applies the effect to the whole affected area. The default handles cells one by one;
## handlers whose cells interact (terrain reactions) override it to resolve the area at once.
func execute_hexes(effect: AbilityEffectDefinition, context: BattleEffectContext, source_unit_id: StringName, hexes: Array[Vector2i]) -> Array[BattleEvent]:
	var events: Array[BattleEvent] = []
	for hex: Vector2i in hexes:
		events.append_array(execute_hex(effect, context, source_unit_id, hex))
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
