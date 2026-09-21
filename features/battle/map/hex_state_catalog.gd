class_name HexStateCatalog
extends RefCounted


## Only movement cost and direct damage are active rules in this iteration.
const RULES := {
	&"core:electricity": {"name": "Электричество", "cost": 1, "damage": 1},
	&"core:water": {"name": "Вода", "cost": 1, "damage": 0},
	&"core:fire": {"name": "Огонь", "cost": 1, "damage": 1},
	&"core:oil": {"name": "Масло", "cost": 2, "damage": 0},
	&"core:acid": {"name": "Кислота", "cost": 1, "damage": 1},
	&"core:electrified_water": {"name": "Наэлектризованная вода", "cost": 1, "damage": 1},
	&"core:plasma": {"name": "Плазма", "cost": 1, "damage": 2},
	&"core:electrified_acid": {"name": "Наэлектризованная кислота", "cost": 1, "damage": 2},
	&"core:steam": {"name": "Пар", "cost": 1, "damage": 0},
	&"core:boiling_acid": {"name": "Кипящая кислота", "cost": 2, "damage": 2},
	&"core:burning_oil": {"name": "Горящее масло", "cost": 2, "damage": 2},
	&"core:acid_vapour": {"name": "Кислотный пар", "cost": 1, "damage": 2},
}


static func has_state(state_id: StringName) -> bool:
	return RULES.has(state_id)


static func get_movement_cost(state_id: StringName) -> int:
	if state_id.is_empty():
		return 1

	var rule: Dictionary = RULES.get(state_id, {})
	return int(rule.get("cost", -1))


static func get_damage(state_id: StringName) -> int:
	var rule: Dictionary = RULES.get(state_id, {})
	return int(rule.get("damage", 0))


static func get_display_name(state_id: StringName) -> String:
	var rule: Dictionary = RULES.get(state_id, {})
	return String(rule.get("name", String(state_id)))