class_name HexStateCatalog
extends RefCounted


## Built-in gameplay rules, shared by graphical battles and simulation.
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


const EFFECTS := {
	&"core:electricity": {&"core:electrified": 2},
	&"core:water": {&"core:wet": 2},
	&"core:fire": {&"core:burning": 2},
	&"core:oil": {&"core:sticky_oil": 2},
	&"core:acid": {&"core:acid": 2},
	&"core:electrified_water": {&"core:electrified": 3},
	&"core:plasma": {&"core:plasma": 2},
	&"core:electrified_acid": {&"core:acid": 2, &"core:electrified": 2},
	&"core:steam": {&"core:wet": 1},
	&"core:boiling_acid": {&"core:acid": 3},
	&"core:burning_oil": {&"core:burning": 3, &"core:sticky_oil": 3},
	&"core:acid_vapour": {&"core:acid": 3},
}

static func get_damage_type(id: StringName) -> StringName:
	if id == &"core:plasma":
		return &"plasma"
	if id in [&"core:electricity", &"core:electrified_water"]:
		return &"electric"
	if id in [&"core:fire", &"core:burning_oil"]:
		return &"fire"
	if id in [&"core:acid", &"core:electrified_acid", &"core:boiling_acid", &"core:acid_vapour"]:
		return &"acid"
	# Harmless states never deal damage; a new damaging state must be listed explicitly above.
	return &"physical"

static func ranged_reduction(id: StringName) -> int:
	return 6 if id == &"core:acid_vapour" else (3 if id == &"core:steam" else 0)

static func combine(existing: StringName, incoming: StringName) -> StringName:
	if existing == incoming or existing.is_empty() or incoming.is_empty():
		return incoming
	var pair: Array[StringName] = [existing, incoming]
	if pair.has(&"core:electricity"):
		if pair.has(&"core:water"):
			return &"core:electrified_water"
		if pair.has(&"core:fire"):
			return &"core:plasma"
		if pair.has(&"core:oil"):
			return &"core:oil"
		if pair.has(&"core:acid"):
			return &"core:electrified_acid"
	if pair.has(&"core:fire"):
		if pair.has(&"core:water"):
			return &"core:steam"
		if pair.has(&"core:oil"):
			return &"core:burning_oil"
		if pair.has(&"core:acid"):
			return &"core:acid_vapour"
	if pair.has(&"core:water") and pair.has(&"core:acid"):
		return &"core:boiling_acid"
	# No reactions of compound states are specified; the last applied state wins.
	return incoming

static func propagation(id: StringName) -> Dictionary:
	match id:
		&"core:electrified_water":
			return {&"core:water": &"core:electrified_water"}
		&"core:plasma":
			return {&"core:electricity": &"core:plasma", &"core:fire": &"core:plasma"}
		&"core:electrified_acid":
			return {&"core:acid": &"core:electrified_acid"}
		&"core:boiling_acid", &"core:burning_oil":
			return {&"core:water": &"core:boiling_acid", &"core:acid": &"core:boiling_acid"}
	return {}
