class_name ModAPI
extends RefCounted


const VERSION := 1

var _frozen := false

var _effect_handlers: Dictionary[StringName, AbilityEffectHandler] = {}


static func create_default() -> ModAPI:
	var api := ModAPI.new()
	api.register_effect_handler(&"core:damage", DamageEffectHandler.new())
	api.register_effect_handler(&"core:hex_state", HexStateEffectHandler.new())
	api.register_effect_handler(&"core:unit_status", UnitStatusEffectHandler.new())
	api.register_effect_handler(&"core:summon", SummonEffectHandler.new())
	return api


func register_effect_handler(
	effect_type_id: StringName,
	handler: AbilityEffectHandler
) -> bool:
	if _frozen or effect_type_id.is_empty() or handler == null:
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


func frozen_copy() -> ModAPI:
	var copy := ModAPI.new()
	copy._effect_handlers.assign(_effect_handlers)
	copy._frozen = true
	return copy
