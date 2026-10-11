class_name SpearReturnService
extends RefCounted

static func resolve(state: BattleState, unit: UnitState, events: Array[BattleEvent]) -> void:
	if unit == null or unit.pending_spear_return.is_empty():
		return
	var pending := unit.pending_spear_return.duplicate()
	unit.pending_spear_return.clear()
	if unit.health.is_defeated():
		return
	var cells := AbilityExecutor.get_path_hexes(state.hex_grid, pending.hex, unit.hex)
	cells.erase(unit.hex)
	# Include the landing hex, but never damage the returning spear's owner.
	if state.hex_grid.has_cell(pending.hex) and pending.hex != unit.hex:
		cells.push_front(pending.hex)
	var returned := AreaAbilityUsedEvent.new(unit.unit_id, pending.ability_id, unit.hex, cells)
	returned.is_return = true
	returned.origin_hex = pending.hex
	events.append(returned)
	var ability := unit.get_ability(pending.ability_id)
	if ability == null:
		return
	var context := BattleEffectContext.new(state, pending.ability_id)
	context.target_hex = unit.hex
	var ids := state.unit_states.keys()
	ids.sort()
	for hex: Vector2i in cells:
		for id: StringName in ids:
			var target: UnitState = state.unit_states[id]
			if id != unit.unit_id and not target.health.is_defeated() and target.hex == hex:
				for effect: AbilityEffectDefinition in ability.effects:
					var handler := state.mod_api.get_effect_handler(effect.effect_type_id)
					events.append_array(handler.execute(effect, context, unit.unit_id, id))
