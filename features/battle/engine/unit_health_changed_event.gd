class_name UnitHealthChangedEvent
extends BattleEvent
## The maximum health of a living unit changed, for example when an allied aura appeared or ended.

var unit_id: StringName
var health_before: int
var maximum_before: int
var health_after: int
var maximum_after: int


func _init(p_unit_id: StringName, p_health_before: int, p_maximum_before: int, p_health_after: int, p_maximum_after: int) -> void:
	unit_id = p_unit_id
	health_before = p_health_before
	maximum_before = p_maximum_before
	health_after = p_health_after
	maximum_after = p_maximum_after
