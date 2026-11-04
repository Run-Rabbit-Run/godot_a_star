class_name EliminateTargetsObjective
extends BattleObjective
## Completed when every commander is defeated, or when the target faction is gone.

var _target_ids: Array[StringName] = []
var _target_faction: BattleFaction.Value
var _description: String


func _init(target_ids: Array[StringName], target_faction: BattleFaction.Value, description: String) -> void:
	_target_ids.assign(target_ids)
	_target_faction = target_faction
	_description = description


func is_completed(unit_states: Dictionary[StringName, UnitState], _round_number: int) -> bool:
	var targets_left := false
	var faction_left := false
	for state: UnitState in unit_states.values():
		if state.health.is_defeated():
			continue
		targets_left = targets_left or _target_ids.has(state.unit_id)
		faction_left = faction_left or (state.faction == _target_faction and not state.is_summoned)
	return not targets_left or not faction_left


func get_target_ids() -> Array[StringName]:
	return _target_ids.duplicate()


func get_description() -> String:
	return _description
