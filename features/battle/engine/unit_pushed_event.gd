class_name UnitPushedEvent
extends BattleEvent
## A unit forced along a straight line by a push. The path starts at the hex it left; a
## collision names what stopped it on `blocker_hex`, the next hex of the line.

enum Collision { NONE, UNIT, OBSTACLE, IMPASSABLE, EDGE }

var unit_id: StringName
## The unit whose push moved it.
var source_unit_id: StringName
var path: Array[Vector2i] = []
var collision: Collision = Collision.NONE
var blocker_hex := Vector2i.ZERO
## The living unit it hit, for a collision with a unit.
var blocker_unit_id: StringName


func _init(p_unit_id: StringName, p_source_unit_id: StringName, p_path: Array[Vector2i]) -> void:
	unit_id = p_unit_id
	source_unit_id = p_source_unit_id
	path.assign(p_path)
