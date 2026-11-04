class_name PushEffectHandler
extends AbilityEffectHandler
## Pushes each living target `distance` hexes straight away from the ability's user; what
## stops it and the collision damage follow PushService. A target off the six axes of the
## user's hex has no straight line away and stays in place.

const MAX_DISTANCE := 8


func validate(effect: AbilityEffectDefinition) -> String:
	if effect == null:
		return "Push effect must not be null."
	var distance: Variant = effect.parameters.get("distance")
	if not distance is int or distance < 1 or distance > MAX_DISTANCE:
		return "Push effect requires an integer distance from 1 to %d." % MAX_DISTANCE
	return ""


func execute(effect: AbilityEffectDefinition, context: BattleEffectContext, source_unit_id: StringName, target_unit_id: StringName) -> Array[BattleEvent]:
	return context.push(source_unit_id, target_unit_id, int(effect.parameters["distance"]))
