class_name ObjectiveSystem
extends RefCounted


var _primary_objective: BattleObjective
var _protected_faction: BattleFaction.Value


func _init(
	primary_objective: BattleObjective,
	protected_faction: BattleFaction.Value
) -> void:
	_primary_objective = primary_objective
	_protected_faction = protected_faction


func get_outcome(
	unit_states: Dictionary[StringName, UnitState],
	round_number: int
) -> BattleOutcome.Value:
	if _primary_objective == null:
		push_error("ObjectiveSystem requires a primary objective.")
		return BattleOutcome.Value.DEFEAT

	if not _has_living_unit(unit_states, _protected_faction):
		return BattleOutcome.Value.DEFEAT

	if _primary_objective.is_completed(unit_states, round_number):
		return BattleOutcome.Value.VICTORY

	return BattleOutcome.Value.IN_PROGRESS


func get_description() -> String:
	if _primary_objective == null:
		return ""

	return _primary_objective.get_description()


func _has_living_unit(
	unit_states: Dictionary[StringName, UnitState],
	faction: BattleFaction.Value
) -> bool:
	for state: UnitState in unit_states.values():
		if state.faction == faction and not state.health.is_defeated():
			return true

	return false