class_name SummonEffectHandler
extends AbilityEffectHandler

func affects_hexes() -> bool:
	return true

func validate(effect: AbilityEffectDefinition) -> String:
	var definition: Variant = effect.parameters.get("unit")
	if not definition is UnitDefinition or definition.base_stats == null:
		return "Summon effect requires a unit definition and stats."
	if definition.id.is_empty() or not definition.ability_ids.is_empty():
		return "Summoned unit needs an ID and cannot have unresolved active abilities."
	var stats: UnitStatsDefinition = definition.base_stats
	var error := stats.validate()
	if not error.is_empty():
		return error
	if not effect.parameters.get("center_only", false):
		return "Summoning must target the center only."
	return PassiveAbilityCatalog.validate(definition.passive_ability_ids)

func execute_hex(effect: AbilityEffectDefinition, context: BattleEffectContext, source: StringName, hex: Vector2i) -> Array[BattleEvent]:
	return context.summon(source, hex, effect.parameters["unit"] as UnitDefinition)
