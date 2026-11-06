class_name BattleEngine
extends RefCounted


## Shield levels the defend command (EndTurnCommand) gives every unit.
const DEFEND_SHIELD_LEVELS := 1

var _state: BattleState
var _initial_resolution: BattleResolution
var _terminal_error := ""
## Prediction copies change only through commands, which advance the revisions,
## so a stored search stays valid while its revisions match the state.
var _caches_movement_searches := false
var _movement_searches: Dictionary[StringName, MovementSearchResult] = {}


func _init(p_state: BattleState, initialize := true) -> void:
	_state = p_state
	if not initialize:
		return
	_state.turn_service.start()
	# Auras of the starting units are part of the setup, like passives: they apply silently.
	var silent: Array[BattleEvent] = []
	HealthAuraService.refresh(_state, silent)
	var initial_events: Array[BattleEvent] = []
	# Starting terrain settles on a copy, so rules that never settle leave the map untouched.
	var settled := _state.hex_grid.duplicate_grid()
	HexStateService.settle(settled, initial_events)
	_terminal_error = HexStateService.propagate(settled, settled.get_cells(), initial_events, _state.spread_rule)
	if _terminal_error.is_empty():
		_state.hex_grid.replace_with(settled)
	else:
		initial_events.clear()
	if not initial_events.is_empty():
		_state.map_revision += 1

	if _terminal_error.is_empty() and get_outcome() == BattleOutcome.Value.IN_PROGRESS:
		# Every starting occupant is already touching its terrain; expose each once.
		for unit_id: StringName in _state.turn_service.get_turn_order():
			_apply_hex_state_damage(unit_id, initial_events)
		_settle_presence(initial_events)
		# Every unit has just touched its terrain, so the first phase does not expose it again.
		_start_phase(initial_events, true)
		if get_outcome() == BattleOutcome.Value.IN_PROGRESS and _terminal_error.is_empty():
			_settle_turns(initial_events)

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
	return fork_onto(_state.duplicate_for_prediction())


## The forecast engine over `state`, a detached copy the caller has just made of this battle's
## state with `duplicate_for_prediction()` and keeps using itself.
func fork_onto(state: BattleState) -> BattleEngine:
	var copy := BattleEngine.new(state, false)
	copy._terminal_error = _terminal_error
	copy._caches_movement_searches = true
	copy._movement_searches.assign(_movement_searches)
	return copy


func supports_ability_prediction(ability: AbilityDefinition) -> bool:
	var supported: Array[Script] = [DamageEffectHandler.new().get_script(), HexStateEffectHandler.new().get_script(), UnitStatusEffectHandler.new().get_script(), SummonEffectHandler.new().get_script(), PushEffectHandler.new().get_script()]
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
		or not _state.turn_service.can_command(attacker.unit_id)
		or not attacker.turn.main_action_available
	):
		return targets

	var shot_blocked := _shot_blocked(attacker)
	for candidate: UnitState in _state.unit_states.values():
		if candidate.faction == attacker.faction:
			continue

		if candidate.health.is_defeated():
			continue

		if BasicAttackRules.reaches(attacker.basic_attack_range, attacker.hex, candidate.hex, shot_blocked):
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


## Cells this unit's ability would affect from its current hex, by the geometry execution uses.
func get_ability_affected_hexes(unit_id: StringName, ability_id: StringName, center: Vector2i) -> Array[Vector2i]:
	var unit := get_unit(unit_id)
	var ability := unit.get_ability(ability_id) if unit != null else null
	if ability == null:
		var none: Array[Vector2i] = []
		return none
	return AbilityExecutor.get_affected_hexes(_state.hex_grid, unit.hex, ability, center)


## Obstacle hexes this unit may attack now; AttackObstacleCommand accepts exactly these.
func get_attackable_obstacle_hexes(unit_id: StringName) -> Array[Vector2i]:
	var hexes: Array[Vector2i] = []
	var attacker := get_unit(unit_id)
	if attacker == null or get_outcome() != BattleOutcome.Value.IN_PROGRESS:
		return hexes
	for hex: Vector2i in _state.hex_grid.get_cells_in_range(attacker.hex, attacker.basic_attack_range):
		if _state.hex_grid.has_obstacle(hex) and _obstacle_attack_error(attacker, hex).is_empty():
			hexes.append(hex)
	hexes.sort()
	return hexes


func get_deterministic_seed() -> int:
	return _state.deterministic_seed


func get_active_unit_id() -> StringName:
	return _state.turn_service.get_active_unit_id()


func get_round_number() -> int:
	return _state.turn_service.get_round_number()


func get_active_faction() -> BattleFaction.Value:
	return _state.turn_service.get_active_faction()


## The unit that started its turn and has not finished it, or "".
func get_current_unit_id() -> StringName:
	return _state.turn_service.get_current_unit_id()


## Units of the acting faction that may still act this phase, in field order.
func get_ready_unit_ids() -> Array[StringName]:
	return _state.turn_service.get_ready_unit_ids()


## True when the unit may give a command now: ready, and no other unit has started.
func can_command(unit_id: StringName) -> bool:
	return _state.turn_service.can_command(unit_id)


func get_turn_order() -> Array[StringName]:
	return _state.turn_service.get_turn_order()


func get_state_revision() -> int:
	return _state.state_revision


func get_map_revision() -> int:
	return _state.map_revision


func get_objective_description() -> String:
	return _state.objective_system.get_description()


func get_objective_target_ids() -> Array[StringName]:
	return _state.objective_system.get_target_unit_ids()


func get_protected_unit_ids() -> Array[StringName]:
	return _state.objective_system.get_protected_unit_ids()


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

	var result := BattleResult.new(
		get_battle_id(),
		get_deterministic_seed(),
		outcome,
		get_round_number(),
		objective_result
	)
	for unit: UnitState in _state.unit_states.values():
		if unit.is_summoned:
			continue
		result.participants[unit.faction] = result.participants.get(unit.faction, 0) + 1
		if unit.health.is_defeated():
			result.defeated[unit.faction] = result.defeated.get(unit.faction, 0) + 1
	return result


## [liquid, energy] of one hex, without copying the map.
func get_hex_layers(hex: Vector2i) -> Array[StringName]:
	var layers: Array[StringName] = [_state.hex_grid.get_liquid(hex), _state.hex_grid.get_energy(hex)]
	return layers


## A detached copy of the current map.
func get_hex_grid() -> HexGrid:
	return _state.hex_grid.duplicate_grid()


## Where a unit could stand in its next turn and which cells it could attack from there,
## while everyone else stays put. A paralyzed or defeated unit reaches nothing.
func get_reach(unit_id: StringName) -> Dictionary:
	var cells: Array[Vector2i] = []
	var attack_cells: Array[Vector2i] = []
	var unit := get_unit(unit_id)
	if unit != null and not unit.health.is_defeated() and unit.statuses.get(UnitStatusCatalog.PARALYSIS, 0) <= 0:
		var points := maxi(0, unit.turn.movement_max - UnitStatusCatalog.movement_penalty(unit.statuses))
		cells = MovementService.search(_state.hex_grid, unit.hex, points, _get_blocked_cells(unit_id)).get_reachable_cells()
		cells.sort()
		var attack: Dictionary[Vector2i, bool] = {}
		for cell: Vector2i in cells:
			# A sniper shoots only from where it stands; after a move it strikes its neighbors.
			var attack_range := 1 if unit.sniper_shot and cell != unit.hex else unit.basic_attack_range
			for target: Vector2i in _state.hex_grid.get_cells_in_range(cell, attack_range):
				if target != cell:
					attack[target] = true
		attack_cells.assign(attack.keys())
		attack_cells.sort()
	return {"move": cells, "attack": attack_cells}


func get_movement_search(unit_id: StringName) -> MovementSearchResult:
	var empty_costs: Dictionary[Vector2i, int] = {}
	var empty_came_from: Dictionary[Vector2i, Vector2i] = {}
	var state := get_unit(unit_id)

	if (
		state == null
		or state.health.is_defeated()
		or not _state.turn_service.can_command(unit_id)
	):
		return MovementSearchResult.new(
			empty_costs,
			empty_came_from,
			_state.map_revision,
			_state.state_revision
		)

	if _caches_movement_searches:
		var cached := _movement_searches.get(unit_id) as MovementSearchResult
		if cached != null and cached.map_revision == _state.map_revision and cached.state_revision == _state.state_revision:
			return cached

	var result := MovementService.search(
		_state.hex_grid,
		state.hex,
		state.turn.movement_remaining,
		_get_blocked_cells(unit_id),
		_state.map_revision,
		_state.state_revision
	)
	if _caches_movement_searches:
		_movement_searches[unit_id] = result
	return result


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

	_settle_presence(application.events)
	if _terminal_error.is_empty():
		_settle_turns(application.events)
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

	if command is AttackObstacleCommand:
		return _resolve_obstacle_attack(command as AttackObstacleCommand)

	if command is AttackCommand:
		return _resolve_attack(command as AttackCommand)

	if command is UseAbilityCommand:
		return _resolve_ability(command as UseAbilityCommand)

	if command is EndTurnCommand:
		return _resolve_end_turn(command as EndTurnCommand)

	if command is EndPhaseCommand:
		return _resolve_end_phase(command as EndPhaseCommand)

	if command is UseStrategistAbilityCommand:
		return _resolve_strategist(command as UseStrategistAbilityCommand)

	return _rejected("Unsupported battle command.")


func _resolve_move(command: MoveCommand) -> BattleResolution:
	var result := _execute_move(command)

	if not result.is_successful:
		return _rejected("Move command was rejected.")

	var moved_unit := get_unit(result.unit_id)
	_state.turn_service.begin_unit(result.unit_id)
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

		if not _state.hex_grid.has_layers(next_hex):
			continue

		events.append(UnitMovedEvent.new(result.unit_id, segment_path, segment_cost))
		segment_path = [next_hex]
		segment_cost = 0
		_apply_hex_state_damage(result.unit_id, events)

		if moved_unit.health.is_defeated() or moved_unit.statuses.get(UnitStatusCatalog.PARALYSIS, 0) > 0:
			break

	if segment_cost > 0:
		events.append(UnitMovedEvent.new(result.unit_id, segment_path, segment_cost))

	return _accepted(events)


func _resolve_attack(command: AttackCommand) -> BattleResolution:
	var events: Array[BattleEvent] = []
	var result := _execute_attack(command, events)
	if not result.is_successful:
		return _rejected("Attack command was rejected.")
	_settle_presence(events)
	if _terminal_error.is_empty():
		_finish_action_turn(command.attacker_id, events)
	return _accepted(events)


func _resolve_ability(command: UseAbilityCommand) -> BattleResolution:
	var result := AbilityExecutor.execute(_state, command)

	if not result.accepted:
		# Only a detached forecast changes in place; after a failed effect it is unusable.
		if result.state_changed:
			_terminal_error = result.rejection_reason
		return _rejected(result.rejection_reason)

	_settle_presence(result.events)
	if _terminal_error.is_empty():
		_finish_action_turn(command.user_id, result.events)
	return _accepted(result.events)


## The strategist acts beside the units: the started unit keeps its turn.
func _resolve_strategist(command: UseStrategistAbilityCommand) -> BattleResolution:
	var result := StrategistAbilityExecutor.execute(_state, command)
	if not result.accepted:
		if result.state_changed:
			_terminal_error = result.rejection_reason
		return _rejected(result.rejection_reason)
	return _accepted(result.events)


## Abilities of the player faction's strategist, sorted by ID.
func get_strategist_ability_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_state.strategist_abilities.keys())
	ids.sort()
	return ids


## Why the faction's strategist cannot use the ability now, or "".
func get_strategist_unavailable_reason(faction: BattleFaction.Value, ability_id: StringName) -> String:
	if not _terminal_error.is_empty() or get_outcome() != BattleOutcome.Value.IN_PROGRESS:
		return "Бой завершён."
	return StrategistAbilityExecutor.unavailable_reason(_state, faction, ability_id)


## Hexes UseStrategistAbilityCommand accepts now for the ability.
func get_strategist_target_hexes(faction: BattleFaction.Value, ability_id: StringName) -> Array[Vector2i]:
	if not get_strategist_unavailable_reason(faction, ability_id).is_empty():
		var none: Array[Vector2i] = []
		return none
	return StrategistAbilityExecutor.get_target_hexes(_state, faction, ability_id)


func _finish_action_turn(unit_id: StringName, events: Array[BattleEvent]) -> void:
	if get_outcome() != BattleOutcome.Value.IN_PROGRESS:
		return
	_finish_unit(unit_id, events)


## Defending ends the turn: the unit raises a shield that covers it until its side's next phase.
func _resolve_end_turn(command: EndTurnCommand) -> BattleResolution:
	if not _state.turn_service.can_command(command.unit_id):
		return _rejected("Only a ready unit can end its turn while no other unit has started.")

	var events: Array[BattleEvent] = []
	_finish_unit(command.unit_id, events, DEFEND_SHIELD_LEVELS)
	return _accepted(events)


func _resolve_end_phase(command: EndPhaseCommand) -> BattleResolution:
	if command.faction != get_active_faction():
		return _rejected("Only the acting faction can end its phase.")
	var events: Array[BattleEvent] = []
	# Remaining units end their turns with the phase end.
	for unit_id: StringName in _state.turn_service.get_ready_unit_ids():
		_state.turn_service.finish_unit(unit_id)
	return _accepted(events)


## Start of the acting faction's phase for every unit of it, in field order: reserves expire,
## turns restart, the hex acts, then the periodic statuses act and lose their levels.
## The battle's first phase has no handoff to announce and repeats no terrain exposure.
func _start_phase(events: Array[BattleEvent], first := false) -> void:
	if not first:
		events.append(PhaseStartedEvent.new(get_active_faction(), get_round_number()))
	# The side's shields fall before any start effect, so none of them meets a shield of this side.
	for unit_id: StringName in _state.turn_service.get_phase_unit_ids():
		UnitStatusService.expire_reserves(get_unit(unit_id), events)
	for unit_id: StringName in _state.turn_service.get_phase_unit_ids():
		var unit := get_unit(unit_id)
		unit.turn.start_turn()
		unit.start_cooldown_turn()
		unit.turn.movement_remaining = maxi(0, unit.turn.movement_remaining - UnitStatusCatalog.movement_penalty(unit.statuses))
		var return_error := SpearReturnService.resolve(_state, unit, events)
		if not return_error.is_empty():
			# A phase boundary has no alternative path: a failed return stops the battle.
			_terminal_error = return_error
			return
		if get_outcome() != BattleOutcome.Value.IN_PROGRESS:
			return
		if not first and not unit.health.is_defeated():
			_apply_hex_state_damage(unit_id, events)
		# The hex comes first, so what it gives acts in this phase; properties lose their level
		# only after it, so a resistance still meets the paralysis of the unit's own hex.
		UnitStatusService.start_phase(unit, events)
		# The turn starts where the start effects left the unit: alive, able to act, maybe engaged.
		AttackChargeService.grant(_state, unit, events)
		_settle_presence(events)
		if not _terminal_error.is_empty() or get_outcome() != BattleOutcome.Value.IN_PROGRESS:
			return


## The unit cannot act again this phase and ends its turn once. A defending unit raises
## `shield_levels` of shield that covers it until its side's next phase.
func _finish_unit(unit_id: StringName, events: Array[BattleEvent], shield_levels := 0) -> void:
	var unit := get_unit(unit_id)
	var paralyzed: bool = unit != null and unit.statuses.get(UnitStatusCatalog.PARALYSIS, 0) > 0
	var skipped := paralyzed and _state.turn_service.get_current_unit_id() != unit_id
	# A unit that could still act in this phase lost its turn to the paralysis; one that had
	# already finished (it acted, or was summoned) keeps the paralysis for its next phase.
	var lost_turn := paralyzed and not _state.turn_service.has_finished(unit_id)
	_state.turn_service.finish_unit(unit_id)
	if unit == null or _state.turn_service.has_ended(unit_id):
		return
	_state.turn_service.mark_ended(unit_id, lost_turn)
	UnitStatusService.apply(unit, UnitStatusCatalog.SHIELD, shield_levels, events)
	# An object has no turn to end.
	if not unit.takes_turns():
		return
	var ended := TurnEndedEvent.new(unit_id, get_round_number())
	ended.was_skipped = skipped
	events.append(ended)


## A started unit that died or got paralyzed ends its turn; a phase without ready units passes.
func _settle_turns(events: Array[BattleEvent]) -> void:
	if get_outcome() != BattleOutcome.Value.IN_PROGRESS:
		return
	var current := _state.turn_service.get_current_unit_id()
	if not current.is_empty() and not _state.turn_service.can_still_act(current):
		_finish_unit(current, events)
	# Each passed phase consumes paralysis or health, so chained empty phases are bounded.
	var attempts := 2
	for unit: UnitState in _state.unit_states.values():
		attempts += 2 * (unit.health.current + int(unit.statuses.get(UnitStatusCatalog.PARALYSIS, 0)))
	while get_outcome() == BattleOutcome.Value.IN_PROGRESS and _terminal_error.is_empty() and _state.turn_service.get_ready_unit_ids().is_empty():
		attempts -= 1
		if attempts < 0:
			_terminal_error = "The next phase could not be started."
			return
		_end_phase(events)


## Turns of the units that have not ended them, the turn statuses of the whole side, then the
## other faction's phase.
func _end_phase(events: Array[BattleEvent]) -> void:
	for unit_id: StringName in _state.turn_service.get_phase_unit_ids():
		if _state.turn_service.has_ended(unit_id):
			continue
		_finish_unit(unit_id, events)
	for unit_id: StringName in _state.turn_service.get_phase_unit_ids():
		UnitStatusService.end_phase(get_unit(unit_id), _state.turn_service.lost_turn_to_paralysis(unit_id), events)
	if _state.turn_service.advance_phase():
		HexStateService.end_round(_state, events)
		# A new round can decide the battle: a survived objective or the round limit.
		if get_outcome() != BattleOutcome.Value.IN_PROGRESS:
			return
	_start_phase(events)


func _apply_hex_state_damage(
	unit_id: StringName,
	events: Array[BattleEvent]
) -> void:
	HexStateService.expose(get_unit(unit_id), _state.hex_grid, events)


## Consequences of units that appeared or fell, right after the effects that caused them: the
## hexes of defeated holders leave the map, allied health auras follow their living sources.
func _settle_presence(events: Array[BattleEvent]) -> void:
	if not _terminal_error.is_empty():
		return
	# The removal changes the map only after the effects have landed: a refusal stops the battle.
	_terminal_error = HeldHexService.collapse_defeated(_state, events)
	if _terminal_error.is_empty():
		HealthAuraService.refresh(_state, events)


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

	if not _state.turn_service.can_command(attacker.unit_id):
		return AttackResult.failure()

	if attacker.unit_id == target.unit_id:
		return AttackResult.failure()

	if attacker.faction == target.faction:
		return AttackResult.failure()

	if attacker.health.is_defeated() or target.health.is_defeated():
		return AttackResult.failure()

	if not attacker.turn.main_action_available:
		return AttackResult.failure()

	if not BasicAttackRules.reaches(attacker.basic_attack_range, attacker.hex, target.hex, _shot_blocked(attacker)):
		return AttackResult.failure()

	if not BasicAttackRules.may_choose(attacker.basic_attack_damage_type, attacker.attack_damage_types, command.damage_type):
		return AttackResult.failure()

	if not attacker.turn.spend_main_action():
		return AttackResult.failure()

	# The chosen type stays the unit's attack type: a later retaliation strikes with it too.
	if not command.damage_type.is_empty():
		attacker.basic_attack_damage_type = command.damage_type
	var health_before := target.health.current
	# Only the liquid layer gives cover: steam.
	var protection_hex_state := _state.hex_grid.get_liquid(target.hex)
	var shot := BasicAttackRules.is_shot(attacker.basic_attack_range, attacker.hex, target.hex)
	var reduction := HexStateCatalog.ranged_reduction(protection_hex_state) if shot else 0
	var penalty := 0 if shot else BasicAttackRules.melee_penalty(attacker.basic_attack_range, attacker.basic_attack_damage)
	var first_event := events.size()
	var charge := AttackChargeService.spend(attacker, events)
	var hit := DamageRequest.new(attacker.basic_attack_damage, attacker.basic_attack_damage_type).from_unit(attacker.unit_id).with_bonus(charge, UnitStatusCatalog.ATTACK_CHARGE)
	UnitStatusService.damage(target, hit.with_cover(reduction, protection_hex_state).with_melee_penalty(penalty), events)
	if shot:
		_mark_ranged_hit(events, first_event)
	for status: StringName in attacker.basic_attack_statuses:
		UnitStatusService.apply(target, status, attacker.basic_attack_statuses[status], events)
	# The hit itself has landed: a reaction that cannot settle stops the battle.
	_terminal_error = DamageType.react(_state, target.hex, attacker.basic_attack_damage_type, events)
	var damage := health_before - target.health.current
	if not shot and _terminal_error.is_empty():
		_terminal_error = RetaliationService.respond(_state, attacker, target, events)
	return AttackResult.success(
		attacker.unit_id,
		target.unit_id,
		damage,
		target.health.current
	)


func _accepted(events: Array[BattleEvent]) -> BattleResolution:
	# After a terminal error no further rules run, not even passing the turn.
	_settle_presence(events)
	if _terminal_error.is_empty():
		_settle_turns(events)
	_state.state_revision += 1
	var resolution := BattleResolution.success(
		events,
		_state.state_revision,
		get_active_unit_id(),
		get_result()
	)

	resolution.terminal_error = _terminal_error
	return resolution

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


func _resolve_obstacle_attack(command: AttackObstacleCommand) -> BattleResolution:
	var attacker := get_unit(command.attacker_id)
	var error := _obstacle_attack_error(attacker, command.target_hex)
	if not error.is_empty():
		return _rejected(error)
	attacker.turn.spend_main_action()
	var events: Array[BattleEvent] = []
	var damage := attacker.basic_attack_damage
	if not BasicAttackRules.is_shot(attacker.basic_attack_range, attacker.hex, command.target_hex):
		damage -= BasicAttackRules.melee_penalty(attacker.basic_attack_range, damage)
	# An attack on an obstacle is the unit's own ordinary attack too: it spends the charge.
	damage += AttackChargeService.spend(attacker, events)
	# The strike has landed: a flask burst the map refuses stops the battle, as after a hit.
	_terminal_error = ObstacleService.damage(_state, command.target_hex, damage, events)
	# A burst may kill: its consequences come before the attacker's turn ends.
	_settle_presence(events)
	if _terminal_error.is_empty():
		_finish_action_turn(attacker.unit_id, events)
	return _accepted(events)


## Why this unit cannot attack the obstacle at the hex now, or "".
func _obstacle_attack_error(attacker: UnitState, hex: Vector2i) -> String:
	var obstacle := _state.hex_grid.get_obstacle(hex)
	if attacker == null or obstacle == null or not obstacle.destructible:
		return "Уничтожаемое препятствие не найдено."
	if not _state.turn_service.can_command(attacker.unit_id) or attacker.health.is_defeated() or not attacker.turn.main_action_available:
		return "Атака препятствия недоступна."
	if HexGrid.get_distance(attacker.hex, hex) > attacker.basic_attack_range:
		return "Препятствие вне дальности атаки."
	if not BasicAttackRules.reaches(attacker.basic_attack_range, attacker.hex, hex, _is_engaged(attacker)):
		return "Рядом враг: стрелять нельзя."
	if not BasicAttackRules.reaches(attacker.basic_attack_range, attacker.hex, hex, _shot_blocked(attacker)):
		return "Снайперский выстрел невозможен после перемещения."
	return ""


## True when the unit cannot shoot now and only strikes its neighbors: an opponent stands next
## to it, or it is a sniper that has spent movement points this turn.
func _shot_blocked(unit: UnitState) -> bool:
	return BasicAttackRules.sniper_moved(unit.sniper_shot, unit.turn.movement_spent) or _is_engaged(unit)


## True when a living opponent stands next to the unit, so it cannot shoot.
func _is_engaged(unit: UnitState) -> bool:
	var opponent_hexes: Array[Vector2i] = []
	for other: UnitState in _state.unit_states.values():
		if other.faction != unit.faction and not other.health.is_defeated():
			opponent_hexes.append(other.hex)
	return BasicAttackRules.is_engaged(unit.hex, opponent_hexes)


## The hit's own damage event comes first; explosions it triggers follow it.
static func _mark_ranged_hit(events: Array[BattleEvent], from_index: int) -> void:
	for index in range(from_index, events.size()):
		if events[index] is UnitDamagedEvent:
			events[index].ranged_attack = true
			return
