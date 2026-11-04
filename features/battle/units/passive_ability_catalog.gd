class_name PassiveAbilityCatalog
extends RefCounted

const DEFINITIONS := {
	&"core:melee_retaliation": {"name": "Ответный удар в ближнем бою", "description": "Отвечает обычной атакой на удар в ближнем бою, если выжил и не парализован."},
	&"core:attack_training": {"name": "Боевая подготовка (+3 к атаке)", "attack_bonus": 3, "description": "+{bonus} к урону обычной атаки и умений, использующих урон атаки."},
	&"core:immune_burning": {"name": "Невосприимчивость к горению", "immunity": UnitStatusCatalog.BURNING, "description": "Невосприимчивость: {immunity} не накладывается на юнита."},
	&"core:immune_electrified": {"name": "Невосприимчивость к наэлектризованности", "immunity": UnitStatusCatalog.ELECTRIFIED, "description": "Невосприимчивость: {immunity} не накладывается на юнита."},
	&"core:attack_burning": {"name": "Базовая атака: горение ×2", "status": UnitStatusCatalog.BURNING, "description": "Обычная атака накладывает {status} ×{levels}."},
	&"core:attack_electrified": {"name": "Базовая атака: наэлектризованность ×2", "status": UnitStatusCatalog.ELECTRIFIED, "description": "Обычная атака накладывает {status} ×{levels}."},
	&"core:attack_wet": {"name": "Базовая атака: влага ×2", "status": UnitStatusCatalog.WET, "description": "Обычная атака накладывает {status} ×{levels}."},
	&"core:attack_acid": {"name": "Базовая атака: кислота ×2", "status": UnitStatusCatalog.ACID, "description": "Обычная атака накладывает {status} ×{levels}."},
	&"core:attack_plasma": {"name": "Базовая атака: плазма ×2", "status": UnitStatusCatalog.PLASMA, "description": "Обычная атака накладывает {status} ×{levels}."},
	&"core:electric_attack": {"name": "Электрическая базовая атака", "damage_type": &"electric", "description": "Обычная атака наносит {damage_type} урон."},
	&"core:fire_attack": {"name": "Огненная базовая атака", "damage_type": &"fire", "description": "Обычная атака наносит {damage_type} урон."},
	&"core:water_attack": {"name": "Водная базовая атака", "damage_type": &"water", "description": "Обычная атака наносит {damage_type} урон."},
	&"core:acid_attack": {"name": "Кислотная базовая атака", "damage_type": &"acid", "description": "Обычная атака наносит {damage_type} урон."},
	&"core:plasma_attack": {"name": "Плазменная базовая атака", "damage_type": &"plasma", "description": "Обычная атака наносит {damage_type} урон."},
	&"core:ally_max_health": {"name": "Жизнеобеспечение (+1 ОЗ союзникам)", "ally_max_health": 1, "description": "Пока юнит цел, у остальных союзников максимум ОЗ больше на {ally_health}."},
}

static func validate(ids: Array[StringName], overrides: Dictionary = {}) -> String:
	var definitions := DEFINITIONS.duplicate(true)
	definitions.merge(overrides, true)
	var seen: Array[StringName] = []
	var attack_type_count := 0
	for id: StringName in ids:
		if not definitions.has(id):
			return "Неизвестное пассивное умение: %s" % id
		if id in seen:
			return "Повтор пассивного умения: %s" % id
		seen.append(id)
		if definitions[id].has("damage_type"):
			attack_type_count += 1
	if attack_type_count > 1:
		return "Выберите только один тип урона базовой атаки."
	return ""

static func attack_bonus(ids: Array[StringName], overrides: Dictionary = {}) -> int:
	var definitions := DEFINITIONS.duplicate(true)
	definitions.merge(overrides, true)
	var bonus := 0
	for id: StringName in ids:
		bonus += int(definitions.get(id, {}).get("attack_bonus", 0))
	return bonus
