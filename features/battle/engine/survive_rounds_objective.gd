class_name SurviveRoundsObjective
extends BattleObjective
## Completed once the given round has ended, or earlier when the target faction is gone.

var _rounds: int
var _target_faction: BattleFaction.Value
var _description: String


func _init(rounds: int, target_faction: BattleFaction.Value, description: String) -> void:
	_rounds = rounds
	_target_faction = target_faction
	_description = description


func is_completed(unit_states: Dictionary[StringName, UnitState], round_number: int) -> bool:
	if round_number > _rounds:
		return true
	for state: UnitState in unit_states.values():
		if state.faction == _target_faction and not state.health.is_defeated():
			return false
	return true


func get_description() -> String:
	return _description
