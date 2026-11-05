class_name TurnService
extends RefCounted
## Side phases: the player faction acts with its units in any order, then the enemy faction.
## A unit that started its turn with a command finishes it before another unit may act.
## Whenever an order among units matters, it is their FieldOrder at that moment.

var _participants: Array[StringName] = []
## The battle's unit registry: readiness reads current faction, health and paralysis.
var _units: Dictionary[StringName, UnitState] = {}
var _active_faction := BattleFaction.Value.PLAYER
var _round_number := 0
var _started := false
## Units that cannot act again this phase: they finished, or joined it as summons.
var _finished: Dictionary[StringName, bool] = {}
## Units whose turn ended this phase; true when paralysis kept the unit from acting in it.
var _ended: Dictionary[StringName, bool] = {}
var _current_unit_id := StringName()
## The acting faction's strategist has used its ability this phase.
var _strategist_used := false


## `units` is shared, not copied: the service sees every change of the battle's units.
func _init(turn_order: Array[StringName], units: Dictionary[StringName, UnitState] = {}) -> void:
	_participants.assign(turn_order)
	_units = units


## Opens round 1 with the player phase and returns its first ready unit.
func start() -> StringName:
	_started = not _participants.is_empty()
	_round_number = 1 if _started else 0
	_active_faction = BattleFaction.Value.PLAYER
	_clear_phase()
	return get_active_unit_id()


func get_round_number() -> int:
	return _round_number


func get_active_faction() -> BattleFaction.Value:
	return _active_faction


## The started unit, otherwise the first ready unit of the phase in field order.
func get_active_unit_id() -> StringName:
	if not _current_unit_id.is_empty():
		return _current_unit_id
	for unit_id: StringName in get_turn_order():
		if can_still_act(unit_id):
			return unit_id
	return StringName()


## The unit whose turn a command started and has not finished, or "".
func get_current_unit_id() -> StringName:
	return _current_unit_id


## True when the unit may act in this phase at all, ignoring which unit has started.
## An object that never takes turns is never ready.
func can_still_act(unit_id: StringName) -> bool:
	var unit := _units.get(unit_id) as UnitState
	return (
		_started
		and unit != null
		and unit.faction == _active_faction
		and unit.takes_turns()
		and not unit.health.is_defeated()
		and unit.statuses.get(UnitStatusCatalog.PARALYSIS, 0) <= 0
		and not _finished.has(unit_id)
	)


## True when a command of this unit is allowed now: it may act and no other unit has started.
func can_command(unit_id: StringName) -> bool:
	return can_still_act(unit_id) and (_current_unit_id.is_empty() or _current_unit_id == unit_id)


## Units that may still act this phase, in field order.
func get_ready_unit_ids() -> Array[StringName]:
	var ready: Array[StringName] = []
	for unit_id: StringName in get_turn_order():
		if can_still_act(unit_id):
			ready.append(unit_id)
	return ready


## Living units of the acting faction in field order.
func get_phase_unit_ids() -> Array[StringName]:
	var phase_units: Array[StringName] = []
	for unit_id: StringName in get_turn_order():
		var unit := _units.get(unit_id) as UnitState
		if unit != null and unit.faction == _active_faction and not unit.health.is_defeated():
			phase_units.append(unit_id)
	return phase_units


func begin_unit(unit_id: StringName) -> void:
	_current_unit_id = unit_id


## The unit cannot act again this phase.
func finish_unit(unit_id: StringName) -> void:
	_finished[unit_id] = true
	if _current_unit_id == unit_id:
		_current_unit_id = StringName()


func has_finished(unit_id: StringName) -> bool:
	return _finished.has(unit_id)


## `lost_to_paralysis`: the unit could still act in this phase when paralysis ended its turn.
func mark_ended(unit_id: StringName, lost_to_paralysis := false) -> void:
	_ended[unit_id] = lost_to_paralysis


func has_ended(unit_id: StringName) -> bool:
	return _ended.has(unit_id)


## Whether paralysis cost the unit its turn in this phase.
func lost_turn_to_paralysis(unit_id: StringName) -> bool:
	return _ended.get(unit_id, false)


## Whether the acting faction's strategist has already used an ability this phase.
func is_strategist_used() -> bool:
	return _strategist_used


func mark_strategist_used() -> void:
	_strategist_used = true


## Passes the turn to the other faction; returns true when this opens a new round.
func advance_phase() -> bool:
	if not _started:
		return false
	var new_round := _active_faction == BattleFaction.Value.ENEMY
	_active_faction = BattleFaction.Value.PLAYER if new_round else BattleFaction.Value.ENEMY
	if new_round:
		_round_number += 1
	_clear_phase()
	return new_round


## The service of a copied battle reads the copy's units.
func duplicate_service(units: Dictionary[StringName, UnitState]) -> TurnService:
	var copy := TurnService.new(_participants, units)
	copy._copy_phase(self)
	return copy


## Takes over another service's order and phase; keeps reading this battle's units.
func copy_from(other: TurnService) -> void:
	_participants.assign(other._participants)
	_copy_phase(other)


func get_participant_count() -> int:
	return _participants.size()


## A unit joining the acting faction acts from its next phase.
func add_participant(unit_id: StringName) -> void:
	if _participants.has(unit_id):
		return
	_participants.append(unit_id)
	var unit := _units.get(unit_id) as UnitState
	if unit != null and unit.faction == _active_faction:
		_finished[unit_id] = true


## Every participant: the player's units, then the enemy's, each in current field order.
func get_turn_order() -> Array[StringName]:
	return FieldOrder.sort_ids(_participants, _units)


func _clear_phase() -> void:
	_finished.clear()
	_ended.clear()
	_current_unit_id = StringName()
	_strategist_used = false


func _copy_phase(other: TurnService) -> void:
	_active_faction = other._active_faction
	_round_number = other._round_number
	_started = other._started
	_finished = other._finished.duplicate()
	_ended = other._ended.duplicate()
	_current_unit_id = other._current_unit_id
	_strategist_used = other._strategist_used
