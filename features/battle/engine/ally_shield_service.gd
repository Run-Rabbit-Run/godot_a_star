class_name AllyShieldService
extends RefCounted
## The «Плечом к плечу» passive: a unit that ends its own turn next to a living ally raises a
## shield, which falls at the start of its side's next phase like any shield.


## Shield levels the unit raises as it ends its turn: its passive's levels while a living ally
## of its faction stands next to it, otherwise 0.
static func levels(state: BattleState, unit: UnitState) -> int:
	if unit == null or unit.ally_shield <= 0 or unit.health.is_defeated():
		return 0
	for other: UnitState in state.unit_states.values():
		if other != unit and other.faction == unit.faction and not other.health.is_defeated() and HexGrid.get_distance(other.hex, unit.hex) == 1:
			return unit.ally_shield
	return 0
