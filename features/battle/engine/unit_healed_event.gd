class_name UnitHealedEvent
extends BattleEvent
## An ability restored a unit's health: healed a living body or repaired a mechanical one.

var unit_id: StringName
var source_unit_id: StringName
var ability_id: StringName
## UnitBody the effect restores; a mechanical body is repaired.
var body: StringName
## Health actually restored; 0 when the unit was already at its maximum.
var amount: int
var health_after: int
var health_maximum: int


func _init(p_unit_id: StringName, p_source_unit_id: StringName, p_ability_id: StringName, p_body: StringName, p_amount: int, p_health_after: int, p_health_maximum: int) -> void:
	unit_id = p_unit_id
	source_unit_id = p_source_unit_id
	ability_id = p_ability_id
	body = p_body
	amount = p_amount
	health_after = p_health_after
	health_maximum = p_health_maximum
