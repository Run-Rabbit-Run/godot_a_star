class_name LandingEffectHandler
extends AbilityEffectHandler
## Drops the unit named by `unit_id` onto a hex missing from the battlefield next to it. The hex
## (`terrain_id`, default core:landing_pad) joins the field and is held by the unit: it leaves the
## battlefield again with everything on it once the unit is defeated (HeldHexService).

const DEFAULT_TERRAIN := &"core:landing_pad"


func affects_hexes() -> bool:
	return true


func validate(effect: AbilityEffectDefinition) -> String:
	if unit_id(effect).is_empty():
		return "Landing effect requires a unit_id."
	if not effect.parameters.get("center_only", false):
		return "Landing must target the center only."
	return ""


func get_unit_references(effect: AbilityEffectDefinition) -> Array[StringName]:
	var ids: Array[StringName] = [unit_id(effect)]
	return ids


func validate_unit_reference(_effect: AbilityEffectDefinition, unit: UnitDefinition) -> String:
	if unit.base_stats == null:
		return "Landing unit %s needs stats." % unit.id
	if not unit.ability_ids.is_empty():
		return "Landing unit %s cannot have unresolved active abilities." % unit.id
	var error := unit.base_stats.validate()
	if not error.is_empty():
		return error
	return PassiveAbilityCatalog.validate(unit.passive_ability_ids, unit.passive_definitions)


func execute_hex(effect: AbilityEffectDefinition, context: BattleEffectContext, source: StringName, hex: Vector2i) -> Array[BattleEvent]:
	var definition := context.get_unit_definition(unit_id(effect))
	if definition == null:
		context.fail("Landing unit %s is not part of this battle." % unit_id(effect))
		var none: Array[BattleEvent] = []
		return none
	var terrain := StringName(str(effect.parameters.get("terrain_id", DEFAULT_TERRAIN)))
	return context.land(source, hex, definition, terrain)


static func unit_id(effect: AbilityEffectDefinition) -> StringName:
	return StringName(str(effect.parameters.get("unit_id", "")))
