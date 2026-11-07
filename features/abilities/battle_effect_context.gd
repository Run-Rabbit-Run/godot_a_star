class_name BattleEffectContext
extends RefCounted


var _state: BattleState
var _ability_id: StringName
var target_hex := Vector2i.ZERO
## The faction whose strategist uses the ability, or -1 for a unit's ability.
var acting_faction := -1
var _failure := ""


func _init(state: BattleState, ability_id: StringName = StringName()) -> void:
	_state = state
	_ability_id = ability_id


## A handler calls this when its effect cannot be completed. The engine then discards the
## whole ability, so a handler never has to undo the changes it has already made.
func fail(reason: String) -> void:
	if _failure.is_empty():
		_failure = reason if not reason.is_empty() else "Ability effect failed."


func has_failed() -> bool:
	return not _failure.is_empty()


func get_failure() -> String:
	return _failure


func get_corpses_at(hex: Vector2i) -> Array[UnitSnapshot]:
	return _state.get_corpses_at(hex)


## A unit definition an effect of this battle references (AbilityEffectHandler.get_unit_references),
## or null. The battle resolved it at setup; it is read-only.
func get_unit_definition(id: StringName) -> UnitDefinition:
	return _state.unit_definitions.get(id) as UnitDefinition


func summon(source_id: StringName, hex: Vector2i, definition: UnitDefinition) -> Array[BattleEvent]:
	var events: Array[BattleEvent] = []
	var source := _state.unit_states.get(source_id) as UnitState
	if source == null or not _state.hex_grid.is_traversable(hex):
		fail("Summon needs a living source and a traversable hex: %s." % hex)
		return events
	for candidate: UnitState in _state.unit_states.values():
		if candidate.hex == hex and not candidate.health.is_defeated():
			fail("Summon target is occupied: %s." % hex)
			return events
	var unit := _spawn(source_id, source.faction, hex, definition)
	if unit == null:
		return events
	events.append(UnitSummonedEvent.new(source_id, unit, definition))
	HexStateService.expose(unit, _state.hex_grid, events)
	return events


## Adds the missing hex next to the battlefield and drops the strategist's unit onto it; the unit
## holds the hex while it lives.
func land(source_id: StringName, hex: Vector2i, definition: UnitDefinition, terrain_id: StringName) -> Array[BattleEvent]:
	var events: Array[BattleEvent] = []
	if acting_faction < 0:
		fail("Landing needs the strategist's faction.")
		return events
	if _state.hex_grid.has_cell(hex):
		fail("Landing needs a hex outside the battlefield: %s." % hex)
		return events
	var touches_field := false
	for direction: Vector2i in HexGrid.DIRECTIONS:
		touches_field = touches_field or _state.hex_grid.has_cell(hex + direction)
	if not touches_field:
		fail("Landing hex must touch the battlefield: %s." % hex)
		return events
	var mutations: Array[MapMutation] = [MapMutation.add_hex(hex, terrain_id)]
	var added := MapMutationService.apply(_state, mutations)
	if not added.accepted:
		fail(added.rejection_reason)
		return events
	events.append_array(added.events)
	var unit := _spawn(source_id, acting_faction as BattleFaction.Value, hex, definition)
	if unit == null:
		return events
	unit.holds_hex = true
	unit.summoned_by = _ability_id
	events.append(UnitSummonedEvent.new(source_id, unit, definition))
	HexStateService.expose(unit, _state.hex_grid, events)
	return events


## A new summoned participant with a deterministic unique ID; it acts from its side's next phase.
func _spawn(source_id: StringName, faction: BattleFaction.Value, hex: Vector2i, definition: UnitDefinition) -> UnitState:
	var suffix := _state.unit_states.size()
	var id := StringName("%s:summon:%d" % [source_id, suffix])
	while _state.unit_states.has(id):
		suffix += 1
		id = StringName("%s:summon:%d" % [source_id, suffix])
	var spawn := UnitSpawnData.new(id, id, definition.id, definition, &"", faction, BattleControlSource.Value.PLAYER, &"", null, hex)
	var unit := UnitStateFactory.create(spawn)
	if unit == null:
		fail("Summoned unit could not be created: %s." % definition.id)
		return null
	unit.is_summoned = true
	_state.unit_states[id] = unit
	_state.turn_service.add_participant(id)
	return unit


## A detached copy of the obstacle at the hex, or null.
func get_obstacle(hex: Vector2i) -> BattleObstacleDefinition:
	return _state.hex_grid.get_obstacle(hex)


## A flask it destroys bursts; a burst the map refuses fails the ability.
func damage_obstacle(hex: Vector2i, amount: int) -> Array[BattleEvent]:
	var events: Array[BattleEvent] = []
	var error := ObstacleService.damage(_state, hex, amount, events)
	if not error.is_empty():
		fail(error)
	return events


func get_base_attack_damage(id: StringName) -> int:
	var unit := _state.unit_states.get(id) as UnitState
	return unit.basic_attack_damage if unit != null else 0


func get_unit_hex(id: StringName) -> Vector2i:
	var unit := _state.unit_states.get(id) as UnitState
	return unit.hex if unit != null else Vector2i.ZERO


func apply_unit_status(target_id: StringName, status_id: StringName, levels: int) -> Array[BattleEvent]:
	var events: Array[BattleEvent] = []
	var target := _state.unit_states.get(target_id) as UnitState
	if target == null or not UnitStatusCatalog.has_status(status_id):
		fail("Unit status %s needs an existing target: %s." % [status_id, target_id])
		return events
	UnitStatusService.apply(target, status_id, levels, events)
	return events


## Restores the target's health when its body is `body`: heals a living body, repairs a mechanical
## one. A defeated target or one of the other body is left as it is, without an event.
func heal(source_unit_id: StringName, target_id: StringName, amount: int, body: StringName) -> Array[BattleEvent]:
	var events: Array[BattleEvent] = []
	var target := _state.unit_states.get(target_id) as UnitState
	if target == null:
		fail("Heal needs an existing target: %s." % target_id)
		return events
	if target.health.is_defeated() or target.body != body:
		return events
	var restored := target.health.restore(amount)
	events.append(UnitHealedEvent.new(target_id, source_unit_id, _ability_id, body, restored, target.health.current, target.health.maximum))
	return events


func apply_hex_state(hex: Vector2i, id: StringName) -> Array[BattleEvent]:
	var hexes: Array[Vector2i] = [hex]
	return apply_hex_states(hexes, id)


## One atomic batch: every cell changes before reactions spread, so cell order does not matter.
func apply_hex_states(hexes: Array[Vector2i], id: StringName) -> Array[BattleEvent]:
	var mutations: Array[MapMutation] = []
	for hex: Vector2i in hexes:
		mutations.append(MapMutation.apply_hex_state(hex, id))
	if mutations.is_empty():
		var none: Array[BattleEvent] = []
		return none
	var result := MapMutationService.apply(_state, mutations)
	if not result.accepted:
		fail(result.rejection_reason)
	return result.events


## Pushes the target straight away from the source's hex. A target off the source's six axes
## has no such line and stays in place; a defeated one is not moved.
func push(source_unit_id: StringName, target_unit_id: StringName, distance: int) -> Array[BattleEvent]:
	var events: Array[BattleEvent] = []
	var source := _state.unit_states.get(source_unit_id) as UnitState
	var target := _state.unit_states.get(target_unit_id) as UnitState
	if source == null or target == null:
		fail("Push needs an existing source and target: %s -> %s." % [source_unit_id, target_unit_id])
		return events
	var direction := AbilityExecutor.get_line_direction(source.hex, target.hex)
	if direction != Vector2i.ZERO:
		var error := PushService.push(_state, source_unit_id, target_unit_id, direction, distance, _ability_id, events)
		if not error.is_empty():
			fail(error)
	return events


func apply_damage_events(source_unit_id: StringName, target_unit_id: StringName, amount: int, type: StringName = &"physical") -> Array[BattleEvent]:
	var events: Array[BattleEvent] = []
	var source := _state.unit_states.get(source_unit_id) as UnitState
	var target := _state.unit_states.get(target_unit_id) as UnitState
	if source == null or target == null:
		fail("Damage needs an existing source and target: %s -> %s." % [source_unit_id, target_unit_id])
		return events
	var ability := source.get_ability(_ability_id)
	var ranged := ability != null and ability.get_range(source) > 1
	var protection_hex_state := _state.hex_grid.get_liquid(target.hex)
	var reduction := HexStateCatalog.ranged_reduction(protection_hex_state) if ranged else 0
	var hit := DamageRequest.new(amount, type).from_unit(source_unit_id).with_ability(_ability_id)
	UnitStatusService.damage(target, hit.with_cover(reduction, protection_hex_state), events)
	var reaction_error := DamageType.react(_state, target.hex, type, events)
	if not reaction_error.is_empty():
		fail(reaction_error)
	return events
