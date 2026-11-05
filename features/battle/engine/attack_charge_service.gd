class_name AttackChargeService
extends RefCounted
## The attack charge: the «Я здесь» passive gives it to a unit that starts its turn next to an
## opponent, and the unit's next own ordinary attack spends all of it for extra damage.


## Start of the unit's side phase, after its hex and statuses: a living unit that will take its
## turn tops its charge up to its passive's level while a living opponent stands next to it.
static func grant(state: BattleState, unit: UnitState, events: Array[BattleEvent]) -> void:
	if unit == null or unit.engaged_charge <= 0 or unit.health.is_defeated() or not unit.takes_turns():
		return
	# A paralyzed unit loses its turn, so it does not start one next to anybody.
	if unit.statuses.get(UnitStatusCatalog.PARALYSIS, 0) > 0:
		return
	var missing := unit.engaged_charge - int(unit.statuses.get(UnitStatusCatalog.ATTACK_CHARGE, 0))
	if missing > 0 and _next_to_opponent(state, unit):
		UnitStatusService.apply(unit, UnitStatusCatalog.ATTACK_CHARGE, missing, events)


## Takes the whole charge for the ordinary attack the unit is making; returns its levels.
static func spend(unit: UnitState, events: Array[BattleEvent]) -> int:
	var levels := int(unit.statuses.get(UnitStatusCatalog.ATTACK_CHARGE, 0))
	if levels <= 0:
		return 0
	var before := unit.statuses.duplicate()
	unit.statuses.erase(UnitStatusCatalog.ATTACK_CHARGE)
	events.append(UnitStatusChangedEvent.new(unit, before))
	return levels


static func _next_to_opponent(state: BattleState, unit: UnitState) -> bool:
	for other: UnitState in state.unit_states.values():
		if other.faction != unit.faction and not other.health.is_defeated() and HexGrid.get_distance(other.hex, unit.hex) == 1:
			return true
	return false
