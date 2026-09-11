class_name HealthSnapshot
extends RefCounted


var maximum: int
var current: int


func _init(p_maximum: int, p_current: int) -> void:
	maximum = maxi(p_maximum, 1)
	current = clampi(p_current, 0, maximum)


func is_defeated() -> bool:
	return current == 0