class_name TurnSnapshot
extends RefCounted


var movement_max: int
var movement_remaining: int
var main_action_available: bool


func _init(
	p_movement_max: int,
	p_movement_remaining: int,
	p_main_action_available: bool
) -> void:
	movement_max = maxi(p_movement_max, 0)
	movement_remaining = clampi(p_movement_remaining, 0, movement_max)
	main_action_available = p_main_action_available