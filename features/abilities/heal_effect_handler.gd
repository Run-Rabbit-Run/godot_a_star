class_name HealEffectHandler
extends AbilityEffectHandler
## `core:heal`: restores `amount` health to each living target whose body is `body`. A living
## body is healed, a mechanical one repaired; a unit of the other body is passed over, and a
## unit-targeted ability cannot choose it. Health never rises above the maximum.


static func body_of(effect: AbilityEffectDefinition) -> StringName:
	return StringName(effect.parameters.get("body", UnitBody.LIVING))


func validate(effect: AbilityEffectDefinition) -> String:
	if effect == null:
		return "Heal effect must not be null."
	var amount: Variant = effect.parameters.get("amount")
	if not amount is int or amount <= 0:
		return "Heal effect requires a positive integer amount."
	var body: Variant = effect.parameters.get("body", UnitBody.LIVING)
	if not (body is String or body is StringName) or not UnitBody.is_known(StringName(body)):
		return "Heal effect has an unknown body."
	return ""


func accepts_target(effect: AbilityEffectDefinition, target: UnitState) -> bool:
	return target.body == body_of(effect)


func execute(effect: AbilityEffectDefinition, context: BattleEffectContext, source_unit_id: StringName, target_unit_id: StringName) -> Array[BattleEvent]:
	return context.heal(source_unit_id, target_unit_id, int(effect.parameters["amount"]), body_of(effect))
