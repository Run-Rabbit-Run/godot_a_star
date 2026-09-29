class_name AbilityExecutor
extends RefCounted


static func get_target_hexes(
	state: BattleState, unit_id: StringName, ability_id: StringName
) -> Array[Vector2i]:
	var targets: Array[Vector2i] = []
	var user := state.unit_states.get(unit_id) as UnitState
	if user == null or user.health.is_defeated():
		return targets
	if unit_id != state.turn_service.get_active_unit_id() or not user.turn.main_action_available:
		return targets
	var ability := user.get_ability(ability_id)
	if ability == null:
		return targets
	if ability.area_radius > 0:
		targets = state.hex_grid.get_cells_in_range(user.hex, ability.range)
	else:
		for target: UnitState in state.unit_states.values():
			if target.health.is_defeated() or target.faction == user.faction:
				continue
			if HexGrid.get_distance(user.hex, target.hex) <= ability.range:
				targets.append(target.hex)
	targets.sort()
	return targets


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
			return AbilityExecutionResult.rejected("Area ability requires a target hex.")
	else:
		if command.targets_hex:
			return AbilityExecutionResult.rejected("Single-target ability requires a unit target.")
		target = state.unit_states.get(command.target_id) as UnitState
		if target == null:
			return AbilityExecutionResult.rejected("Ability target does not exist.")
		if target.health.is_defeated() or target.faction == user.faction:
			return AbilityExecutionResult.rejected("Ability requires a living opposing target.")

	var target_hex := command.target_hex if command.targets_hex else target.hex
	if not get_target_hexes(state, user.unit_id, ability.id).has(target_hex):
		return AbilityExecutionResult.rejected("Ability target is not available.")

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

	var context := BattleEffectContext.new(state, ability.id)

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
