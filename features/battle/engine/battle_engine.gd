class_name BattleEngine
extends RefCounted


var _state: BattleState
var _initial_resolution: BattleResolution
var _terminal_error := ""


func _init(p_state: BattleState, initialize := true) -> void:
	_state = p_state
	if not initialize:
		return
	_state.turn_service.start()
	var initial_events: Array[BattleEvent] = []
	HexStateService.propagate(_state.hex_grid, _state.hex_grid.get_cells(), initial_events)
	if not initial_events.is_empty():
		_state.map_revision += 1

	if get_outcome() == BattleOutcome.Value.IN_PROGRESS:
		# Every starting occupant is already touching its terrain; expose each once.
		var initial_ids := _state.unit_states.keys()
		initial_ids.sort()
		for unit_id: StringName in initial_ids:
			_apply_hex_state_damage(unit_id, initial_events)
		_start_unit_turn(get_active_unit_id())

		_advance_defeated_active(initial_events, true)

	if not initial_events.is_empty():
		_state.state_revision += 1

	# Captured once so a later request cannot mix start events with the current state.
	_initial_resolution = BattleResolution.success(
		initial_events,
		get_state_revision(),
		get_active_unit_id(),
		get_result()
	)
	# A turn order that cannot start must stop the graphical adapter before the first input.
	_initial_resolution.terminal_error = _terminal_error


func get_initial_resolution() -> BattleResolution:
	return _initial_resolution


## A forecast never reapplies startup exposure, resets turns or consumes the live RNG.
func fork_for_prediction() -> BattleEngine:
	var copy := BattleEngine.new(_state.duplicate_for_prediction(), false)
	copy._terminal_error = _terminal_error
	return copy


func supports_ability_prediction(ability: AbilityDefinition) -> bool:
	var supported: Array[Script] = [DamageEffectHandler.new().get_script(), HexStateEffectHandler.new().get_script(), UnitStatusEffectHandler.new().get_script(), SummonEffectHandler.new().get_script()]
	for effect: AbilityEffectDefinition in ability.effects:
		var handler := _state.mod_api.get_effect_handler(effect.effect_type_id)
		if handler == null or not supported.has(handler.get_script()):
			return false
	return true


func get_unit(unit_id: StringName) -> UnitState:
	return _state.unit_states.get(unit_id) as UnitState


func get_unit_at(hex: Vector2i) -> UnitState:
	for state: UnitState in _state.unit_states.values():
		if state.health.is_defeated():
			continue

		if state.hex == hex:
			return state

	return null


func get_living_units_by_faction(
	faction: BattleFaction.Value
) -> Array[UnitState]:
	var living_units: Array[UnitState] = []

	for state: UnitState in _state.unit_states.values():
		if state.faction == faction and not state.health.is_defeated():
			living_units.append(state)

	living_units.sort_custom(_is_unit_id_before)
	return living_units


func get_attackable_targets(unit_id: StringName) -> Array[UnitState]:
	var targets: Array[UnitState] = []
	var attacker := get_unit(unit_id)

	if (
		attacker == null
		or attacker.health.is_defeated()
		or attacker.unit_id != get_active_unit_id()
		or not attacker.turn.main_action_available
	):
		return targets

	for candidate: UnitState in _state.unit_states.values():
		if candidate.faction == attacker.faction:
			continue

		if candidate.health.is_defeated():
			continue

		if (
			HexGrid.get_distance(attacker.hex, candidate.hex)
			<= attacker.basic_attack_range
		):
			targets.append(candidate)

	targets.sort_custom(_is_unit_id_before)
	return targets


func get_battle_id() -> StringName:
	return _state.battle_id


func get_ability_target_hexes(
	unit_id: StringName,
	ability_id: StringName
) -> Array[Vector2i]:
	if get_outcome() != BattleOutcome.Value.IN_PROGRESS:
		var no_targets: Array[Vector2i] = []
		return no_targets

	return AbilityExecutor.get_target_hexes(_state, unit_id, ability_id)


func get_deterministic_seed() -> int:
	return _state.deterministic_seed


func get_active_unit_id() -> StringName:
	return _state.turn_service.get_active_unit_id()


func get_round_number() -> int:
	return _state.turn_service.get_round_number()


func get_turn_order() -> Array[StringName]:
	return _state.turn_service.get_turn_order()


func get_state_revision() -> int:
	return _state.state_revision


func get_map_revision() -> int:
	return _state.map_revision


func get_objective_description() -> String:
	return _state.objective_system.get_description()


func get_outcome() -> BattleOutcome.Value:
	return _state.objective_system.get_outcome(
		_state.unit_states,
		get_round_number()
	)


func get_result() -> BattleResult:
	var outcome := get_outcome()

	if outcome == BattleOutcome.Value.IN_PROGRESS:
		return null

	var objective_result := ObjectiveResult.new(
		get_objective_description(),
		outcome == BattleOutcome.Value.VICTORY
	)

	return BattleResult.new(
		get_battle_id(),
		get_deterministic_seed(),
		outcome,
		get_round_number(),
		objective_result
	)


func get_movement_search(unit_id: StringName) -> MovementSearchResult:
	var empty_costs: Dictionary[Vector2i, int] = {}
	var empty_came_from: Dictionary[Vector2i, Vector2i] = {}
	var state := get_unit(unit_id)

	if (
		state == null
		or state.health.is_defeated()
		or unit_id != get_active_unit_id()
	):
		return MovementSearchResult.new(
			empty_costs,
			empty_came_from,
			_state.map_revision,
			_state.state_revision
		)

	return MovementService.search(
		_state.hex_grid,
		state.hex,
		state.turn.movement_remaining,
		_get_blocked_cells(unit_id),
		_state.map_revision,
		_state.state_revision
	)


func apply_map_mutations(
	mutations: Array[MapMutation]
) -> BattleResolution:
	if not _terminal_error.is_empty():
		return _rejected(_terminal_error)
	if get_outcome() != BattleOutcome.Value.IN_PROGRESS:
		return _rejected("Battle is already finished.")

	var application := MapMutationService.apply(_state, mutations)

	if not application.accepted:
		return _rejected(application.rejection_reason)

	_advance_defeated_active(application.events)
	var resolution := BattleResolution.success(
		application.events,
		_state.state_revision,
		get_active_unit_id(),
		get_result()
	)
	resolution.terminal_error = _terminal_error
	return resolution


func execute(command: BattleCommand) -> BattleResolution:
	if not _terminal_error.is_empty():
		return _rejected(_terminal_error)
	if command == null:
		return _rejected("Command must not be null.")

	if get_outcome() != BattleOutcome.Value.IN_PROGRESS:
		return _rejected("Battle is already finished.")

	if command is MoveCommand:
		return _resolve_move(command as MoveCommand)

	if command is AttackCommand:
		return _resolve_attack(command as AttackCommand)

	if command is UseAbilityCommand:
		return _resolve_ability(command as UseAbilityCommand)

	if command is EndTurnCommand:
		return _resolve_end_turn(command as EndTurnCommand)

	return _rejected("Unsupported battle command.")


func _resolve_move(command: MoveCommand) -> BattleResolution:
	var result := _execute_move(command)

	if not result.is_successful:
		return _rejected("Move command was rejected.")

	var moved_unit := get_unit(result.unit_id)
	var events: Array[BattleEvent] = []
	var segment_path: Array[Vector2i] = [moved_unit.hex]
	var segment_cost := 0

	for path_index in range(1, result.path.size()):
		var next_hex := result.path[path_index]
		var step_cost := _state.hex_grid.get_movement_cost(next_hex)
		# A newly acquired slowing effect can shorten a previously reachable route.
		if not moved_unit.turn.spend_movement(step_cost):
			break
		moved_unit.hex = next_hex
		segment_path.append(next_hex)
		segment_cost += step_cost

		var state_id := _state.hex_grid.get_hex_state_id(next_hex)

		if state_id.is_empty():
			continue

		events.append(UnitMovedEvent.new(result.unit_id, segment_path, segment_cost))
		segment_path = [next_hex]
		segment_cost = 0
		_apply_hex_state_damage(result.unit_id, events)

		if moved_unit.health.is_defeated() or moved_unit.statuses.get(&"core:paralysis", 0) > 0:
			break

	if segment_cost > 0:
		events.append(UnitMovedEvent.new(result.unit_id, segment_path, segment_cost))

	return _accepted(events)


func _resolve_attack(command: AttackCommand) -> BattleResolution:
	var events: Array[BattleEvent] = []
	var result := _execute_attack(command, events)
	if not result.is_successful:
		return _rejected("Attack command was rejected.")
	_finish_action_turn(command.attacker_id, events)
	return _accepted(events)


func _resolve_ability(command: UseAbilityCommand) -> BattleResolution:
	var result := AbilityExecutor.execute(_state, command)

	if not result.accepted:
		return _rejected(result.rejection_reason)

	_finish_action_turn(command.user_id, result.events)
	return _accepted(result.events)


func _finish_action_turn(_unit_id: StringName, events: Array[BattleEvent]) -> void:
	if get_outcome() != BattleOutcome.Value.IN_PROGRESS:
		return
	var next_id := _end_turn(events)
	if next_id.is_empty() and get_outcome() == BattleOutcome.Value.IN_PROGRESS:
		_terminal_error = "The next unit turn could not be started."


func _resolve_end_turn(command: EndTurnCommand) -> BattleResolution:
	if command.unit_id != get_active_unit_id():
		return _rejected("Only the active unit can end its turn.")

	var events: Array[BattleEvent] = []
	var next_unit_id := _end_turn(events)

	if next_unit_id.is_empty() and get_outcome() == BattleOutcome.Value.IN_PROGRESS:
		_terminal_error = "The next unit turn could not be started."

	return _accepted(events)


func _start_unit_turn(unit_id: StringName) -> bool:
	var state := get_unit(unit_id)

	if state == null or state.health.is_defeated():
		return false

	state.turn.start_turn()
	state.start_cooldown_turn()
	state.turn.movement_remaining = maxi(0, state.turn.movement_remaining - UnitStatusCatalog.movement_penalty(state.statuses))
	return true


func _end_turn(damage_events: Array[BattleEvent], initial_skip := false) -> StringName:
	if get_outcome() != BattleOutcome.Value.IN_PROGRESS:
		return StringName()

	var previous_unit_id := get_active_unit_id()
	var was_skipped := initial_skip
	UnitStatusService.end_turn(get_unit(get_active_unit_id()), damage_events)
	if get_outcome() != BattleOutcome.Value.IN_PROGRESS:
		var ended := TurnEndedEvent.new(previous_unit_id, &"", get_round_number())
		ended.was_skipped = was_skipped
		damage_events.append(ended)
		return StringName()
	# Each skipped turn consumes paralysis or health; this bound covers chained skips.
	var attempts := _state.turn_service.get_participant_count()
	for unit: UnitState in _state.unit_states.values():
		attempts += unit.health.current + int(unit.statuses.get(&"core:paralysis", 0))
	attempts *= _state.turn_service.get_participant_count()
	for _attempt in range(attempts):
		var previous_round := get_round_number()
		var next_unit_id := _state.turn_service.advance_turn()
		if get_round_number() != previous_round:
			HexStateService.end_round(_state, damage_events)

		if not _start_unit_turn(next_unit_id):
			continue

		# Finish the old turn after its status effects, before the new hex exposure.
		var ended := TurnEndedEvent.new(previous_unit_id, next_unit_id, get_round_number())
		ended.was_skipped = was_skipped
		damage_events.append(ended)
		previous_unit_id = next_unit_id
		was_skipped = false
		_apply_hex_state_damage(next_unit_id, damage_events)

		if get_outcome() != BattleOutcome.Value.IN_PROGRESS:
			return StringName()

		var next := get_unit(next_unit_id)
		if next.health.is_defeated():
			continue
		if next.statuses.get(&"core:paralysis", 0) > 0:
			was_skipped = true
			UnitStatusService.end_turn(next, damage_events)
			if get_outcome() != BattleOutcome.Value.IN_PROGRESS:
				var skipped := TurnEndedEvent.new(next_unit_id, &"", get_round_number())
				skipped.was_skipped = true
				damage_events.append(skipped)
				return StringName()
			continue
		return next_unit_id

	return StringName()


func _apply_hex_state_damage(
	unit_id: StringName,
	events: Array[BattleEvent]
) -> void:
	HexStateService.expose(get_unit(unit_id), _state.hex_grid, events)


func _execute_move(command: MoveCommand) -> MoveResult:
	var state := get_unit(command.unit_id)

	if state == null or state.health.is_defeated():
		return MoveResult.failure()

	if command.destination == state.hex:
		return MoveResult.failure()

	var search_result := get_movement_search(command.unit_id)
	var movement_cost := search_result.get_cost(command.destination)

	if movement_cost < 0:
		return MoveResult.failure()

	var path := search_result.build_path(command.destination)

	return MoveResult.success(
		command.unit_id,
		path,
		movement_cost
	)


func _execute_attack(command: AttackCommand, events: Array[BattleEvent]) -> AttackResult:
	var attacker := get_unit(command.attacker_id)
	var target := get_unit(command.target_id)

	if attacker == null or target == null:
		return AttackResult.failure()

	if attacker.unit_id != get_active_unit_id():
		return AttackResult.failure()

	if attacker.unit_id == target.unit_id:
		return AttackResult.failure()

	if attacker.faction == target.faction:
		return AttackResult.failure()

	if attacker.health.is_defeated() or target.health.is_defeated():
		return AttackResult.failure()

	if not attacker.turn.main_action_available:
		return AttackResult.failure()

	if (
		HexGrid.get_distance(attacker.hex, target.hex)
		> attacker.basic_attack_range
	):
		return AttackResult.failure()

	if not attacker.turn.spend_main_action():
		return AttackResult.failure()

	var health_before := target.health.current
	var protection_hex_state := _state.hex_grid.get_hex_state_id(target.hex)
	var reduction := HexStateCatalog.ranged_reduction(protection_hex_state) if attacker.basic_attack_range > 1 else 0
	UnitStatusService.damage(target, attacker.basic_attack_damage, attacker.basic_attack_damage_type, events, attacker.unit_id, &"", &"", reduction, &"", protection_hex_state)
	for status: StringName in attacker.basic_attack_statuses:
		UnitStatusService.apply(target, status, attacker.basic_attack_statuses[status], events)
	events.append_array(DamageType.react(_state, target.hex, attacker.basic_attack_damage_type))
	var damage := health_before - target.health.current
	return AttackResult.success(
		attacker.unit_id,
		target.unit_id,
		damage,
		target.health.current
	)


func _accepted(events: Array[BattleEvent]) -> BattleResolution:
	_advance_defeated_active(events)
	_state.state_revision += 1
	var resolution := BattleResolution.success(
		events,
		_state.state_revision,
		get_active_unit_id(),
		get_result()
	)

	resolution.terminal_error = _terminal_error
	return resolution

func _advance_defeated_active(events: Array[BattleEvent], initial_turn := false) -> void:
	var active := get_unit(get_active_unit_id())

	if active == null or (not active.health.is_defeated() and active.statuses.get(&"core:paralysis", 0) <= 0):
		return

	if get_outcome() != BattleOutcome.Value.IN_PROGRESS:
		return

	var next_unit_id := _end_turn(events, initial_turn and active.statuses.get(&"core:paralysis", 0) > 0)
	if next_unit_id.is_empty() and get_outcome() == BattleOutcome.Value.IN_PROGRESS:
		_terminal_error = "The next unit turn could not be started."


func _rejected(reason: String) -> BattleResolution:
	return BattleResolution.rejected(
		reason,
		_state.state_revision,
		get_active_unit_id(),
		get_result()
	)


func _is_unit_id_before(
	left: UnitState,
	right: UnitState
) -> bool:
	return String(left.unit_id) < String(right.unit_id)


func _get_blocked_cells(
	excluded_unit_id: StringName
) -> Dictionary[Vector2i, bool]:
	var blocked_cells: Dictionary[Vector2i, bool] = {}

	for unit_id: StringName in _state.unit_states:
		if unit_id == excluded_unit_id:
			continue

		var state: UnitState = _state.unit_states[unit_id]

		if state.health.is_defeated():
			continue

		blocked_cells[state.hex] = true

	return blocked_cells
