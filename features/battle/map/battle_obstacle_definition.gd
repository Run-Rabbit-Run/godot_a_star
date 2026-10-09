class_name BattleObstacleDefinition
extends Resource

const TYPES: Array[StringName] = [&"hill", &"river", &"puddle", &"trees", &"rocks"]
const NAMES: Array[String] = ["Холмы", "Река", "Лужи", "Деревья", "Камни"]

@export var id: StringName
@export var terrain_type: StringName = &"rocks"
@export var hexes: Array[Vector2i] = []
@export var destructible := false
@export var max_hp := 10
# Runtime copies own current_hp; authored JSON only stores max_hp.
@export var current_hp := 10

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
	return ""
