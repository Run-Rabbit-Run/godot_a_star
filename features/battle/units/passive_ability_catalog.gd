class_name PassiveAbilityCatalog
extends RefCounted

const DEFINITIONS := {
	&"core:attack_training": {"name": "Боевая подготовка (+3 к атаке)", "attack_bonus": 3},
}

static func validate(ids: Array[StringName]) -> String:
	var seen: Array[StringName] = []
	for id: StringName in ids:
		if not DEFINITIONS.has(id):
			return "Неизвестное пассивное умение: %s" % id
		if id in seen:
			return "Повтор пассивного умения: %s" % id
		seen.append(id)
	return ""

static func attack_bonus(ids: Array[StringName]) -> int:
	var bonus := 0
	for id: StringName in ids:
		bonus += int(DEFINITIONS[id].attack_bonus)
	return bonus
