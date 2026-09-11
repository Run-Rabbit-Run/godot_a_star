class_name UnitMovedEvent
extends BattleEvent


var unit_id: StringName
var path: Array[Vector2i] = []
var movement_cost: int


func _init(
	p_unit_id: StringName,
	p_path: Array[Vector2i],
	p_movement_cost: int
) -> void:
	unit_id = p_unit_id
	path.assign(p_path)
	movement_cost = maxi(p_movement_cost, 0)