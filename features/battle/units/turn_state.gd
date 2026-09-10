class_name TurnState
extends RefCounted


var movement_max: int
var movement_remaining: int
var main_action_available: bool


## Само состояние гарантирует неотрицательный максимум и полный стартовый запас.
func _init(p_movement_max: int) -> void:
	movement_max = maxi(p_movement_max, 0)
	start_turn()


func start_turn() -> void:
	movement_remaining = movement_max
	main_action_available = true


func spend_movement(cost: int) -> bool:
	if cost < 0 or cost > movement_remaining:
		return false

	movement_remaining -= cost

	return true


func spend_main_action() -> bool:
	if not main_action_available:
		return false

	main_action_available = false

	return true
