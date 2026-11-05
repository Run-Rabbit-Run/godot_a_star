class_name ObstacleDescription
extends RefCounted
## Player-facing names and burst texts of obstacles for hover details, the log and forecasts.

## Instrumental case for "с …": a flask with acid is «колба с кислотой».
const CONTENT_NAMES: Dictionary[StringName, String] = {
	&"core:acid": "кислотой", &"core:water": "водой", &"core:oil": "маслом", &"core:electricity": "электричеством",
}


static func display_name(obstacle: BattleObstacleDefinition) -> String:
	var index := BattleObstacleDefinition.TYPES.find(obstacle.terrain_type)
	var name: String = BattleObstacleDefinition.NAMES[index] if index >= 0 else String(obstacle.terrain_type)
	if not obstacle.contents.is_empty():
		name += " с " + CONTENT_NAMES.get(obstacle.contents, HexStateCatalog.get_display_name(obstacle.contents).to_lower())
	return name


## What the flask does when destroyed; "" for an ordinary obstacle.
static func burst(obstacle: BattleObstacleDefinition) -> String:
	var layer := HexStateCatalog.get_display_name(obstacle.contents).to_lower()
	match obstacle.terrain_type:
		&"flask":
			return "При разрушении: %s на её гексе." % layer
		&"big_flask":
			return "При разрушении: %s на её гексе и соседних." % layer
		&"pressure_flask":
			return "При разрушении отбрасывает соседних юнитов на %d гекса." % ObstacleBreakService.PRESSURE_PUSH_DISTANCE
		&"explosive_flask":
			return "При разрушении: %d огненного урона соседям, огонь на её гексе и соседних." % obstacle.blast_damage
	return ""


## The log line of a burst.
static func burst_log(obstacle: BattleObstacleDefinition, hex: Vector2i) -> String:
	var name := display_name(obstacle)
	match obstacle.terrain_type:
		&"pressure_flask":
			return "%s %s лопается: ударная волна отбрасывает соседей." % [name, _hex(hex)]
		&"explosive_flask":
			return "%s %s взрывается: %d огненного урона вокруг, всё вокруг горит." % [name, _hex(hex), obstacle.blast_damage]
	var spread := " и соседних" if obstacle.terrain_type == &"big_flask" else ""
	return "%s %s разбита: %s на её гексе%s." % [name, _hex(hex), HexStateCatalog.get_display_name(obstacle.contents).to_lower(), spread]


static func _hex(cell: Vector2i) -> String:
	return "(%d, %d)" % [cell.x, cell.y]
