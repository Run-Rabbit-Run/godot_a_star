class_name BattleController
extends Node


signal battle_finished(result: BattleResult)


const MAX_AUTOMATIC_STEPS_PER_HANDOFF := 128


@onready var _units: Node2D = %Units
@onready var _map_view: BattleMapView = get_parent() as BattleMapView
@onready var _hud: BattleHUD = %BattleUI
@onready var _input_router: BattleInputRouter = %BattleInputRouter

var _hex_grid: HexGrid
var _battle_session: BattleSession
var _battle_setup: BattleSetup
var _start_request: BattleStartRequest
var _is_initialization_requested := false
var _movement_search_result: MovementSearchResult
var _attackable_target_hexes: Array[Vector2i] = []
var _is_presenting := false
var _unit_actors: Dictionary[StringName, UnitActor] = {}
var _unit_definitions: Dictionary[StringName, UnitDefinition] = {}


func setup(request: BattleStartRequest) -> bool:
	var validation := BattleStartRequestValidator.validate(request)

	if not validation.is_valid:
		push_error("Battle setup failed: %s" % validation.error_message)
		return false

	if _is_initialization_requested:
		push_error("BattleController setup can only be called once.")
		return false

	_start_request = request
	_is_initialization_requested = true
	call_deferred("_initialize_battle")

	return true


func _initialize_battle() -> void:
	if _start_request == null:
		push_error("BattleController requires setup before initialization.")
		return

	var session_result := BattleSessionFactory.create(_start_request)

	if not session_result.is_successful:
		push_error(
			"Battle initialization failed: %s" % session_result.error_message
		)
		return

	_battle_session = session_result.session
	_battle_setup = _battle_session.setup
	_hex_grid = _battle_session.get_hex_grid()
	_input_router.setup(_hex_grid)

	if not _create_unit_actors(_battle_setup.unit_spawns):
		_clear_created_units()
		return

	_hud.end_turn_requested.connect(_on_end_turn_requested)
	_input_router.hex_selected.connect(_on_hex_selected)
	_input_router.hex_hovered.connect(_on_hex_hovered)
	_input_router.hex_hover_exited.connect(_on_hex_hover_exited)
	_hud.clear_action()
	_hud.show_objective(_battle_session.get_objective_description())

	var active_state := _battle_session.get_unit(
		_battle_session.get_active_unit_id()
	)

	if active_state != null:
		_show_unit_movement(active_state)

		if _battle_session.is_active_unit_ai_controlled():
			_set_presenting(true)
			await _run_ai_turns()


func _create_unit_actors(spawns: Array[UnitSpawnData]) -> bool:
	for spawn: UnitSpawnData in spawns:
		var state := _battle_session.get_unit(spawn.unit_id)

		if state == null:
			push_error("Unit state is missing: %s." % spawn.unit_id)
			return false

		var actor := UnitActorFactory.create(
			state,
			spawn.unit_definition,
			_units
		)

		if actor == null:
			push_error("Unit actor could not be created: %s." % spawn.unit_id)
			return false

		actor.global_position = _map_view.hex_to_global_position(state.hex)
		_unit_actors[state.unit_id] = actor
		_unit_definitions[state.unit_id] = spawn.unit_definition

	return true


func _clear_created_units() -> void:
	for actor: UnitActor in _unit_actors.values():
		actor.queue_free()

	_unit_actors.clear()
	_unit_definitions.clear()


## Контроллер превращает ввод в команду; допустимость решает BattleEngine.
func _on_hex_selected(axial_cell: Vector2i) -> void:
	if _is_presenting:
		return

	var active_unit_id := _battle_session.get_active_unit_id()

	if active_unit_id.is_empty():
		return

	var state := _battle_session.get_unit(active_unit_id)

	if state == null:
		push_error("Active unit state is not registered.")
		return

	if _battle_session.is_unit_ai_controlled(state.unit_id):
		return

	var target_state := _battle_session.get_unit_at(axial_cell)

	if target_state != null and target_state.unit_id != active_unit_id:
		var attack_command := AttackCommand.new(
			active_unit_id,
			target_state.unit_id
		)
		var attack_result := _battle_session.execute_attack(
			attack_command
		)

		if attack_result.is_successful:
			_set_presenting(true)
			await _present_attack(attack_result)

			if _finish_battle_if_needed():
				return

			_set_presenting(false)
			_show_unit_movement(state)

		return

	var command := MoveCommand.new(active_unit_id, axial_cell)
	var move_result := _battle_session.execute_move(command)

	if not move_result.is_successful:
		return

	_set_presenting(true)
	var was_presented := await _present_move(move_result)
	_set_presenting(false)

	if not was_presented:
		return

	_show_unit_movement(state)


func _on_hex_hovered(axial_cell: Vector2i) -> void:
	_show_hovered_target(axial_cell)

	if (
		_battle_session != null
		and _battle_session.get_unit_at(axial_cell) != null
	):
		_map_view.clear_path()
		return

	if _movement_search_result == null:
		_map_view.clear_path()
		return

	_map_view.show_path(
		_movement_search_result.build_path(axial_cell)
	)


func _show_hovered_target(axial_cell: Vector2i) -> void:
	if _battle_session == null:
		_hud.clear_target()
		return

	var target := _battle_session.get_unit_at(axial_cell)
	var active := _battle_session.get_unit(
		_battle_session.get_active_unit_id()
	)

	if (
		target == null
		or active == null
		or target.faction == active.faction
	):
		_hud.clear_target()
		return

	_hud.show_target(
		"%s [%s]" % [
			_get_unit_display_name(target.unit_id),
			target.unit_id,
		],
		target.health.current,
		target.health.maximum
	)


func _on_hex_hover_exited() -> void:
	_map_view.clear_path()
	_hud.clear_target()


func _on_end_turn_requested() -> void:
	if _is_presenting or _battle_session.is_active_unit_ai_controlled():
		return

	_set_presenting(true)
	var active_unit_id := _battle_session.get_active_unit_id()
	var next_unit_id := _battle_session.end_turn_for(active_unit_id)

	if next_unit_id.is_empty():
		if not _finish_battle_if_needed():
			push_error("The next unit turn could not be started.")
			_set_presenting(false)
		return

	await _continue_turn_cycle()


func _continue_turn_cycle() -> void:
	var active_unit_id := _battle_session.get_active_unit_id()
	var active := _battle_session.get_unit(active_unit_id)

	if active == null:
		push_error("The next active unit is not registered.")
		_set_presenting(false)
		return

	_show_unit_movement(active)

	if _battle_session.is_active_unit_ai_controlled():
		await _run_ai_turns()
		return

	_set_presenting(false)


func _run_ai_turns() -> void:
	var automatic_steps := 0

	while (
		not _battle_session.is_finished()
		and _battle_session.is_active_unit_ai_controlled()
	):
		if automatic_steps >= MAX_AUTOMATIC_STEPS_PER_HANDOFF:
			push_error("Automatic turn step limit was reached.")
			_set_presenting(false)
			return

		var active_unit_id := _battle_session.get_active_unit_id()
		var active := _battle_session.get_unit(active_unit_id)

		if active == null:
			push_error("AI-controlled active unit is not registered.")
			_set_presenting(false)
			return

		_show_unit_movement(active)
		var command := _battle_session.get_next_ai_command()

		if command == null:
			push_error("AI command source did not provide a command.")
			_set_presenting(false)
			return

		if command is MoveCommand:
			var move_result := _battle_session.execute_move(
				command as MoveCommand
			)

			if not move_result.is_successful:
				push_error("AI move command was rejected.")
				_set_presenting(false)
				return

			await _present_move(move_result)
		elif command is AttackCommand:
			var attack_result := _battle_session.execute_attack(
				command as AttackCommand
			)

			if not attack_result.is_successful:
				push_error("AI attack command was rejected.")
				_set_presenting(false)
				return

			await _present_attack(attack_result)
		elif command is EndTurnCommand:
			var end_turn := command as EndTurnCommand
			var next_unit_id := _battle_session.end_turn_for(end_turn.unit_id)

			if next_unit_id.is_empty():
				if _finish_battle_if_needed():
					return

				push_error("The next turn could not be started after an AI turn.")
				_set_presenting(false)
				return
		else:
			push_error("AI command source returned an unsupported command.")
			_set_presenting(false)
			return

		automatic_steps += 1

		if _finish_battle_if_needed():
			return

	var active := _battle_session.get_unit(
		_battle_session.get_active_unit_id()
	)

	if active != null:
		_show_unit_movement(active)

	_set_presenting(false)


func _get_unit_display_name(unit_id: StringName) -> String:
	var definition := _unit_definitions.get(unit_id) as UnitDefinition

	if definition == null:
		push_warning("UnitDefinition is not registered for presentation.")
		return String(unit_id)

	return definition.display_name


func _present_attack(result: AttackResult) -> bool:
	if result == null or not result.is_successful:
		return false

	var target_actor := _unit_actors.get(result.target_id) as UnitActor

	if target_actor == null:
		push_error("UnitActor is not registered for the attacked unit.")
		return false

	_hud.show_attack(
		_get_unit_display_name(result.attacker_id),
		_get_unit_display_name(result.target_id),
		result.damage,
		result.target_health_remaining
	)
	await target_actor.present_damage()

	if result.is_target_defeated():
		_present_defeat(result.target_id)

	return true


func _present_defeat(unit_id: StringName) -> void:
	var actor := _unit_actors.get(unit_id) as UnitActor

	if actor == null:
		push_error("UnitActor is not registered for the defeated unit.")
		return

	actor.present_defeat()


func _present_move(move_result: MoveResult) -> bool:
	if move_result == null or not move_result.is_successful:
		return false

	var actor := _unit_actors.get(move_result.unit_id) as UnitActor

	if actor == null:
		push_error("UnitActor is not registered for the moved unit.")
		return false

	_map_view.clear_path()

	var empty_cells: Array[Vector2i] = []
	_map_view.show_reachable_cells(empty_cells)

	var global_positions: Array[Vector2] = []

	for path_index in range(1, move_result.path.size()):
		global_positions.append(
			_map_view.hex_to_global_position(
				move_result.path[path_index]
			)
		)

	await actor.move_along_global_positions(global_positions)

	return true


func _set_presenting(is_presenting: bool) -> void:
	_is_presenting = is_presenting
	_input_router.set_interaction_enabled(not is_presenting)
	_hud.set_interaction_enabled(not is_presenting)

	if is_presenting:
		_attackable_target_hexes.clear()
		_map_view.show_targetable_cells(_attackable_target_hexes)
		_hud.clear_target()


func _finish_battle_if_needed() -> bool:
	var result := _battle_session.get_result()

	if result == null:
		return false

	_movement_search_result = null
	_map_view.clear_overlays()
	_hud.show_outcome(result.outcome)
	_set_presenting(true)
	battle_finished.emit(result)

	return true


## Контроллер преобразует доменные цели в axial-клетки слоя представления.
func _refresh_attack_targets(state: UnitState) -> void:
	_attackable_target_hexes.clear()

	if state == null or _battle_session.is_unit_ai_controlled(state.unit_id):
		_map_view.show_targetable_cells(_attackable_target_hexes)
		return

	var targets := _battle_session.get_attackable_targets(state.unit_id)

	for target: UnitState in targets:
		_attackable_target_hexes.append(target.hex)

	_map_view.show_targetable_cells(_attackable_target_hexes)


## Один сохранённый поиск питает область движения и preview маршрута.
func _show_unit_movement(state: UnitState) -> void:
	_map_view.clear_path()

	_movement_search_result = _battle_session.get_movement_search(
		state.unit_id
	)
	_map_view.show_selected_hex(state.hex)
	_map_view.show_reachable_cells(
		_movement_search_result.get_reachable_cells()
	)
	_refresh_attack_targets(state)
	_hud.show_round(_battle_session.get_round_number())
	_hud.show_health(
		state.health.current,
		state.health.maximum
	)
	_hud.show_movement(
		state.turn.movement_remaining,
		state.turn.movement_max
	)
	_hud.show_main_action(state.turn.main_action_available)

	var definition := _unit_definitions.get(state.unit_id) as UnitDefinition

	if definition == null:
		push_error("Active unit definition is not registered.")
		return

	_hud.show_active_unit(
		"%s [%s]" % [definition.display_name, state.unit_id]
	)
