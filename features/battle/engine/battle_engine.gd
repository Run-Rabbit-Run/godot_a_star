class_name BattleEngine
extends RefCounted


var _state: BattleState


func _init(p_state: BattleState) -> void:
	_state = p_state
	_state.turn_service.start()


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
	if get_outcome() != BattleOutcome.Value.IN_PROGRESS:
		return _rejected("Battle is already finished.")

	var application := MapMutationService.apply(_state, mutations)

	if not application.accepted:
		return _rejected(application.rejection_reason)

	return BattleResolution.success(
		application.events,
		_state.state_revision,
		get_active_unit_id(),
		get_result()
	)


func execute(command: BattleCommand) -> BattleResolution:
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
		# The entire route was validated before entering it, so every step can be paid.
		moved_unit.turn.spend_movement(step_cost)
		moved_unit.hex = next_hex
		segment_path.append(next_hex)
		segment_cost += step_cost

		var state_id := _state.hex_grid.get_hex_state_id(next_hex)

		if HexStateCatalog.get_damage(state_id) <= 0:
			continue

		events.append(UnitMovedEvent.new(result.unit_id, segment_path, segment_cost))
		segment_path = [next_hex]
		segment_cost = 0
		_apply_hex_state_damage(result.unit_id, events)

		if moved_unit.health.is_defeated():
			break

	if segment_cost > 0:
		events.append(UnitMovedEvent.new(result.unit_id, segment_path, segment_cost))

	if moved_unit.health.is_defeated() and get_outcome() == BattleOutcome.Value.IN_PROGRESS:
		var turn_damage_events: Array[BattleEvent] = []
		var next_unit_id := _end_turn(turn_damage_events)
		events.append(TurnEndedEvent.new(
			result.unit_id,
			next_unit_id,
			get_round_number()
		))
		events.append_array(turn_damage_events)

	return _accepted(events)


func _resolve_attack(command: AttackCommand) -> BattleResolution:
	var result := _execute_attack(command)

	if not result.is_successful:
		return _rejected("Attack command was rejected.")

	var events: Array[BattleEvent] = [
		UnitDamagedEvent.new(
			result.attacker_id,
			result.target_id,
			result.damage,
			result.target_health_remaining,
			result.is_target_defeated()
		),
	]
	return _accepted(events)


func _resolve_ability(command: UseAbilityCommand) -> BattleResolution:
	var result := AbilityExecutor.execute(_state, command)

	if not result.accepted:
		return _rejected(result.rejection_reason)

	return _accepted(result.events)


func _resolve_end_turn(command: EndTurnCommand) -> BattleResolution:
	if command.unit_id != get_active_unit_id():
		return _rejected("Only the active unit can end its turn.")

	var previous_unit_id := command.unit_id
	var turn_damage_events: Array[BattleEvent] = []
	var next_unit_id := _end_turn(turn_damage_events)

	if next_unit_id.is_empty() and get_outcome() == BattleOutcome.Value.IN_PROGRESS:
		return _rejected("The next unit turn could not be started.")

	var events: Array[BattleEvent] = [
		TurnEndedEvent.new(
			previous_unit_id,
			next_unit_id,
			get_round_number()
		),
	]
	events.append_array(turn_damage_events)
	return _accepted(events)


func _start_unit_turn(unit_id: StringName) -> bool:
	var state := get_unit(unit_id)

	if state == null or state.health.is_defeated():
		return false

	state.turn.start_turn()
	return true


func _end_turn(damage_events: Array[BattleEvent]) -> StringName:
	if get_outcome() != BattleOutcome.Value.IN_PROGRESS:
		return StringName()

	for _attempt in range(_state.turn_service.get_participant_count()):
		var next_unit_id := _state.turn_service.advance_turn()

		if not _start_unit_turn(next_unit_id):
			continue

		_apply_hex_state_damage(next_unit_id, damage_events)

		if get_outcome() != BattleOutcome.Value.IN_PROGRESS:
			return StringName()

		if not get_unit(next_unit_id).health.is_defeated():
			return next_unit_id

	return StringName()


func _apply_hex_state_damage(
	unit_id: StringName,
	events: Array[BattleEvent]
) -> void:
	var unit := get_unit(unit_id)

	if unit == null or unit.health.is_defeated():
		return

	var state_id := _state.hex_grid.get_hex_state_id(unit.hex)
	var damage := HexStateCatalog.get_damage(state_id)

	if damage <= 0:
		return

	var applied_damage := unit.health.apply_damage(damage)
	events.append(UnitDamagedEvent.new(
		StringName(),
		unit_id,
		applied_damage,
		unit.health.current,
		unit.health.is_defeated(),
		state_id
	))


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


func _execute_attack(command: AttackCommand) -> AttackResult:
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

	var damage := target.health.apply_damage(
		attacker.basic_attack_damage
	)
	return AttackResult.success(
		attacker.unit_id,
		target.unit_id,
		damage,
		target.health.current
	)


func _accepted(events: Array[BattleEvent]) -> BattleResolution:
	_state.state_revision += 1
	return BattleResolution.success(
		events,
		_state.state_revision,
		get_active_unit_id(),
		get_result()
	)


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
