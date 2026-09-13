class_name AbilityExecutor
extends RefCounted


static func execute(
	state: BattleState,
	command: UseAbilityCommand
) -> AbilityExecutionResult:
	if state == null or command == null:
		return AbilityExecutionResult.rejected(
			"Ability command and BattleState are required."
		)

	var user := state.unit_states.get(command.user_id) as UnitState

	if user == null:
		return AbilityExecutionResult.rejected(
			"Ability user does not exist."
		)

	if user.unit_id != state.turn_service.get_active_unit_id():
		return AbilityExecutionResult.rejected(
			"Only the active unit can use an ability."
		)

	if user.health.is_defeated():
		return AbilityExecutionResult.rejected(
			"Defeated units cannot use abilities."
		)

	if not user.turn.main_action_available:
		return AbilityExecutionResult.rejected(
			"The unit has no main action available."
		)

	var ability := user.get_ability(command.ability_id)

	if ability == null:
		return AbilityExecutionResult.rejected(
			"Unit does not have ability %s." % command.ability_id
		)


	var target: UnitState

	if ability.area_radius > 0:
		if not command.targets_hex:
			return AbilityExecutionResult.rejected(
				"Area ability requires a target hex."
			)

		if not state.hex_grid.has_cell(command.target_hex):
			return AbilityExecutionResult.rejected(
				"Ability target hex does not exist."
			)

		if HexGrid.get_distance(user.hex, command.target_hex) > ability.range:
			return AbilityExecutionResult.rejected(
				"Ability target hex is out of range."
			)
	else:
		target = state.unit_states.get(command.target_id) as UnitState

		if target == null:
			return AbilityExecutionResult.rejected(
				"Ability target does not exist."
			)

		if target.health.is_defeated():
			return AbilityExecutionResult.rejected(
				"Defeated units cannot receive this ability."
			)

		if user.faction == target.faction:
			return AbilityExecutionResult.rejected(
				"This offensive ability requires an opposing target."
			)

		if HexGrid.get_distance(user.hex, target.hex) > ability.range:
			return AbilityExecutionResult.rejected(
				"Ability target is out of range."
			)

	for effect: AbilityEffectDefinition in ability.effects:
		var handler := state.mod_api.get_effect_handler(effect.effect_type_id)

		if handler == null:
			return AbilityExecutionResult.rejected(
				"No effect handler is registered for %s." % effect.effect_type_id
			)

		var error := handler.validate(effect)

		if not error.is_empty():
			return AbilityExecutionResult.rejected(error)

	if ability.ends_main_action and not user.turn.spend_main_action():
		return AbilityExecutionResult.rejected(
			"The ability action cost could not be paid."
		)

	var context := BattleEffectContext.new(state)

	if ability.area_radius > 0:
		return AbilityExecutionResult.success(
			_execute_area_ability(
				state,
				context,
				user,
				ability,
				command.target_hex
			)
		)

	var events: Array[BattleEvent] = [
		AbilityUsedEvent.new(user.unit_id, target.unit_id, ability.id),
	]

	for effect: AbilityEffectDefinition in ability.effects:
		var handler := state.mod_api.get_effect_handler(effect.effect_type_id)
		events.append_array(
			handler.execute(effect, context, user.unit_id, target.unit_id)
		)

	return AbilityExecutionResult.success(events)


static func _execute_area_ability(
	state: BattleState,
	context: BattleEffectContext,
	user: UnitState,
	ability: AbilityDefinition,
	target_hex: Vector2i
) -> Array[BattleEvent]:
	var affected_hexes := state.hex_grid.get_cells_in_range(
		target_hex,
		ability.area_radius
	)
	affected_hexes.sort()
	var target_ids: Array[StringName] = []

	for candidate: UnitState in state.unit_states.values():
		if candidate.health.is_defeated():
			continue

		if affected_hexes.has(candidate.hex):
			target_ids.append(candidate.unit_id)

	target_ids.sort()
	var events: Array[BattleEvent] = [
		AreaAbilityUsedEvent.new(
			user.unit_id,
			ability.id,
			target_hex,
			affected_hexes
		),
	]

	for target_id: StringName in target_ids:
		for effect: AbilityEffectDefinition in ability.effects:
			var handler := state.mod_api.get_effect_handler(
				effect.effect_type_id
			)
			events.append_array(
				handler.execute(
					effect,
					context,
					user.unit_id,
					target_id
				)
			)

	return events
