class_name UnitStatusService
extends RefCounted

const DAMAGE_TYPES := [&"physical", &"fire", &"water", &"electric", &"acid"]

static func apply(unit: UnitState, id: StringName, levels: int, events: Array[BattleEvent]) -> void:
	if unit == null or unit.health.is_defeated() or levels <= 0 or not UnitStatusCatalog.has_status(id):
		return
	var before := unit.statuses.duplicate()
	var old_penalty := UnitStatusCatalog.movement_penalty(before)
	if id == &"core:wet" and unit.statuses.get(&"core:plasma", 0) > 0:
		return
	if id == &"core:plasma":
		unit.statuses.erase(&"core:wet")
	if id == &"core:wet" or id == &"core:burning":
		var opposite: StringName = &"core:burning" if id == &"core:wet" else &"core:wet"
		var cancelled := mini(levels, int(unit.statuses.get(opposite, 0)))
		_set_levels(unit, opposite, int(unit.statuses.get(opposite, 0)) - cancelled)
		levels -= cancelled
	var previous := int(unit.statuses.get(id, 0))
	_set_levels(unit, id, previous + levels)
	if id == &"core:acid" and unit.statuses.get(id, 0) >= 5:
		unit.statuses.erase(id)
		unit.statuses.erase(&"core:armor")
	if id in [&"core:electrified", &"core:plasma"] and levels > 0 and unit.statuses.get(id, 0) >= 5:
		_set_levels(unit, &"core:paralysis", int(unit.statuses.get(&"core:paralysis", 0)) + 1)
	unit.turn.movement_remaining = maxi(0, unit.turn.movement_remaining - maxi(0, UnitStatusCatalog.movement_penalty(unit.statuses) - old_penalty))
	_emit(unit, before, events)
	if id == &"core:burning" or (id == &"core:sticky_oil" and unit.statuses.get(&"core:burning", 0) > 0):
		_explode_oil(unit, events)

static func damage(unit: UnitState, amount: int, type: StringName, events: Array[BattleEvent], source: StringName = &"", hex_state: StringName = &"", ability: StringName = &"", ranged_reduction: int = 0) -> void:
	if unit == null or unit.health.is_defeated() or amount <= 0:
		return
	var before := unit.statuses.duplicate()
	var adjusted := maxi(0, amount - ranged_reduction)
	match type:
		&"physical":
			adjusted = maxi(0, adjusted - int(unit.statuses.get(&"core:armor", 0)))
		&"fire":
			var absorbed := mini(adjusted, int(unit.statuses.get(&"core:wet", 0)))
			adjusted -= absorbed
			_set_levels(unit, &"core:wet", int(unit.statuses.get(&"core:wet", 0)) - absorbed)
		&"water":
			if unit.statuses.get(&"core:plasma", 0) > 0:
				adjusted = 0
			else:
				var absorbed := mini(adjusted, int(unit.statuses.get(&"core:burning", 0)))
				adjusted -= absorbed
				_set_levels(unit, &"core:burning", int(unit.statuses.get(&"core:burning", 0)) - absorbed)
		&"electric":
			if adjusted > 0:
				adjusted += int(unit.statuses.get(&"core:wet", 0))
	_emit(unit, before, events)
	var applied := unit.health.apply_damage(adjusted)
	var event := UnitDamagedEvent.new(source, unit.unit_id, applied, unit.health.current, unit.health.is_defeated(), hex_state, ability)
	event.damage_type = type
	events.append(event)
	if type == &"fire":
		_explode_oil(unit, events)

static func end_turn(unit: UnitState, events: Array[BattleEvent]) -> void:
	if unit == null or unit.health.is_defeated():
		return
	# Use the levels present at the end of the turn, before decay.
	var burning := int(unit.statuses.get(&"core:burning", 0))
	var plasma := int(unit.statuses.get(&"core:plasma", 0))
	var electricity := int(unit.statuses.get(&"core:electrified", 0))
	damage(unit, burning, &"fire", events, &"", &"core:fire")
	damage(unit, plasma * 2, &"fire", events, &"", &"core:plasma")
	damage(unit, electricity, &"electric", events, &"", &"core:electricity")
	var before := unit.statuses.duplicate()
	if unit.statuses.get(&"core:acid", 0) > 0:
		_set_levels(unit, &"core:armor", int(unit.statuses.get(&"core:armor", 0)) - 1)
	for id: StringName in unit.statuses.keys():
		if id != &"core:armor":
			_set_levels(unit, id, int(unit.statuses[id]) - 1)
	_emit(unit, before, events)

static func _explode_oil(unit: UnitState, events: Array[BattleEvent]) -> void:
	var oil := int(unit.statuses.get(&"core:sticky_oil", 0))
	if oil <= 0 or unit.health.is_defeated():
		return
	var amount := oil + int(unit.statuses.get(&"core:burning", 0))
	var before := unit.statuses.duplicate()
	unit.statuses.erase(&"core:sticky_oil")
	_emit(unit, before, events)
	damage(unit, amount, &"physical", events, &"", &"core:burning_oil")

static func _set_levels(unit: UnitState, id: StringName, levels: int) -> void:
	if levels <= 0:
		unit.statuses.erase(id)
	else:
		unit.statuses[id] = levels

static func _emit(unit: UnitState, before: Dictionary, events: Array[BattleEvent]) -> void:
	if before != unit.statuses:
		events.append(UnitStatusChangedEvent.new(unit, before))
