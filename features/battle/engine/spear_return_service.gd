class_name SpearReturnService
extends RefCounted

## Returns the reason when the return's effects failed; their changes are then discarded.
static func resolve(state: BattleState, unit: UnitState, events: Array[BattleEvent]) -> String:
	if unit == null or unit.pending_spear_return.is_empty():
		return ""
	var pending := unit.pending_spear_return.duplicate()
	unit.pending_spear_return.clear()
	if unit.health.is_defeated():
		return ""
	var cells := AbilityExecutor.get_path_hexes(state.hex_grid, pending.hex, unit.hex)
	cells.erase(unit.hex)
	# Include the landing hex, but never damage the returning spear's owner.
	if state.hex_grid.has_cell(pending.hex) and pending.hex != unit.hex:
		cells.push_front(pending.hex)
	var returned := AreaAbilityUsedEvent.new(unit.unit_id, pending.ability_id, unit.hex, cells)
	returned.is_return = true
	returned.origin_hex = pending.hex
	var ability := unit.get_ability(pending.ability_id)
	if ability == null:
		events.append(returned)
		return ""
	# Occupants are struck in path order, starting at the landing hex, while still alive.
	var target_ids: Array[StringName] = []
	var ids := state.unit_states.keys()
	ids.sort()
	for hex: Vector2i in cells:
		for id: StringName in ids:
			var target: UnitState = state.unit_states[id]
			if id != unit.unit_id and not target.health.is_defeated() and target.hex == hex:
				target_ids.append(id)
	# The same effect pipeline as ability use, on a copy adopted only after success.
	var scratch := state if state.is_detached else state.duplicate_for_prediction()
	var context := BattleEffectContext.new(scratch, pending.ability_id)
	context.target_hex = unit.hex
	var produced := AbilityEffectPipeline.apply(context, scratch, ability, unit.unit_id, cells, target_ids, true)
	if context.has_failed():
		return context.get_failure()
	if scratch != state:
		state.adopt(scratch)
	events.append(returned)
	events.append_array(produced)
	return ""
