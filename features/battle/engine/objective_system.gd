class_name ObjectiveSystem
extends RefCounted
## The outcome of a battle: defeat first (protected faction or a protected unit gone), then the
## primary objective, then the round limit.


var _primary_objective: BattleObjective
var _protected_faction: BattleFaction.Value
var _protected_unit_ids: Array[StringName] = []
var _round_limit: int


func _init(
	primary_objective: BattleObjective,
	protected_faction: BattleFaction.Value,
	protected_unit_ids: Array[StringName] = [],
	round_limit: int = BattleObjectiveDefinition.MAX_ROUND_LIMIT
) -> void:
	_primary_objective = primary_objective
	_protected_faction = protected_faction
	_protected_unit_ids.assign(protected_unit_ids)
	_round_limit = round_limit


func get_outcome(
	unit_states: Dictionary[StringName, UnitState],
	round_number: int
) -> BattleOutcome.Value:
	if _primary_objective == null:
		push_error("ObjectiveSystem requires a primary objective.")
		return BattleOutcome.Value.DEFEAT

	if not _has_living_unit(unit_states, _protected_faction):
		return BattleOutcome.Value.DEFEAT

	for unit_id: StringName in _protected_unit_ids:
		var state := unit_states.get(unit_id) as UnitState
		if state != null and state.health.is_defeated():
			return BattleOutcome.Value.DEFEAT

	if _primary_objective.is_completed(unit_states, round_number):
		return BattleOutcome.Value.VICTORY

	if round_number > _round_limit:
		return BattleOutcome.Value.DEFEAT

	return BattleOutcome.Value.IN_PROGRESS


func get_description() -> String:
	if _primary_objective == null:
		return ""

	return _primary_objective.get_description()


## Commanders of an ELIMINATE_TARGETS objective; empty for other objectives.
func get_target_unit_ids() -> Array[StringName]:
	if _primary_objective is EliminateTargetsObjective:
		return (_primary_objective as EliminateTargetsObjective).get_target_ids()
	var none: Array[StringName] = []
	return none


func get_protected_unit_ids() -> Array[StringName]:
	return _protected_unit_ids.duplicate()


func get_round_limit() -> int:
	return _round_limit


func _has_living_unit(
	unit_states: Dictionary[StringName, UnitState],
	faction: BattleFaction.Value
) -> bool:
	for state: UnitState in unit_states.values():
		if state.faction == faction and not state.health.is_defeated():
			return true

	return false
