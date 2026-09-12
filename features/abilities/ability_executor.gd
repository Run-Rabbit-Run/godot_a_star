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
	var target := state.unit_states.get(command.target_id) as UnitState

	if user == null or target == null:
		return AbilityExecutionResult.rejected(
			"Ability user or target does not exist."
		)

	if user.unit_id != state.turn_service.get_active_unit_id():
		return AbilityExecutionResult.rejected(
			"Only the active unit can use an ability."
		)

	if user.health.is_defeated() or target.health.is_defeated():
		return AbilityExecutionResult.rejected(
			"Defeated units cannot use or receive this ability."
		)

	if user.faction == target.faction:
		return AbilityExecutionResult.rejected(
			"This offensive ability requires an opposing target."
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

	var events: Array[BattleEvent] = [
		AbilityUsedEvent.new(user.unit_id, target.unit_id, ability.id),
	]
	var context := BattleEffectContext.new(state)

	for effect: AbilityEffectDefinition in ability.effects:
		var handler := state.mod_api.get_effect_handler(effect.effect_type_id)
		events.append_array(
			handler.execute(effect, context, user.unit_id, target.unit_id)
		)

	return AbilityExecutionResult.success(events)