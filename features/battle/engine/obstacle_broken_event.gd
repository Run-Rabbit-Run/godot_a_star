class_name ObstacleBrokenEvent
extends BattleEvent
## A flask burst on destruction. Its effects follow as ordinary events: damage, pushes and
## hex layers. The map updates that removed it come before it.

## A detached copy of the flask as it was destroyed.
var obstacle: BattleObstacleDefinition
var hex: Vector2i


func _init(p_obstacle: BattleObstacleDefinition) -> void:
	obstacle = p_obstacle
	hex = p_obstacle.hexes[0]
