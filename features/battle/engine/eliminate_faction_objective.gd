class_name EliminateFactionObjective
extends BattleObjective


var _target_faction: BattleFaction.Value
var _description: String


func _init(
	target_faction: BattleFaction.Value,
	description: String
) -> void:
	_target_faction = target_faction
	_description = description


func is_completed(
	unit_states: Dictionary[StringName, UnitState],
	_round_number: int
) -> bool:
	for state: UnitState in unit_states.values():
		if (
			state.faction == _target_faction
			and not state.health.is_defeated()
		):
			return false

	return true


func get_description() -> String:
	return _description