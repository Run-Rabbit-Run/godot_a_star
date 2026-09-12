class_name BattleEffectContext
extends RefCounted


var _state: BattleState


func _init(state: BattleState) -> void:
	_state = state


func apply_damage(
	source_unit_id: StringName,
	target_unit_id: StringName,
	amount: int
) -> UnitDamagedEvent:
	var source := _state.unit_states.get(source_unit_id) as UnitState
	var target := _state.unit_states.get(target_unit_id) as UnitState

	if source == null or target == null or amount <= 0:
		return null

	if source.health.is_defeated() or target.health.is_defeated():
		return null

	var damage := target.health.apply_damage(amount)
	return UnitDamagedEvent.new(
		source.unit_id,
		target.unit_id,
		damage,
		target.health.current,
		target.health.is_defeated()
	)