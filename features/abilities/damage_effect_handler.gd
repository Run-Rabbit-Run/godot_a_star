class_name DamageEffectHandler
extends AbilityEffectHandler


func validate(effect: AbilityEffectDefinition) -> String:
	if effect == null:
		return "Damage effect must not be null."

	var amount: Variant = effect.parameters.get("amount")

	if not (amount is int) or amount <= 0:
		return "Damage effect requires a positive integer amount."
	var splash: Variant = effect.parameters.get("secondary_amount", amount)
	if not (splash is int) or splash <= 0:
		return "Damage effect secondary_amount must be a positive integer."
	var type: Variant = effect.parameters.get("damage_type", "physical")
	if not (type is String or type is StringName) or not UnitStatusService.DAMAGE_TYPES.has(StringName(type)):
		return "Damage effect has an unknown damage_type."

	return ""


func execute(
	effect: AbilityEffectDefinition,
	context: BattleEffectContext,
	source_unit_id: StringName,
	target_unit_id: StringName
) -> Array[BattleEvent]:
	return context.apply_damage_events(
		source_unit_id,
		target_unit_id,
		int(effect.parameters["amount"] if context.get_unit_hex(target_unit_id) == context.target_hex else effect.parameters.get("secondary_amount", effect.parameters["amount"])),
		StringName(effect.parameters.get("damage_type", "physical"))
	)
