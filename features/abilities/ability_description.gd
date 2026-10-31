class_name AbilityDescription
extends RefCounted
## Player-facing ability text: an authored template whose {variables} take the final values of the ability effects.

const DAMAGE_TYPE_NAMES := {"physical": "физический", "electric": "электрический", "fire": "огненный", "water": "водный", "acid": "кислотный", "plasma": "плазменный"}
const MAX_LENGTH := 1000
const _TOKEN := "\\{([A-Za-z0-9_]+)\\}"


## Variables of an active ability in display order: [{key, label, value}].
## context describes the acting unit: attack_damage (base attack with passives) and attack_range.
## Without it values that depend on the unit are named instead of counted.
static func variables(ability: AbilityDefinition, context: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var attack_range := str(context.attack_range) if context.has("attack_range") else "дальность атаки"
	_add(result, "range", "Дальность", attack_range if ability.uses_attack_range else str(ability.range))
	_add(result, "radius", "Радиус области", str(ability.area_radius))
	_add(result, "cooldown", "Перезарядка", str(ability.cooldown_turns))
	_add(result, "initial_cooldown", "Начальная перезарядка", str(ability.initial_cooldown_turns))
	var counts := {}
	for effect: AbilityEffectDefinition in ability.effects:
		var kind := String(effect.effect_type_id)
		counts[kind] = int(counts.get(kind, 0)) + 1
		# The first effect of a kind has the short name; later ones are numbered: damage, damage_2.
		var suffix := "" if counts[kind] == 1 else "_%d" % counts[kind]
		var number := "" if counts[kind] == 1 else " (%d)" % counts[kind]
		var params := effect.parameters
		match effect.effect_type_id:
			&"core:damage":
				var attack := str(context.attack_damage) if context.has("attack_damage") else "урон атаки"
				var base: bool = params.get("use_base_attack", false)
				_add(result, "damage" + suffix, "Урон цели" + number, attack if base else str(params.get("amount", 0)))
				_add(result, "damage_area" + suffix, "Урон остальным в области" + number, attack if base else str(params.get("secondary_amount", params.get("amount", 0))))
				_add(result, "damage_type" + suffix, "Тип урона" + number, damage_type_name(str(params.get("damage_type", "physical"))))
			&"core:unit_status":
				_add(result, "status" + suffix, "Состояние юнита" + number, UnitStatusCatalog.display_name(StringName(str(params.get("status_id", "")))).to_lower())
				_add(result, "levels" + suffix, "Уровней состояния" + number, str(params.get("levels", 0)))
			&"core:hex_state":
				_add(result, "hex_state" + suffix, "Состояние гекса" + number, HexStateCatalog.get_display_name(StringName(str(params.get("state_id", "")))).to_lower())
			&"core:summon":
				var unit: Variant = params.get("unit")
				if unit is UnitDefinition:
					_add(result, "summon" + suffix, "Призываемый юнит" + number, unit.display_name)
					if unit.base_stats != null:
						_add(result, "summon_hp" + suffix, "ОЗ призыва" + number, str(unit.base_stats.max_health))
						_add(result, "summon_damage" + suffix, "Урон атаки призыва" + number, str(unit.base_stats.basic_attack_damage))
						_add(result, "summon_range" + suffix, "Дальность атаки призыва" + number, str(unit.base_stats.basic_attack_range))
	return result


static func render(ability: AbilityDefinition, context: Dictionary = {}) -> String:
	return fill(ability.description, variables(ability, context))


## Variables of a passive definition (PassiveAbilityCatalog shape): only the properties it sets.
static func passive_variables(definition: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if int(definition.get("attack_bonus", 0)) > 0:
		_add(result, "bonus", "Бонус урона", str(int(definition.attack_bonus)))
	if not str(definition.get("damage_type", "")).is_empty():
		_add(result, "damage_type", "Тип урона атаки", damage_type_name(str(definition.damage_type)))
	if not str(definition.get("status", "")).is_empty():
		_add(result, "status", "Накладываемое состояние", UnitStatusCatalog.display_name(StringName(str(definition.status))).to_lower())
		_add(result, "levels", "Уровней за удар", str(int(definition.get("levels", 2))))
	if not str(definition.get("immunity", "")).is_empty():
		_add(result, "immunity", "Невосприимчивость", UnitStatusCatalog.display_name(StringName(str(definition.immunity))).to_lower())
	return result


static func render_passive(definition: Dictionary) -> String:
	return fill(str(definition.get("description", "")), passive_variables(definition))


static func fill(template: String, entries: Array[Dictionary]) -> String:
	var values := {}
	for entry: Dictionary in entries:
		values[entry.key] = entry.value
	return template.format(values)


## Placeholders of the template that are not variables of this ability, in order of appearance.
static func unknown_tokens(template: String, entries: Array[Dictionary]) -> PackedStringArray:
	var known := entries.map(func(entry: Dictionary) -> String: return entry.key)
	var unknown := PackedStringArray()
	var regex := RegEx.create_from_string(_TOKEN)
	for found: RegExMatch in regex.search_all(template):
		var key := found.get_string(1)
		if not known.has(key) and not unknown.has(key):
			unknown.append(key)
	return unknown


static func damage_type_name(type: String) -> String:
	return DAMAGE_TYPE_NAMES.get(type, type)


static func _add(result: Array[Dictionary], key: String, label: String, value: String) -> void:
	result.append({"key": key, "label": label, "value": value})
