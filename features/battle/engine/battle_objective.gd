class_name BattleObjective
extends RefCounted


func is_completed(
	_unit_states: Dictionary[StringName, UnitState],
	_round_number: int
) -> bool:
	push_error("BattleObjective.is_completed() must be overridden.")
	return false


func get_description() -> String:
	return ""
