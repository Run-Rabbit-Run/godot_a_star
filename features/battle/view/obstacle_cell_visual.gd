class_name ObstacleCellVisual
extends Node2D

var obstacle: BattleObstacleDefinition
var hex: Vector2i

func _draw() -> void:
	if obstacle != null:
		ObstacleArt.draw(self, Vector2.ZERO, obstacle, hex)
