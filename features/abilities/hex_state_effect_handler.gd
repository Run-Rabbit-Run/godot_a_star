class_name HexStateEffectHandler
extends AbilityEffectHandler

func affects_hexes() -> bool:
	return true

func validate(effect: AbilityEffectDefinition) -> String:
	var value: Variant = effect.parameters.get("state_id", "")
	if not (value is String or value is StringName):
		return "Hex state effect state_id must be text."
	var id := StringName(value)
	return "" if HexStateCatalog.has_state(id) else "Hex state effect requires a known state_id."

func execute_hex(effect: AbilityEffectDefinition, context: BattleEffectContext, _source: StringName, hex: Vector2i) -> Array[BattleEvent]:
	return context.apply_hex_state(hex, StringName(effect.parameters["state_id"]))

func execute_hexes(effect: AbilityEffectDefinition, context: BattleEffectContext, _source: StringName, hexes: Array[Vector2i]) -> Array[BattleEvent]:
	return context.apply_hex_states(hexes, StringName(effect.parameters["state_id"]))

func execute(effect: AbilityEffectDefinition, context: BattleEffectContext, source: StringName, target: StringName) -> Array[BattleEvent]:
	return execute_hex(effect, context, source, context.get_unit_hex(target))
