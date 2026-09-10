class_name BattleController
extends Node


signal battle_finished(result: BattleResult)


@onready var _terrain_layer: TileMapLayer = %TerrainLayer
@onready var _units: Node2D = %Units
@onready var _map_view: BattleMapView = get_parent() as BattleMapView
@onready var _hud: BattleHUD = %BattleUI
@onready var _input_router: BattleInputRouter = %BattleInputRouter

var _hex_grid: HexGrid
var _battle_engine: BattleEngine
var _start_request: BattleStartRequest
var _is_initialization_requested := false
var _movement_search_result: MovementSearchResult
var _attackable_target_hexes: Array[Vector2i] = []
var _is_presenting := false
var _unit_states: Dictionary[StringName, UnitState] = {}
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

	var definition := _start_request.battle_definition
	_hex_grid = BattleMapAssembler.build_hex_grid(_terrain_layer)
	var validation := BattleDefinitionValidator.validate(
		definition,
		_hex_grid
	)

	if not validation.is_valid:
		push_error(
			"Battle initialization failed: %s" % validation.error_message
		)
		return

	_input_router.setup(_hex_grid)

	## Порядок spawn-определений задаёт начальный порядок ходов.
	var turn_order: Array[StringName] = []

	for spawn: BattleUnitSpawnDefinition in definition.unit_spawns:
		var state := _create_unit_from_spawn(spawn)

		if state != null:
			turn_order.append(state.unit_id)

	var primary_objective := BattleObjectiveFactory.create(
		definition.primary_objective
	)

	if primary_objective == null:
		push_error("BattleObjective could not be created.")
		return
	var objective_system := ObjectiveSystem.new(
		primary_objective,
		definition.protected_faction
	)
	_battle_engine = BattleEngine.new(
		_hex_grid,
		_unit_states,
		turn_order,
		objective_system,
		definition.id,
		_start_request.deterministic_seed
	)
	_hud.end_turn_requested.connect(_on_end_turn_requested)
	_input_router.hex_selected.connect(_on_hex_selected)
	_input_router.hex_hovered.connect(_on_hex_hovered)
	_input_router.hex_hover_exited.connect(_on_hex_hover_exited)
	_hud.clear_action()
	_hud.show_objective(_battle_engine.get_objective_description())

	var active_state := _battle_engine.get_unit(
		_battle_engine.get_active_unit_id()
	)

	if active_state != null:
		_show_unit_movement(active_state)


func _create_unit_from_spawn(
	spawn: BattleUnitSpawnDefinition
) -> UnitState:
	if spawn == null:
		push_error("BattleUnitSpawnDefinition must not be null.")
		return null

	return _create_unit(
		spawn.unit_id,
		spawn.unit_definition,
		spawn.faction,
		spawn.hex
	)


func _create_unit(	unit_id: StringName,
	definition: UnitDefinition,
	faction: BattleFaction.Value,
	hex: Vector2i
) -> UnitState:
	if definition == null:
		push_error("UnitDefinition is not assigned to BattleController.")
		return null

	if definition.id.is_empty():
		push_error("UnitDefinition id must not be empty.")
		return null

	if definition.actor_scene == null:
		push_error("UnitDefinition actor_scene is not assigned.")
		return null

	if definition.base_stats == null:
		push_error("UnitDefinition base_stats is not assigned.")
		return null

	if not _hex_grid.has_cell(hex):
		push_warning("Unit spawn hex does not exist in the battle grid.")
		return null

	if _unit_states.has(unit_id):
		push_warning("Unit spawn id is already registered.")
		return null

	for existing_state: UnitState in _unit_states.values():
		if existing_state.hex == hex:
			push_warning("Unit spawn hex is already occupied.")
			return null

	var actor_node := definition.actor_scene.instantiate()
	var actor := actor_node as UnitActor

	if actor == null:
		actor_node.free()
		push_error("UnitDefinition actor_scene root must be a UnitActor.")
		return null

	var base_stats := definition.base_stats
	var turn := TurnState.new(base_stats.movement_points)
	var health := HealthState.new(base_stats.max_health)
	var state := UnitState.new(
		unit_id,
		definition.id,
		faction,
		hex,
		turn,
		health,
		base_stats.basic_attack_damage
	)
	_units.add_child(actor)
	actor.setup(state.unit_id, definition)
	actor.global_position = _map_view.hex_to_global_position(state.hex)

	_unit_states[state.unit_id] = state
	_unit_actors[state.unit_id] = actor
	_unit_definitions[state.unit_id] = definition

	return state


## Контроллер превращает ввод в команду; допустимость решает BattleEngine.
func _on_hex_selected(axial_cell: Vector2i) -> void:
	if _is_presenting:
		return

	var active_unit_id := _battle_engine.get_active_unit_id()

	if active_unit_id.is_empty():
		return

	var state := _battle_engine.get_unit(active_unit_id)

	if state == null:
		push_error("Active unit state is not registered.")
		return

	if state.faction != BattleFaction.Value.PLAYER:
		return

	var target_state := _battle_engine.get_unit_at(axial_cell)

	if target_state != null and target_state.unit_id != active_unit_id:
		var attack_command := AttackCommand.new(
			active_unit_id,
			target_state.unit_id
		)
		var attack_result := _battle_engine.execute_attack(
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
	var move_result := _battle_engine.execute_move(command)

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
		_battle_engine != null
		and _battle_engine.get_unit_at(axial_cell) != null
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
	if _battle_engine == null:
		_hud.clear_target()
		return

	var target := _battle_engine.get_unit_at(axial_cell)
	var active := _battle_engine.get_unit(
		_battle_engine.get_active_unit_id()
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
	if _is_presenting:
		return

	_set_presenting(true)

	var next_unit_id := _battle_engine.end_turn()

	if next_unit_id.is_empty():
		push_error("The next unit turn could not be started.")
		_set_presenting(false)
		return

	var next_state := _battle_engine.get_unit(next_unit_id)

	if next_state == null:
		push_error("The next active unit is not registered.")
		_set_presenting(false)
		return

	if next_state.faction == BattleFaction.Value.PLAYER:
		_show_unit_movement(next_state)
		_set_presenting(false)
		return

	if next_state.faction != BattleFaction.Value.ENEMY:
		push_error("The next active unit has an unsupported faction.")
		_set_presenting(false)
		return

	_show_unit_movement(next_state)
	await _run_enemy_turn(next_state)

func _run_enemy_turn(enemy_state: UnitState) -> void:
	if (
		enemy_state == null
		or enemy_state.faction != BattleFaction.Value.ENEMY
	):
		push_error("Enemy turn requires a valid enemy UnitState.")
		_set_presenting(false)
		return

	var player_candidates := _battle_engine.get_living_units_by_faction(
		BattleFaction.Value.PLAYER
	)
	var player_state := EnemyBrain.choose_target(
		enemy_state.hex,
		player_candidates
	)

	if player_state == null:
		push_error("No living player target is available for the enemy.")
		await _advance_after_enemy_turn()
		return

	var opening_attack_result := _execute_enemy_attack(
		enemy_state,
		player_state
	)

	if opening_attack_result.is_successful:
		await _present_attack(opening_attack_result)

		if _finish_battle_if_needed():
			return

		await _advance_after_enemy_turn()
		return

	var movement_search := _battle_engine.get_movement_search(
		enemy_state.unit_id
	)
	var command := EnemyBrain.choose_move(
		enemy_state.unit_id,
		enemy_state.hex,
		player_state.hex,
		movement_search
	)

	if command != null:
		var move_result := _battle_engine.execute_move(command)

		if move_result.is_successful:
			await _present_move(move_result)

	var closing_attack_result := _execute_enemy_attack(
		enemy_state,
		player_state
	)

	if closing_attack_result.is_successful:
		await _present_attack(closing_attack_result)

		if _finish_battle_if_needed():
			return

	await _advance_after_enemy_turn()


func _execute_enemy_attack(
	enemy_state: UnitState,
	player_state: UnitState
) -> AttackResult:
	var command := EnemyBrain.choose_attack(
		enemy_state.unit_id,
		enemy_state.hex,
		player_state.unit_id,
		player_state.hex,
		enemy_state.turn.main_action_available
	)

	if command == null:
		return AttackResult.failure()

	return _battle_engine.execute_attack(command)


func _advance_after_enemy_turn() -> void:
	var next_unit_id := _battle_engine.end_turn()

	if next_unit_id.is_empty():
		push_error("The next turn could not be started after the enemy turn.")
		_set_presenting(false)
		return

	var next_state := _battle_engine.get_unit(next_unit_id)

	if next_state == null:
		push_error("The next active unit is not registered in the battle.")
		_set_presenting(false)
		return

	if next_state.faction == BattleFaction.Value.PLAYER:
		_show_unit_movement(next_state)
		_set_presenting(false)
		return

	if next_state.faction == BattleFaction.Value.ENEMY:
		_show_unit_movement(next_state)
		await _run_enemy_turn(next_state)
		return

	push_error("The next active unit belongs to an unsupported faction.")
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
	var result := _battle_engine.get_result()

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

	if state == null or state.faction != BattleFaction.Value.PLAYER:
		_map_view.show_targetable_cells(_attackable_target_hexes)
		return

	var targets := _battle_engine.get_attackable_targets(state.unit_id)

	for target: UnitState in targets:
		_attackable_target_hexes.append(target.hex)

	_map_view.show_targetable_cells(_attackable_target_hexes)


## Один сохранённый поиск питает область движения и preview маршрута.
func _show_unit_movement(state: UnitState) -> void:
	_map_view.clear_path()

	_movement_search_result = _battle_engine.get_movement_search(
		state.unit_id
	)
	_map_view.show_selected_hex(state.hex)
	_map_view.show_reachable_cells(
		_movement_search_result.get_reachable_cells()
	)
	_refresh_attack_targets(state)
	_hud.show_round(_battle_engine.get_round_number())
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
