class_name ModAPI
extends RefCounted


const VERSION := 1

var _effect_handlers: Dictionary[StringName, AbilityEffectHandler] = {}


static func create_default() -> ModAPI:
	var api := ModAPI.new()
	api.register_effect_handler(&"core:damage", DamageEffectHandler.new())
	return api


func register_effect_handler(
	effect_type_id: StringName,
	handler: AbilityEffectHandler
) -> bool:
	if effect_type_id.is_empty() or handler == null:
		return false

	if _effect_handlers.has(effect_type_id):
		return false

	_effect_handlers[effect_type_id] = handler
	return true


func get_effect_handler(
	effect_type_id: StringName
) -> AbilityEffectHandler:
	return _effect_handlers.get(effect_type_id) as AbilityEffectHandler


func has_effect_handler(effect_type_id: StringName) -> bool:
	return _effect_handlers.has(effect_type_id)