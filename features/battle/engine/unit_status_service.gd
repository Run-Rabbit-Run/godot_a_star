class_name UnitStatusService
extends RefCounted

const DAMAGE_TYPES := DamageType.ALL

static func apply(unit: UnitState, id: StringName, levels: int, events: Array[BattleEvent]) -> void:
	if unit == null or unit.health.is_defeated() or levels <= 0 or not UnitStatusCatalog.has_status(id):
		return
	if unit.status_immunities.has(id):
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

static func damage(unit: UnitState, amount: int, type: StringName, events: Array[BattleEvent], source: StringName = &"", hex_state: StringName = &"", ability: StringName = &"", ranged_reduction: int = 0, status: StringName = &"", protection_hex_state: StringName = &"") -> void:
	if unit == null or unit.health.is_defeated() or amount <= 0:
		return
	var before := unit.statuses.duplicate()
	var adjusted := maxi(0, amount - ranged_reduction)
	var modifiers: Array[Dictionary] = []
	if adjusted != amount:
		modifiers.append({"source_id": protection_hex_state if not protection_hex_state.is_empty() else &"ranged_protection", "amount": adjusted - amount})
	var before_status_damage := adjusted
	var modifier_status: StringName = &""
	match type:
		&"physical":
			modifier_status = &"core:armor"
			adjusted = maxi(0, adjusted - int(unit.statuses.get(&"core:armor", 0)))
		&"fire":
			modifier_status = &"core:wet"
			var absorbed := mini(adjusted, int(unit.statuses.get(&"core:wet", 0)))
			adjusted -= absorbed
			_set_levels(unit, &"core:wet", int(unit.statuses.get(&"core:wet", 0)) - absorbed)
		&"water":
			if unit.statuses.get(&"core:plasma", 0) > 0:
				modifier_status = &"core:plasma"
				adjusted = 0
			else:
				modifier_status = &"core:burning"
				var absorbed := mini(adjusted, int(unit.statuses.get(&"core:burning", 0)))
				adjusted -= absorbed
				_set_levels(unit, &"core:burning", int(unit.statuses.get(&"core:burning", 0)) - absorbed)
		&"electric":
			modifier_status = &"core:wet"
			if adjusted > 0 and unit.statuses.get(&"core:wet", 0) > 0:
				adjusted += 1
	if adjusted != before_status_damage:
		modifiers.append({"source_id": modifier_status, "amount": adjusted - before_status_damage})
	_emit(unit, before, events)
	var applied := unit.health.apply_damage(adjusted)
	var event := UnitDamagedEvent.new(source, unit.unit_id, applied, unit.health.current, unit.health.is_defeated(), hex_state, ability)
	event.damage_type = type
	event.base_damage = amount
	event.calculated_damage = adjusted
	event.damage_modifiers.assign(modifiers)
	event.source_status_id = status
	events.append(event)
	if type == &"fire":
		_explode_oil(unit, events)

static func end_turn(unit: UnitState, events: Array[BattleEvent]) -> void:
	if unit == null or unit.health.is_defeated():
		return
	# Presence determines periodic damage; levels determine decay and thresholds.
	var burning := int(unit.statuses.get(&"core:burning", 0))
	var plasma := int(unit.statuses.get(&"core:plasma", 0))
	var electricity := int(unit.statuses.get(&"core:electrified", 0))
	damage(unit, 1 if burning > 0 else 0, &"fire", events, &"", &"", &"", 0, &"core:burning")
	damage(unit, 2 if plasma > 0 else 0, &"fire", events, &"", &"", &"", 0, &"core:plasma")
	damage(unit, 1 if electricity > 0 else 0, &"electric", events, &"", &"", &"", 0, &"core:electrified")
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
	damage(unit, amount, &"physical", events, &"", &"", &"", 0, &"core:sticky_oil")

static func _set_levels(unit: UnitState, id: StringName, levels: int) -> void:
	if levels <= 0:
		unit.statuses.erase(id)
	else:
		unit.statuses[id] = levels

static func _emit(unit: UnitState, before: Dictionary, events: Array[BattleEvent]) -> void:
	if before != unit.statuses:
		events.append(UnitStatusChangedEvent.new(unit, before))
