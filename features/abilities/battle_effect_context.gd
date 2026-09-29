class_name BattleEffectContext
extends RefCounted


var _state: BattleState
var _ability_id: StringName


func _init(state: BattleState, ability_id: StringName = StringName()) -> void:
	_state = state
	_ability_id = ability_id


func apply_damage(
	source_unit_id: StringName,
	target_unit_id: StringName,
	amount: int
) -> UnitDamagedEvent:
	var source := _state.unit_states.get(source_unit_id) as UnitState
	var target := _state.unit_states.get(target_unit_id) as UnitState

	if source == null or target == null or amount <= 0:
		return null

	# The executor validates the source before the whole ability starts.
	# Its death during an area effect must not cancel the remaining targets.
	if target.health.is_defeated():
		return null

	var damage := target.health.apply_damage(amount)
	return UnitDamagedEvent.new(
		source.unit_id,
		target.unit_id,
		damage,
		target.health.current,
		target.health.is_defeated(),
		StringName(),
		_ability_id
	)
