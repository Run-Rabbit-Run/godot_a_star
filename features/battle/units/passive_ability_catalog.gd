class_name PassiveAbilityCatalog
extends RefCounted

const DEFINITIONS := {
	&"core:attack_training": {"name": "Боевая подготовка (+3 к атаке)", "attack_bonus": 3},
	&"core:immune_burning": {"name": "Невосприимчивость к горению", "immunity": &"core:burning"},
	&"core:immune_electrified": {"name": "Невосприимчивость к наэлектризованности", "immunity": &"core:electrified"},
	&"core:attack_burning": {"name": "Базовая атака: горение ×2", "status": &"core:burning"},
	&"core:attack_electrified": {"name": "Базовая атака: наэлектризованность ×2", "status": &"core:electrified"},
	&"core:attack_wet": {"name": "Базовая атака: влага ×2", "status": &"core:wet"},
	&"core:attack_acid": {"name": "Базовая атака: кислота ×2", "status": &"core:acid"},
	&"core:attack_plasma": {"name": "Базовая атака: плазма ×2", "status": &"core:plasma"},
	&"core:electric_attack": {"name": "Электрическая базовая атака", "damage_type": &"electric"},
	&"core:fire_attack": {"name": "Огненная базовая атака", "damage_type": &"fire"},
	&"core:water_attack": {"name": "Водная базовая атака", "damage_type": &"water"},
	&"core:acid_attack": {"name": "Кислотная базовая атака", "damage_type": &"acid"},
	&"core:plasma_attack": {"name": "Плазменная базовая атака", "damage_type": &"plasma"},
}

static func validate(ids: Array[StringName]) -> String:
	var seen: Array[StringName] = []
	var attack_type_count := 0
	for id: StringName in ids:
		if not DEFINITIONS.has(id):
			return "Неизвестное пассивное умение: %s" % id
		if id in seen:
			return "Повтор пассивного умения: %s" % id
		seen.append(id)
		if DEFINITIONS[id].has("damage_type"):
			attack_type_count += 1
	if attack_type_count > 1:
		return "Выберите только один тип урона базовой атаки."
	return ""

static func attack_bonus(ids: Array[StringName]) -> int:
	var bonus := 0
	for id: StringName in ids:
		bonus += int(DEFINITIONS[id].get("attack_bonus", 0))
	return bonus
