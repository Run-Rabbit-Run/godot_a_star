class_name HexStateCatalog
extends RefCounted
## Built-in values of the two hex layers, shared by graphical battles and simulation.
## A hex holds at most one liquid and one energy; its effect is the sum of both layers.

enum Layer { NONE, LIQUID, ENERGY }

const LIFETIME := 3

const RULES := {
	&"core:water": {"name": "Вода", "layer": Layer.LIQUID, "statuses": {UnitStatusCatalog.WET: 2}, "damage": 0},
	&"core:oil": {"name": "Масло", "layer": Layer.LIQUID, "statuses": {UnitStatusCatalog.STICKY_OIL: 2}, "damage": 0, "cost": 2},
	&"core:acid": {"name": "Кислота", "layer": Layer.LIQUID, "statuses": {UnitStatusCatalog.ACID: 2}, "damage": 1},
	&"core:steam": {"name": "Пар", "layer": Layer.LIQUID, "statuses": {UnitStatusCatalog.WET: 1}, "damage": 0, "cover": 3},
	&"core:fire": {"name": "Огонь", "layer": Layer.ENERGY, "statuses": {UnitStatusCatalog.BURNING: 2}, "damage": 1},
	&"core:electricity": {"name": "Электричество", "layer": Layer.ENERGY, "statuses": {UnitStatusCatalog.ELECTRIFIED: 2}, "damage": 1},
	&"core:plasma": {"name": "Плазма", "layer": Layer.ENERGY, "statuses": {UnitStatusCatalog.PLASMA: 2}, "damage": 2},
}

## Liquids that carry electricity to neighbors of the same liquid.
const CONDUCTORS: Array[StringName] = [&"core:water", &"core:acid"]

## Single states of the former model, read from old maps as [liquid, energy].
const LEGACY := {
	&"core:electrified_water": [&"core:water", &"core:electricity"],
	&"core:electrified_acid": [&"core:acid", &"core:electricity"],
	&"core:burning_oil": [&"core:oil", &"core:fire"],
	&"core:acid_vapour": [&"core:acid", &"core:fire"],
	&"core:boiling_acid": [&"core:acid", &""],
}


static func has_state(id: StringName) -> bool:
	return RULES.has(id)


static func layer_of(id: StringName) -> Layer:
	var layer: int = RULES.get(id, {}).get("layer", Layer.NONE)
	return layer as Layer


static func is_liquid(id: StringName) -> bool:
	return layer_of(id) == Layer.LIQUID


static func is_energy(id: StringName) -> bool:
	return layer_of(id) == Layer.ENERGY


static func get_display_name(id: StringName) -> String:
	return String(RULES.get(id, {}).get("name", String(id)))


## Statuses a unit gets from this layer value on exposure.
static func get_statuses(id: StringName) -> Dictionary:
	return RULES.get(id, {}).get("statuses", {})


static func get_damage(id: StringName) -> int:
	return int(RULES.get(id, {}).get("damage", 0))


static func get_damage_type(id: StringName) -> StringName:
	match id:
		&"core:fire":
			return &"fire"
		&"core:electricity":
			return &"electric"
		&"core:plasma":
			return &"plasma"
		&"core:acid":
			return &"acid"
	# Harmless values never deal damage; a new damaging value must be listed explicitly above.
	return &"physical"


## Movement cost set by the liquid layer; a hex without liquid costs 1.
static func get_movement_cost(liquid: StringName) -> int:
	return int(RULES.get(liquid, {}).get("cost", 1))


## Damage reduction the liquid gives against shots and ranged abilities.
static func ranged_reduction(liquid: StringName) -> int:
	return int(RULES.get(liquid, {}).get("cover", 0))


## Fire and electricity together make plasma; plasma absorbs both.
static func combine_energy(existing: StringName, incoming: StringName) -> StringName:
	if existing.is_empty() or existing == incoming:
		return incoming
	return &"core:plasma"


## The energy a neighbor receives from a spreading source, or "": electricity runs through
## water and acid of the same kind, fire runs through oil.
static func spreading_energy(source_liquid: StringName, source_energy: StringName, neighbor_liquid: StringName, neighbor_energy: StringName) -> StringName:
	if neighbor_energy in [source_energy, &"core:plasma"] or neighbor_liquid != source_liquid:
		return &""
	if source_energy == &"core:electricity" and CONDUCTORS.has(source_liquid):
		return source_energy
	if source_energy == &"core:fire" and source_liquid == &"core:oil":
		return source_energy
	return &""


## [liquid, energy] of a stored id: a layer value or a single state of the former model.
static func split(id: StringName) -> Array[StringName]:
	var layers: Array[StringName] = [&"", &""]
	if LEGACY.has(id):
		layers.assign(LEGACY[id])
	elif is_liquid(id):
		layers[0] = id
	elif is_energy(id):
		layers[1] = id
	return layers


static func description(id: StringName) -> String:
	if not has_state(id):
		return ""
	var parts: PackedStringArray = []
	var statuses: PackedStringArray = []
	var effects := get_statuses(id)
	for status: StringName in effects:
		statuses.append("%s ×%d" % [UnitStatusCatalog.display_name(status), effects[status]])
	parts.append("При входе и в начале фазы: %s." % ", ".join(statuses))
	var amount := get_damage(id)
	if amount > 0:
		var types := {&"fire": "огненного", &"electric": "электрического", &"acid": "кислотного", &"plasma": "плазменного", &"physical": "физического"}
		parts.append("Наносит %d %s урона после наложения эффектов." % [amount, types.get(get_damage_type(id), "")])
	var reduction := ranged_reduction(id)
	if reduction > 0:
		parts.append("Снижает урон дальних атак и способностей на %d." % reduction)
	match id:
		&"core:water":
			parts.append("Огонь испаряет её в пар. Проводит ток к соседней воде.")
		&"core:acid":
			parts.append("Проводит ток к соседней кислоте.")
		&"core:oil":
			parts.append("Огонь бежит по соседнему маслу. Ток не проводит.")
		&"core:fire":
			parts.append("Испаряет воду в пар, бежит по маслу. С током даёт плазму.")
		&"core:electricity":
			parts.append("Бежит по соседней воде и кислоте. С огнём даёт плазму.")
	return "\n".join(parts)
