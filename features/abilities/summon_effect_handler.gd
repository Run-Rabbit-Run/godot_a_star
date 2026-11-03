class_name SummonEffectHandler
extends AbilityEffectHandler
## Brings the unit named by `unit_id` into the battle; the setup resolves it from the content.

func affects_hexes() -> bool:
	return true

func validate(effect: AbilityEffectDefinition) -> String:
	if unit_id(effect).is_empty():
		return "Summon effect requires a unit_id."
	if not effect.parameters.get("center_only", false):
		return "Summoning must target the center only."
	return ""

func get_unit_references(effect: AbilityEffectDefinition) -> Array[StringName]:
	var ids: Array[StringName] = [unit_id(effect)]
	return ids

func validate_unit_reference(_effect: AbilityEffectDefinition, unit: UnitDefinition) -> String:
	if unit.base_stats == null:
		return "Summoned unit %s needs stats." % unit.id
	if not unit.ability_ids.is_empty():
		return "Summoned unit %s cannot have unresolved active abilities." % unit.id
	var error := unit.base_stats.validate()
	if not error.is_empty():
		return error
	return PassiveAbilityCatalog.validate(unit.passive_ability_ids, unit.passive_definitions)

func execute_hex(effect: AbilityEffectDefinition, context: BattleEffectContext, source: StringName, hex: Vector2i) -> Array[BattleEvent]:
	var definition := context.get_unit_definition(unit_id(effect))
	if definition == null:
		context.fail("Summoned unit %s is not part of this battle." % unit_id(effect))
		var none: Array[BattleEvent] = []
		return none
	return context.summon(source, hex, definition)

static func unit_id(effect: AbilityEffectDefinition) -> StringName:
	return StringName(str(effect.parameters.get("unit_id", "")))
