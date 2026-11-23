class_name PositioningEffectHandler
extends AbilityEffectHandler

const EFFECT_ID := &"core:positioning"
const OPERATIONS := [&"attract", &"shot_push", &"shot_pull", &"ram", &"grapple", &"recoil", &"swap", &"fissure", &"intercept", &"dash"]


func validate(effect: AbilityEffectDefinition) -> String:
	if effect == null or not effect.parameters.get("operation") is String or not OPERATIONS.has(StringName(effect.parameters.operation)):
		return "Positioning effect requires a supported operation."
	return ""


func affects_hexes() -> bool:
	return true


func execute_hexes(effect: AbilityEffectDefinition, context: BattleEffectContext, source_unit_id: StringName, hexes: Array[Vector2i]) -> Array[BattleEvent]:
	return context.apply_positioning(StringName(effect.parameters.operation), source_unit_id, hexes)


static func can_target(state: BattleState, actor: UnitState, ability: AbilityDefinition, center: Vector2i) -> bool:
	for effect: AbilityEffectDefinition in ability.effects:
		if effect != null and effect.effect_type_id == EFFECT_ID and not PositioningAbilityService.can_target(state, actor, StringName(str(effect.parameters.get("operation", ""))), center):
			return false
	return true


static func creates_fissure(ability: AbilityDefinition) -> bool:
	for effect: AbilityEffectDefinition in ability.effects:
		if effect != null and effect.effect_type_id == EFFECT_ID and effect.parameters.get("operation") == "fissure":
			return true
	return false
