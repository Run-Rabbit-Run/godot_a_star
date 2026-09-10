class_name ObjectiveResult
extends RefCounted


var description: String
var is_completed: bool


func _init(
	p_description: String,
	p_is_completed: bool
) -> void:
	description = p_description
	is_completed = p_is_completed