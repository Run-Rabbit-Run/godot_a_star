class_name BattlePlaybackSettings
extends RefCounted


signal speed_changed(speed: float)


var speed := 1.0


func set_speed(value: float) -> bool:
	if not is_finite(value) or value <= 0.0:
		return false

	if is_equal_approx(speed, value):
		return true

	speed = value
	speed_changed.emit(speed)
	return true
