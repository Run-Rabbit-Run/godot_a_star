class_name HealthState
extends RefCounted


var maximum: int
var current: int


func _init(p_maximum: int) -> void:
	maximum = maxi(p_maximum, 1)
	current = maximum


func apply_damage(amount: int) -> int:
	if amount <= 0:
		return 0

	var previous := current
	current = maxi(current - amount, 0)
	return previous - current


func is_defeated() -> bool:
	return current == 0
