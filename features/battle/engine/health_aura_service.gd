class_name HealthAuraService
extends RefCounted
## Allied maximum-health auras. While a unit with `ally_max_health_bonus` lives, every other
## living unit of its faction has that much more maximum health. A gained bonus raises the
## current health too; a lost one lowers the maximum and the current health keeps what is left
## up to the new maximum.


## Brings every living unit's bonus to what the living aura sources give it now.
static func refresh(state: BattleState, events: Array[BattleEvent]) -> void:
	# Forecasts call this after every action: a battle without auras returns at once.
	var involved := false
	for unit: UnitState in state.unit_states.values():
		if unit.ally_max_health_bonus > 0 or unit.max_health_bonus != 0:
			involved = true
			break
	if not involved:
		return
	var ids := IdOrder.sorted(state.unit_states.keys())
	for id: StringName in ids:
		var unit: UnitState = state.unit_states[id]
		if unit.health.is_defeated():
			continue
		var bonus := _bonus_for(state, unit)
		if bonus == unit.max_health_bonus:
			continue
		var health_before := unit.health.current
		var maximum_before := unit.health.maximum
		var change := bonus - unit.max_health_bonus
		unit.health.maximum = maxi(1, unit.health.maximum + change)
		if change > 0:
			unit.health.current += change
		else:
			unit.health.current = mini(unit.health.current, unit.health.maximum)
		unit.max_health_bonus = bonus
		events.append(UnitHealthChangedEvent.new(id, health_before, maximum_before, unit.health.current, unit.health.maximum))


static func _bonus_for(state: BattleState, unit: UnitState) -> int:
	var bonus := 0
	for source: UnitState in state.unit_states.values():
		if source != unit and source.faction == unit.faction and source.ally_max_health_bonus > 0 and not source.health.is_defeated():
			bonus += source.ally_max_health_bonus
	return bonus
