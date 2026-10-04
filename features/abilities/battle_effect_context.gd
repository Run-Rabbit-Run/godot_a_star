class_name BattleEffectContext
extends RefCounted


var _state: BattleState
var _ability_id: StringName


func _init(state: BattleState, ability_id: StringName = StringName()) -> void:
	_state = state
	_ability_id = ability_id


func get_corpses_at(hex: Vector2i) -> Array[UnitSnapshot]:
	return _state.get_corpses_at(hex)


func get_unit_hex(id: StringName) -> Vector2i:
	var unit := _state.unit_states.get(id) as UnitState
	return unit.hex if unit != null else Vector2i.ZERO


func apply_unit_status(target_id: StringName, status_id: StringName, levels: int) -> Array[BattleEvent]:
	var events: Array[BattleEvent] = []
	UnitStatusService.apply(_state.unit_states.get(target_id) as UnitState, status_id, levels, events)
	return events


func apply_hex_state(hex: Vector2i, id: StringName) -> Array[BattleEvent]:
	var mutations: Array[MapMutation] = [MapMutation.apply_hex_state(hex, id)]
	var result := MapMutationService.apply(_state, mutations)
	return result.events


func apply_damage_events(source_unit_id: StringName, target_unit_id: StringName, amount: int, type: StringName = &"physical") -> Array[BattleEvent]:
	var events: Array[BattleEvent] = []
	var source := _state.unit_states.get(source_unit_id) as UnitState
	var target := _state.unit_states.get(target_unit_id) as UnitState
	if source == null or target == null:
		return events
	var ability := source.get_ability(_ability_id)
	var ranged := ability != null and ability.range > 1
	var reduction := HexStateCatalog.ranged_reduction(_state.hex_grid.get_hex_state_id(target.hex)) if ranged else 0
	UnitStatusService.damage(target, amount, type, events, source_unit_id, &"", _ability_id, reduction)
	return events


# Compatibility for existing external handlers. Use apply_damage_events for compound effects.
func apply_damage(source_unit_id: StringName, target_unit_id: StringName, amount: int) -> UnitDamagedEvent:
	var events := apply_damage_events(source_unit_id, target_unit_id, amount)
	for event: BattleEvent in events:
		if event is UnitDamagedEvent:
			return event as UnitDamagedEvent
	return null
