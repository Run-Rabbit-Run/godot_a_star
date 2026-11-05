class_name BattleObstacleDefinition
extends Resource

const TYPES: Array[StringName] = [&"hill", &"river", &"puddle", &"trees", &"rocks", &"flask", &"big_flask", &"pressure_flask", &"explosive_flask"]
const NAMES: Array[String] = ["Холмы", "Река", "Лужи", "Деревья", "Камни", "Колба", "Большая колба", "Колба под давлением", "Взрывоопасная колба"]
## Flasks burst when destroyed (ObstacleBreakService); each fills one hex and can always be destroyed.
const FLASK_TYPES: Array[StringName] = [&"flask", &"big_flask", &"pressure_flask", &"explosive_flask"]
## Flasks that spill their contents: on their own hex, or also on its neighbors for the big one.
const SPILL_TYPES: Array[StringName] = [&"flask", &"big_flask"]
## Hex layers a spilling flask may hold.
const CONTENTS: Array[StringName] = [&"core:acid", &"core:water", &"core:oil", &"core:electricity"]
const DEFAULT_BLAST_DAMAGE := 3
const MAX_BLAST_DAMAGE := 99

@export var id: StringName
@export var terrain_type: StringName = &"rocks"
@export var hexes: Array[Vector2i] = []
@export var destructible := false
@export var max_hp := 10
# Runtime copies own current_hp; authored JSON only stores max_hp.
@export var current_hp := 10
## The hex layer a spilling flask leaves; "" for every other type.
@export var contents: StringName
## Fire damage an explosive flask deals around itself; other types ignore it.
@export var blast_damage := DEFAULT_BLAST_DAMAGE


## True when destroying it has an effect of its own.
func is_flask() -> bool:
	return FLASK_TYPES.has(terrain_type)


func validate() -> String:
	if id.is_empty() or not TYPES.has(terrain_type):
		return "Препятствие требует ID и известный тип местности."
	if max_hp < 1 or hexes.size() < 1 or hexes.size() > 4:
		return "Препятствие занимает 1–4 гекса и требует HP > 0."
	if hexes.size() > 1:
		var direction := hexes[1] - hexes[0]
		if not HexGrid.DIRECTIONS.has(direction):
			return "Гексы препятствия должны идти подряд."
		for index in range(hexes.size()):
			if hexes[index] != hexes[0] + direction * index:
				return "Гексы препятствия должны идти по прямой без пропусков."
	if is_flask() and (hexes.size() != 1 or not destructible):
		return "Колба занимает один гекс и всегда уничтожаема."
	if SPILL_TYPES.has(terrain_type) != not contents.is_empty():
		return "Содержимое задаётся только колбе и большой колбе."
	if not contents.is_empty() and not CONTENTS.has(contents):
		return "Колба содержит кислоту, воду, масло или электричество."
	if terrain_type == &"explosive_flask" and (blast_damage < 1 or blast_damage > MAX_BLAST_DAMAGE):
		return "Урон взрыва — от 1 до %d." % MAX_BLAST_DAMAGE
	return ""
