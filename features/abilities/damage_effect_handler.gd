class_name DamageEffectHandler
extends AbilityEffectHandler


func validate(effect: AbilityEffectDefinition) -> String:
	if effect == null:
		return "Damage effect must not be null."

	if not effect.parameters.get("affects_obstacles", true) is bool:
		return "Damage affects_obstacles must be boolean."
	if not effect.parameters.get("use_base_attack", false) is bool:
		return "Damage use_base_attack must be boolean."
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
		_amount(effect, context, source_unit_id, context.get_unit_hex(target_unit_id)),
		StringName(effect.parameters.get("damage_type", "physical"))
	)


## Each struck obstacle takes damage once per effect, measured at its hex nearest the center.
func execute_obstacles(effect: AbilityEffectDefinition, context: BattleEffectContext, source_unit_id: StringName, hexes: Array[Vector2i]) -> Array[BattleEvent]:
	var events: Array[BattleEvent] = []
	if not effect.parameters.get("affects_obstacles", true):
		return events
	var ordered := hexes.duplicate()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return HexGrid.get_distance(context.target_hex, a) < HexGrid.get_distance(context.target_hex, b))
	var struck: Dictionary[StringName, bool] = {}
	for hex: Vector2i in ordered:
		var obstacle := context.get_obstacle(hex)
		if obstacle == null or struck.has(obstacle.id):
			continue
		struck[obstacle.id] = true
		events.append_array(context.damage_obstacle(hex, _amount(effect, context, source_unit_id, hex)))
	return events


## Full amount at the center, the secondary amount elsewhere, or the source's base attack.
func _amount(effect: AbilityEffectDefinition, context: BattleEffectContext, source_unit_id: StringName, hex: Vector2i) -> int:
	if effect.parameters.get("use_base_attack", false):
		return context.get_base_attack_damage(source_unit_id)
	return int(effect.parameters["amount"] if hex == context.target_hex else effect.parameters.get("secondary_amount", effect.parameters["amount"]))
