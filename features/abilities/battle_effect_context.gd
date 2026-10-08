class_name BattleEffectContext
extends RefCounted


var _state: BattleState
var _ability_id: StringName
var target_hex := Vector2i.ZERO


func _init(state: BattleState, ability_id: StringName = StringName()) -> void:
	_state = state
	_ability_id = ability_id


func get_corpses_at(hex: Vector2i) -> Array[UnitSnapshot]:
	return _state.get_corpses_at(hex)


func summon(source_id: StringName, hex: Vector2i, definition: UnitDefinition) -> Array[BattleEvent]:
	var events: Array[BattleEvent] = []
	var source := _state.unit_states.get(source_id) as UnitState
	if source == null or not _state.hex_grid.is_traversable(hex):
		return events
	for candidate: UnitState in _state.unit_states.values():
		if candidate.hex == hex and not candidate.health.is_defeated():
			return events
	var suffix := _state.unit_states.size()
	var id := StringName("%s:summon:%d" % [source_id, suffix])
	while _state.unit_states.has(id):
		suffix += 1
		id = StringName("%s:summon:%d" % [source_id, suffix])
	var spawn := UnitSpawnData.new(id, id, definition.id, definition, &"", source.faction, BattleControlSource.Value.PLAYER, &"", null, hex)
	var unit := UnitStateFactory.create(spawn)
	if unit == null:
		return events
	_state.unit_states[id] = unit
	_state.turn_service.add_participant(id)
	events.append(UnitSummonedEvent.new(source_id, unit, definition))
	HexStateService.expose(unit, _state.hex_grid, events)
	return events


func get_unit_hex(id: StringName) -> Vector2i:
	var unit := _state.unit_states.get(id) as UnitState
	return unit.hex if unit != null else Vector2i.ZERO


func apply_unit_status(target_id: StringName, status_id: StringName, levels: int) -> Array[BattleEvent]:
	var events: Array[BattleEvent] = []
	UnitStatusService.apply(_state.unit_states.get(target_id) as UnitState, status_id, levels, events)
	return events


func apply_hex_state(hex: Vector2i, id: StringName) -> Array[BattleEvent]:
	var hexes: Array[Vector2i] = [hex]
	return apply_hex_states(hexes, id)


## One atomic batch: every cell changes before reactions spread, so cell order does not matter.
func apply_hex_states(hexes: Array[Vector2i], id: StringName) -> Array[BattleEvent]:
	var mutations: Array[MapMutation] = []
	for hex: Vector2i in hexes:
		mutations.append(MapMutation.apply_hex_state(hex, id))
	var result := MapMutationService.apply(_state, mutations)
	return result.events


func apply_damage_events(source_unit_id: StringName, target_unit_id: StringName, amount: int, type: StringName = &"physical") -> Array[BattleEvent]:
	var events: Array[BattleEvent] = []
	var source := _state.unit_states.get(source_unit_id) as UnitState
	var target := _state.unit_states.get(target_unit_id) as UnitState
	if source == null or target == null:
		return events
	var ability := source.get_ability(_ability_id)
	var ranged := ability != null and ability.get_range(source) > 1
	var protection_hex_state := _state.hex_grid.get_hex_state_id(target.hex)
	var reduction := HexStateCatalog.ranged_reduction(protection_hex_state) if ranged else 0
	UnitStatusService.damage(target, amount, type, events, source_unit_id, &"", _ability_id, reduction, &"", protection_hex_state)
	events.append_array(DamageType.react(_state, target.hex, type))
	return events


# Compatibility for existing external handlers. Use apply_damage_events for compound effects.
func apply_damage(source_unit_id: StringName, target_unit_id: StringName, amount: int) -> UnitDamagedEvent:
	var events := apply_damage_events(source_unit_id, target_unit_id, amount)
	for event: BattleEvent in events:
		if event is UnitDamagedEvent:
			return event as UnitDamagedEvent
	return null
