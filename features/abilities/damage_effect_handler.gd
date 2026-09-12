class_name DamageEffectHandler
extends AbilityEffectHandler


func validate(effect: AbilityEffectDefinition) -> String:
	if effect == null:
		return "Damage effect must not be null."

	var amount: Variant = effect.parameters.get("amount")

	if not (amount is int) or amount <= 0:
		return "Damage effect requires a positive integer amount."

	return ""


func execute(
	effect: AbilityEffectDefinition,
	context: BattleEffectContext,
	source_unit_id: StringName,
	target_unit_id: StringName
) -> Array[BattleEvent]:
	var events: Array[BattleEvent] = []
	var event := context.apply_damage(
		source_unit_id,
		target_unit_id,
		int(effect.parameters["amount"])
	)

	if event != null:
		events.append(event)

	return events