class_name UnitStatusService
extends RefCounted

const DAMAGE_TYPES := DamageType.ALL

static func apply(unit: UnitState, id: StringName, levels: int, events: Array[BattleEvent]) -> void:
	if unit == null or unit.health.is_defeated() or levels <= 0 or not UnitStatusCatalog.has_status(id):
		return
	if unit.status_immunities.has(id):
		return
	# Resistance keeps paralysis away while it lasts.
	if id == &"core:paralysis" and unit.statuses.get(&"core:paralysis_resistance", 0) > 0:
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
	if id == &"core:paralysis_resistance":
		unit.statuses.erase(&"core:paralysis")
	var previous := int(unit.statuses.get(id, 0))
	# Paralysis never stacks past one level: it always costs exactly the next own turn.
	_set_levels(unit, id, mini(1, previous + levels) if id == &"core:paralysis" else previous + levels)
	if id == &"core:acid" and unit.statuses.get(id, 0) >= 5:
		unit.statuses.erase(id)
		unit.statuses.erase(&"core:armor")
	if id in [&"core:electrified", &"core:plasma"] and levels > 0 and unit.statuses.get(id, 0) >= 5 and unit.statuses.get(&"core:paralysis_resistance", 0) <= 0 and not unit.status_immunities.has(&"core:paralysis"):
		_set_levels(unit, &"core:paralysis", 1)
	unit.turn.movement_remaining = maxi(0, unit.turn.movement_remaining - maxi(0, UnitStatusCatalog.movement_penalty(unit.statuses) - old_penalty))
	_emit(unit, before, events)
	if id == &"core:burning" or (id == &"core:sticky_oil" and unit.statuses.get(&"core:burning", 0) > 0):
		_explode_oil(unit, events)

static func damage(unit: UnitState, request: DamageRequest, events: Array[BattleEvent]) -> void:
	var amount := request.amount
	if unit == null or unit.health.is_defeated() or amount <= 0:
		return
	var before := unit.statuses.duplicate()
	var modifiers: Array[Dictionary] = []
	var penalized := maxi(0, amount - request.melee_penalty)
	if penalized != amount:
		modifiers.append({"source_id": BasicAttackRules.RANGED_MELEE_PENALTY, "amount": penalized - amount})
	var adjusted := maxi(0, penalized - request.ranged_reduction)
	if adjusted != penalized:
		modifiers.append({"source_id": request.cover_hex_state_id if not request.cover_hex_state_id.is_empty() else &"ranged_protection", "amount": adjusted - penalized})
	var before_status_damage := adjusted
	var modifier_status: StringName = &""
	match request.type:
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
	var event := UnitDamagedEvent.new(request.source_unit_id, unit.unit_id, applied, unit.health.current, unit.health.is_defeated(), request.source_hex_state_id, request.source_ability_id)
	event.damage_type = request.type
	event.base_damage = amount
	event.calculated_damage = adjusted
	event.damage_modifiers.assign(modifiers)
	event.source_status_id = request.source_status_id
	events.append(event)
	if request.type == &"fire":
		_explode_oil(unit, events)

static func end_turn(unit: UnitState, events: Array[BattleEvent]) -> void:
	if unit == null or unit.health.is_defeated():
		return
	# Presence determines periodic damage; levels determine decay and thresholds.
	var burning := int(unit.statuses.get(&"core:burning", 0))
	var plasma := int(unit.statuses.get(&"core:plasma", 0))
	var electricity := int(unit.statuses.get(&"core:electrified", 0))
	damage(unit, DamageRequest.new(1 if burning > 0 else 0, &"fire").from_status(&"core:burning"), events)
	damage(unit, DamageRequest.new(2 if plasma > 0 else 0, &"fire").from_status(&"core:plasma"), events)
	damage(unit, DamageRequest.new(1 if electricity > 0 else 0, &"electric").from_status(&"core:electrified"), events)
	var before := unit.statuses.duplicate()
	var was_paralyzed: bool = unit.statuses.get(&"core:paralysis", 0) > 0
	if unit.statuses.get(&"core:acid", 0) > 0:
		_set_levels(unit, &"core:armor", int(unit.statuses.get(&"core:armor", 0)) - 1)
	for id: StringName in unit.statuses.keys():
		if id != &"core:armor":
			_set_levels(unit, id, int(unit.statuses[id]) - 1)
	# Worn-off paralysis leaves one level of resistance, added after the decay so that it
	# lasts through the opponent's phase and the unit's next own turn.
	if was_paralyzed and not unit.statuses.has(&"core:paralysis"):
		unit.statuses[&"core:paralysis_resistance"] = 1
	_emit(unit, before, events)

static func _explode_oil(unit: UnitState, events: Array[BattleEvent]) -> void:
	var oil := int(unit.statuses.get(&"core:sticky_oil", 0))
	if oil <= 0 or unit.health.is_defeated():
		return
	var amount := oil + int(unit.statuses.get(&"core:burning", 0))
	var before := unit.statuses.duplicate()
	unit.statuses.erase(&"core:sticky_oil")
	_emit(unit, before, events)
	damage(unit, DamageRequest.new(amount).from_status(&"core:sticky_oil"), events)

static func _set_levels(unit: UnitState, id: StringName, levels: int) -> void:
	if levels <= 0:
		unit.statuses.erase(id)
	else:
		unit.statuses[id] = levels

static func _emit(unit: UnitState, before: Dictionary, events: Array[BattleEvent]) -> void:
	if before != unit.statuses:
		events.append(UnitStatusChangedEvent.new(unit, before))
