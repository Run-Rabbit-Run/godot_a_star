class_name HeldHexService
extends RefCounted
## Hexes that exist because a unit landed on them. When such a unit is defeated, its hex leaves
## the battlefield with everything on it: the bodies lying there and both hex layers.


## Removes the hexes of defeated holders; returns the reason when the map refused a removal.
static func collapse_defeated(state: BattleState, events: Array[BattleEvent]) -> String:
	var fallen := false
	for unit: UnitState in state.unit_states.values():
		if unit.holds_hex and unit.health.is_defeated():
			fallen = true
			break
	if not fallen:
		return ""
	var ids := state.unit_states.keys()
	ids.sort()
	for id: StringName in ids:
		var holder: UnitState = state.unit_states[id]
		if not holder.holds_hex or not holder.health.is_defeated():
			continue
		holder.holds_hex = false
		var hex := holder.hex
		if not state.hex_grid.has_cell(hex):
			continue
		for body_id: StringName in ids:
			var body: UnitState = state.unit_states[body_id]
			if body.hex == hex and body.health.is_defeated() and not body.corpse_removed:
				body.corpse_removed = true
				events.append(CorpseRemovedEvent.new(body_id, hex))
		var mutations: Array[MapMutation] = [MapMutation.remove_hex(hex)]
		var removal := MapMutationService.apply(state, mutations)
		if not removal.accepted:
			return removal.rejection_reason
		events.append_array(removal.events)
	return ""
