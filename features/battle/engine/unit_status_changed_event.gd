class_name UnitStatusChangedEvent
extends BattleEvent

var unit_id: StringName
var statuses: Dictionary[StringName, int] = {}
var previous_statuses: Dictionary[StringName, int] = {}

func _init(unit: UnitState, before: Dictionary) -> void:
	unit_id = unit.unit_id
	statuses.assign(unit.statuses)
	previous_statuses.assign(before)
