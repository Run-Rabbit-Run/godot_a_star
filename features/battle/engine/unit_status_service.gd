class_name UnitStatusService
extends RefCounted

const DAMAGE_TYPES := DamageType.ALL

static func apply(unit: UnitState, id: StringName, levels: int, events: Array[BattleEvent]) -> void:
	if unit == null or unit.health.is_defeated() or levels <= 0 or not UnitStatusCatalog.has_status(id):
		return
	if unit.status_immunities.has(id):
		return
	# Resistance keeps paralysis away while it lasts.
	if id == UnitStatusCatalog.PARALYSIS and unit.statuses.get(UnitStatusCatalog.PARALYSIS_RESISTANCE, 0) > 0:
		return
	var before := unit.statuses.duplicate()
	var old_penalty := UnitStatusCatalog.movement_penalty(before)
	if id == UnitStatusCatalog.WET and unit.statuses.get(UnitStatusCatalog.PLASMA, 0) > 0:
		return
	if id == UnitStatusCatalog.PLASMA:
		unit.statuses.erase(UnitStatusCatalog.WET)
	if id == UnitStatusCatalog.WET or id == UnitStatusCatalog.BURNING:
		var opposite: StringName = UnitStatusCatalog.BURNING if id == UnitStatusCatalog.WET else UnitStatusCatalog.WET
		var cancelled := mini(levels, int(unit.statuses.get(opposite, 0)))
		_set_levels(unit, opposite, int(unit.statuses.get(opposite, 0)) - cancelled)
		levels -= cancelled
	if id == UnitStatusCatalog.PARALYSIS_RESISTANCE:
		unit.statuses.erase(UnitStatusCatalog.PARALYSIS)
	var previous := int(unit.statuses.get(id, 0))
	# Paralysis never stacks past one level: it always costs exactly the next own turn.
	_set_levels(unit, id, mini(1, previous + levels) if id == UnitStatusCatalog.PARALYSIS else previous + levels)
	if id == UnitStatusCatalog.ACID and unit.statuses.get(id, 0) >= 5:
		unit.statuses.erase(id)
		unit.statuses.erase(UnitStatusCatalog.ARMOR)
	if id in [UnitStatusCatalog.ELECTRIFIED, UnitStatusCatalog.PLASMA] and levels > 0 and unit.statuses.get(id, 0) >= 5 and unit.statuses.get(UnitStatusCatalog.PARALYSIS_RESISTANCE, 0) <= 0 and not unit.status_immunities.has(UnitStatusCatalog.PARALYSIS):
		_set_levels(unit, UnitStatusCatalog.PARALYSIS, 1)
	unit.turn.movement_remaining = maxi(0, unit.turn.movement_remaining - maxi(0, UnitStatusCatalog.movement_penalty(unit.statuses) - old_penalty))
	_emit(unit, before, events)
	if id == UnitStatusCatalog.BURNING or (id == UnitStatusCatalog.STICKY_OIL and unit.statuses.get(UnitStatusCatalog.BURNING, 0) > 0):
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
			modifier_status = UnitStatusCatalog.ARMOR
			adjusted = maxi(0, adjusted - int(unit.statuses.get(UnitStatusCatalog.ARMOR, 0)))
		&"fire":
			modifier_status = UnitStatusCatalog.WET
			var absorbed := mini(adjusted, int(unit.statuses.get(UnitStatusCatalog.WET, 0)))
			adjusted -= absorbed
			_set_levels(unit, UnitStatusCatalog.WET, int(unit.statuses.get(UnitStatusCatalog.WET, 0)) - absorbed)
		&"water":
			if unit.statuses.get(UnitStatusCatalog.PLASMA, 0) > 0:
				modifier_status = UnitStatusCatalog.PLASMA
				adjusted = 0
			else:
				modifier_status = UnitStatusCatalog.BURNING
				var absorbed := mini(adjusted, int(unit.statuses.get(UnitStatusCatalog.BURNING, 0)))
				adjusted -= absorbed
				_set_levels(unit, UnitStatusCatalog.BURNING, int(unit.statuses.get(UnitStatusCatalog.BURNING, 0)) - absorbed)
		&"electric":
			modifier_status = UnitStatusCatalog.WET
			if adjusted > 0 and unit.statuses.get(UnitStatusCatalog.WET, 0) > 0:
				adjusted += 1
	if adjusted != before_status_damage:
		modifiers.append({"source_id": modifier_status, "amount": adjusted - before_status_damage})
	_emit(unit, before, events)
	var applied := unit.health.apply_damage(adjusted)
	var event := UnitDamagedEvent.new(request.source_unit_id, unit.unit_id, applied, unit.health.current, unit.health.is_defeated(), request.source_hex_state_id, request.source_ability_id)
	event.damage_type = request.type
	event.target_health_maximum = unit.health.maximum
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
	var burning := int(unit.statuses.get(UnitStatusCatalog.BURNING, 0))
	var plasma := int(unit.statuses.get(UnitStatusCatalog.PLASMA, 0))
	var electricity := int(unit.statuses.get(UnitStatusCatalog.ELECTRIFIED, 0))
	damage(unit, DamageRequest.new(1 if burning > 0 else 0, &"fire").from_status(UnitStatusCatalog.BURNING), events)
	damage(unit, DamageRequest.new(2 if plasma > 0 else 0, &"fire").from_status(UnitStatusCatalog.PLASMA), events)
	damage(unit, DamageRequest.new(1 if electricity > 0 else 0, &"electric").from_status(UnitStatusCatalog.ELECTRIFIED), events)
	var before := unit.statuses.duplicate()
	var was_paralyzed: bool = unit.statuses.get(UnitStatusCatalog.PARALYSIS, 0) > 0
	if unit.statuses.get(UnitStatusCatalog.ACID, 0) > 0:
		_set_levels(unit, UnitStatusCatalog.ARMOR, int(unit.statuses.get(UnitStatusCatalog.ARMOR, 0)) - 1)
	for id: StringName in unit.statuses.keys():
		if id != UnitStatusCatalog.ARMOR:
			_set_levels(unit, id, int(unit.statuses[id]) - 1)
	# Worn-off paralysis leaves one level of resistance, added after the decay so that it
	# lasts through the opponent's phase and the unit's next own turn.
	if was_paralyzed and not unit.statuses.has(UnitStatusCatalog.PARALYSIS):
		unit.statuses[UnitStatusCatalog.PARALYSIS_RESISTANCE] = 1
	_emit(unit, before, events)

static func _explode_oil(unit: UnitState, events: Array[BattleEvent]) -> void:
	var oil := int(unit.statuses.get(UnitStatusCatalog.STICKY_OIL, 0))
	if oil <= 0 or unit.health.is_defeated():
		return
	var amount := oil + int(unit.statuses.get(UnitStatusCatalog.BURNING, 0))
	var before := unit.statuses.duplicate()
	unit.statuses.erase(UnitStatusCatalog.STICKY_OIL)
	_emit(unit, before, events)
	damage(unit, DamageRequest.new(amount).from_status(UnitStatusCatalog.STICKY_OIL), events)

static func _set_levels(unit: UnitState, id: StringName, levels: int) -> void:
	if levels <= 0:
		unit.statuses.erase(id)
	else:
		unit.statuses[id] = levels

static func _emit(unit: UnitState, before: Dictionary, events: Array[BattleEvent]) -> void:
	if before != unit.statuses:
		events.append(UnitStatusChangedEvent.new(unit, before))
