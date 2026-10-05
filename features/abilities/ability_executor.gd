class_name AbilityExecutor
extends RefCounted

static func get_target_hexes(state: BattleState, unit_id: StringName, ability_id: StringName) -> Array[Vector2i]:
	var targets: Array[Vector2i] = []
	var user := state.unit_states.get(unit_id) as UnitState
	if user == null or user.health.is_defeated() or unit_id != state.turn_service.get_active_unit_id() or not user.turn.main_action_available:
		return targets
	var ability := user.get_ability(ability_id)
	if ability == null or user.ability_cooldowns.get(ability_id, 0) > 0:
		return targets
	if not ability.targets_hex():
		for target: UnitState in state.unit_states.values():
			if not target.health.is_defeated() and target.faction != user.faction and HexGrid.get_distance(user.hex, target.hex) <= ability.get_range(user):
				targets.append(target.hex)
	else:
		for hex: Vector2i in state.hex_grid.get_cells_in_range(user.hex, ability.get_range(user)):
			if ability.target_mode == AbilityDefinition.TargetMode.EMPTY_HEX:
				if not state.hex_grid.is_traversable(hex) or _occupied(state, hex):
					continue
			if ability.target_mode == AbilityDefinition.TargetMode.LINE and get_line_direction(user.hex, hex) == Vector2i.ZERO:
				continue
			targets.append(hex)
	targets.sort()
	return targets

static func get_line_direction(origin: Vector2i, target: Vector2i) -> Vector2i:
	var delta := target - origin
	for direction: Vector2i in HexGrid.DIRECTIONS:
		var distance := HexGrid.get_distance(origin, target)
		if distance > 0 and direction * distance == delta:
			return direction
	return Vector2i.ZERO

static func get_affected_hexes(grid: HexGrid, origin: Vector2i, ability: AbilityDefinition, center: Vector2i) -> Array[Vector2i]:
	if ability.target_mode != AbilityDefinition.TargetMode.LINE:
		var area := grid.get_cells_in_range(center, ability.area_radius)
		area.sort()
		return area
	var cells: Array[Vector2i] = []
	var direction := get_line_direction(origin, center)
	if direction == Vector2i.ZERO:
		return cells
	# Holes and impassable cells do not stop a piercing beam.
	for hex: Vector2i in grid.get_cells():
		if get_line_direction(origin, hex) == direction:
			cells.append(hex)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return HexGrid.get_distance(origin, a) < HexGrid.get_distance(origin, b))
	return cells

static func execute(state: BattleState, command: UseAbilityCommand) -> AbilityExecutionResult:
	if state == null or command == null:
		return AbilityExecutionResult.rejected("Ability command and state are required.")
	var user := state.unit_states.get(command.user_id) as UnitState
	if user == null:
		return AbilityExecutionResult.rejected("Ability user does not exist.")
	var ability := user.get_ability(command.ability_id)
	if ability == null:
		return AbilityExecutionResult.rejected("Unit does not have this ability.")
	var error := ability.validate()
	if not error.is_empty():
		return AbilityExecutionResult.rejected(error)
	if command.targets_hex != ability.targets_hex():
		return AbilityExecutionResult.rejected("Incorrect ability target kind.")
	var center := command.target_hex
	if not command.targets_hex:
		var target := state.unit_states.get(command.target_id) as UnitState
		if target == null or target.health.is_defeated() or target.faction == user.faction:
			return AbilityExecutionResult.rejected("Ability requires a living opposing target.")
		center = target.hex
	if not get_target_hexes(state, user.unit_id, ability.id).has(center):
		return AbilityExecutionResult.rejected("Ability target unavailable or ability on cooldown.")
	for effect: AbilityEffectDefinition in ability.effects:
		if effect == null:
			return AbilityExecutionResult.rejected("Null ability effect.")
		var handler := state.mod_api.get_effect_handler(effect.effect_type_id)
		if handler == null:
			return AbilityExecutionResult.rejected("Missing ability effect handler.")
		error = handler.validate(effect)
		if not error.is_empty():
			return AbilityExecutionResult.rejected(error)
	if not user.turn.spend_main_action():
		return AbilityExecutionResult.rejected("Main action unavailable.")
	user.ability_cooldowns[ability.id] = ability.cooldown_turns + 1
	var cells := get_affected_hexes(state.hex_grid, user.hex, ability, center)
	var target_ids: Array[StringName] = []
	for target: UnitState in state.unit_states.values():
		if not target.health.is_defeated() and cells.has(target.hex):
			target_ids.append(target.unit_id)
	target_ids.sort()
	var events: Array[BattleEvent] = []
	if ability.targets_hex() or ability.area_radius > 0:
		events.append(AreaAbilityUsedEvent.new(user.unit_id, ability.id, center, cells))
	else:
		events.append(AbilityUsedEvent.new(user.unit_id, command.target_id, ability.id))
	var context := BattleEffectContext.new(state, ability.id)
	context.target_hex = center
	for effect: AbilityEffectDefinition in ability.effects:
		var handler := state.mod_api.get_effect_handler(effect.effect_type_id)
		if handler.affects_hexes():
			var effect_cells: Array[Vector2i] = []
			if effect.parameters.get("center_only", false):
				effect_cells.append(center)
			else:
				effect_cells.assign(cells)
			if effect.effect_type_id == &"core:hex_state":
				var mutations: Array[MapMutation] = []
				for hex: Vector2i in effect_cells:
					mutations.append(MapMutation.apply_hex_state(hex, StringName(effect.parameters["state_id"])))
				events.append_array(MapMutationService.apply(state, mutations).events)
				continue
			for hex: Vector2i in effect_cells:
				events.append_array(handler.execute_hex(effect, context, user.unit_id, hex))
		else:
			for target_id: StringName in target_ids:
				events.append_array(handler.execute(effect, context, user.unit_id, target_id))
	return AbilityExecutionResult.success(events)

static func _occupied(state: BattleState, hex: Vector2i) -> bool:
	for unit: UnitState in state.unit_states.values():
		if unit.hex == hex and not unit.health.is_defeated():
			return true
	return false
