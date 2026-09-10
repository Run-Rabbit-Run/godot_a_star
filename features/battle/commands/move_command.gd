class_name MoveCommand
extends RefCounted


var unit_id: StringName
var destination: Vector2i


func _init(p_unit_id: StringName, p_destination: Vector2i) -> void:
	unit_id = p_unit_id
	destination = p_destination