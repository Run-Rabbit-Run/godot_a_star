class_name UnitStatusEffectHandler
extends AbilityEffectHandler

func validate(effect: AbilityEffectDefinition) -> String:
	var value: Variant = effect.parameters.get("status_id", "")
	if not (value is String or value is StringName):
		return "Unit status effect status_id must be text."
	var id := StringName(value)
	var levels: Variant = effect.parameters.get("levels")
	if not UnitStatusCatalog.has_status(id) or not levels is int or levels <= 0:
		return "Unit status effect requires a known status_id and positive integer levels."
	return ""

func execute(effect: AbilityEffectDefinition, context: BattleEffectContext, _source: StringName, target: StringName) -> Array[BattleEvent]:
	return context.apply_unit_status(target, StringName(effect.parameters["status_id"]), int(effect.parameters["levels"]))
