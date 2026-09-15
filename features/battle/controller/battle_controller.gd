class_name BattleController
extends Node


signal battle_finished(result: BattleResult)


const MAX_AUTOMATIC_STEPS_PER_HANDOFF := 128
const GRENADE_ABILITY_ID := &"core:grenade"


@onready var _units: Node2D = %Units
@onready var _map_view: BattleMapView = get_parent() as BattleMapView
@onready var _hud: BattleHUD = %BattleUI
@onready var _input_router: BattleInputRouter = %BattleInputRouter
@onready var _presentation_queue: BattlePresentationQueue = %PresentationQueue

var _hex_grid: HexGrid
var _known_map_revision := -1
var _battle_session: BattleSession
var _battle_setup: BattleSetup
var _start_request: BattleStartRequest
var _is_initialization_requested := false
var _movement_search_result: MovementSearchResult
var _attackable_target_hexes: Array[Vector2i] = []
var _ability_target_hexes: Array[Vector2i] = []
var _selected_ability_id := StringName()
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


func set_playback_speed(speed: float) -> bool:
	return _presentation_queue.set_speed(speed)


func apply_map_mutations(
	mutations: Array[MapMutation]
) -> BattleResolution:
	if _battle_session == null:
		return BattleResolution.rejected(
			"Battle session is not initialized.",
			0,
			StringName()
		)

	_set_presenting(true)
	var resolution := _battle_session.apply_map_mutations(mutations)

	if not resolution.accepted:
		_set_presenting(false)
		return resolution

	await _presentation_queue.present(
		resolution,
		_unit_actors,
		_unit_definitions,
		_map_view,
		_hud
	)
	_refresh_map_revision()
	_set_presenting(false)
	return resolution


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
	_known_map_revision = _battle_session.get_map_revision()
	_map_view.render_grid(_hex_grid)
	_input_router.setup(_hex_grid)

	if not _create_unit_actors(_battle_setup.unit_spawns):
		_clear_created_units()
		return

	_hud.end_turn_requested.connect(_on_end_turn_requested)
	_hud.movement_requested.connect(_on_movement_requested)
	_hud.basic_attack_requested.connect(_on_basic_attack_requested)
	_hud.ability_requested.connect(_on_ability_requested)
	_hud.playback_speed_requested.connect(_on_playback_speed_requested)
	_input_router.hex_selected.connect(_on_hex_selected)
	_input_router.hex_hovered.connect(_on_hex_hovered)
	_input_router.hex_hover_exited.connect(_on_hex_hover_exited)
	_hud.clear_action()
	_hud.show_objective(_battle_session.get_objective_description())

	var active := _battle_session.get_unit(
		_battle_session.get_active_unit_id()
	)

	if active != null:
		_show_unit_movement(active)

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


func _on_hex_selected(axial_cell: Vector2i) -> void:
	if _is_presenting:
		return

	var active_unit_id := _battle_session.get_active_unit_id()

	if active_unit_id.is_empty():
		return

	var active := _battle_session.get_unit(active_unit_id)

	if active == null:
		push_error("Active unit snapshot is not registered.")
		return

	if _battle_session.is_unit_ai_controlled(active.unit_id):
		return

	var command: BattleCommand

	if not _selected_ability_id.is_empty():
		if not _ability_target_hexes.has(axial_cell):
			return

		command = UseAbilityCommand.at_hex(
			active_unit_id,
			axial_cell,
			_selected_ability_id
		)
	else:
		var target := _battle_session.get_unit_at(axial_cell)

		if target != null and target.unit_id != active_unit_id:
			command = AttackCommand.new(active_unit_id, target.unit_id)
		else:
			command = MoveCommand.new(active_unit_id, axial_cell)

	var resolution := _battle_session.step(command)

	if not resolution.accepted:
		return

	_set_presenting(true)
	var was_presented := await _presentation_queue.present(
		resolution,
		_unit_actors,
		_unit_definitions,
		_map_view,
		_hud
	)

	if _finish_battle_if_needed(resolution):
		return

	_set_presenting(false)

	if not was_presented:
		return

	active = _battle_session.get_unit(active_unit_id)

	if active != null:
		_show_unit_movement(active)


func _on_hex_hovered(axial_cell: Vector2i) -> void:
	if not _selected_ability_id.is_empty():
		_map_view.clear_path()

		if not _ability_target_hexes.has(axial_cell):
			_map_view.clear_ability_area()
			_hud.clear_target()
			return

		var active := _battle_session.get_unit(
			_battle_session.get_active_unit_id()
		)
		var radius: int = active.ability_area_radii.get(
			_selected_ability_id,
			0
		)
		var area := _hex_grid.get_cells_in_range(axial_cell, radius)
		_map_view.show_ability_area(area)
		_hud.show_area_target(area.size())
		return

	_show_hovered_target(axial_cell)

	if (
		_battle_session != null
		and _battle_session.get_unit_at(axial_cell) != null
	):
		_map_view.clear_path()
		return

	if (
		_movement_search_result == null
		or _movement_search_result.map_revision != _known_map_revision
	):
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

	if target == null:
		_hud.clear_target()
		return

	var definition := _unit_definitions.get(target.unit_id) as UnitDefinition
	_hud.show_target(
		_get_unit_display_name(target.unit_id),
		definition.actor_texture if definition != null else null,
		"Союзник" if target.faction == BattleFaction.Value.PLAYER else "Противник",
		target.health.current,
		target.health.maximum,
		target.basic_attack_damage,
		target.basic_attack_range,
		target.turn.movement_remaining,
		target.turn.movement_max,
		target.turn.main_action_available
	)


func _on_hex_hover_exited() -> void:
	_map_view.clear_path()
	_map_view.clear_ability_area()
	_hud.clear_target()


func _on_ability_requested(ability_id: StringName) -> void:
	if _is_presenting or _battle_session == null:
		return

	var active := _battle_session.get_unit(
		_battle_session.get_active_unit_id()
	)

	if (
		active == null
		or _battle_session.is_unit_ai_controlled(active.unit_id)
		or not active.turn.main_action_available
		or not active.ability_ids.has(ability_id)
		or active.ability_area_radii.get(ability_id, 0) <= 0
	):
		return

	_selected_ability_id = ability_id
	_ability_target_hexes = _hex_grid.get_cells_in_range(
		active.hex,
		active.ability_ranges.get(ability_id, 0)
	)
	var empty_cells: Array[Vector2i] = []
	_map_view.show_reachable_cells(empty_cells)
	_map_view.show_targetable_cells(_ability_target_hexes)
	_map_view.clear_ability_area()
	_hud.show_ability_targeting(
		"Граната",
		1 + 3 * active.ability_area_radii[ability_id]
			* (active.ability_area_radii[ability_id] + 1)
	)


func _on_movement_requested() -> void:
	if _is_presenting or _battle_session == null:
		return

	var active := _battle_session.get_unit(
		_battle_session.get_active_unit_id()
	)

	if (
		active == null
		or _battle_session.is_unit_ai_controlled(active.unit_id)
	):
		return

	_show_unit_movement(active)


func _on_basic_attack_requested() -> void:
	if _is_presenting or _battle_session == null:
		return

	var active := _battle_session.get_unit(
		_battle_session.get_active_unit_id()
	)

	if (
		active == null
		or _battle_session.is_unit_ai_controlled(active.unit_id)
		or not active.turn.main_action_available
	):
		return

	_show_unit_movement(active)


func _on_playback_speed_requested(speed: float) -> void:
	if not set_playback_speed(speed):
		push_warning("Requested playback speed is outside allowed range.")


func _on_end_turn_requested() -> void:
	if _is_presenting or _battle_session.is_active_unit_ai_controlled():
		return

	_set_presenting(true)
	var active_unit_id := _battle_session.get_active_unit_id()
	var resolution := _battle_session.step(
		EndTurnCommand.new(active_unit_id)
	)

	if not resolution.accepted:
		if not _finish_battle_if_needed(resolution):
			push_error(resolution.rejection_reason)
			_set_presenting(false)
		return

	await _presentation_queue.present(
		resolution,
		_unit_actors,
		_unit_definitions,
		_map_view,
		_hud
	)
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

		var active := _battle_session.get_unit(
			_battle_session.get_active_unit_id()
		)

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

		var resolution := _battle_session.step(command)

		if not resolution.accepted:
			push_error("AI command was rejected: %s" % resolution.rejection_reason)
			_set_presenting(false)
			return

		if not await _presentation_queue.present(
			resolution,
			_unit_actors,
			_unit_definitions,
			_map_view,
			_hud
		):
			_set_presenting(false)
			return

		automatic_steps += 1

		if _finish_battle_if_needed(resolution):
			return

	var active := _battle_session.get_unit(
		_battle_session.get_active_unit_id()
	)

	if active != null:
		_show_unit_movement(active)

	_set_presenting(false)


func _refresh_map_revision() -> void:
	var revision := _battle_session.get_map_revision()

	if revision == _known_map_revision:
		return

	_known_map_revision = revision
	_hex_grid = _battle_session.get_hex_grid()
	_input_router.setup(_hex_grid)
	_movement_search_result = null
	_map_view.clear_overlays()

	var active := _battle_session.get_unit(
		_battle_session.get_active_unit_id()
	)

	if active != null:
		_show_unit_movement(active)


func _get_unit_display_name(unit_id: StringName) -> String:
	var definition := _unit_definitions.get(unit_id) as UnitDefinition

	if definition == null:
		push_warning("UnitDefinition is not registered for presentation.")
		return String(unit_id)

	return definition.display_name


func _set_presenting(is_presenting: bool) -> void:
	_is_presenting = is_presenting
	_input_router.set_interaction_enabled(not is_presenting)
	_hud.set_interaction_enabled(not is_presenting)

	if is_presenting:
		_selected_ability_id = StringName()
		_ability_target_hexes.clear()
		_attackable_target_hexes.clear()
		_map_view.show_targetable_cells(_attackable_target_hexes)
		_map_view.clear_ability_area()
		_hud.clear_target()


func _finish_battle_if_needed(
	resolution: BattleResolution = null
) -> bool:
	var result: BattleResult

	if resolution != null:
		result = resolution.battle_result

	if result == null:
		result = _battle_session.get_result()

	if result == null:
		return false

	_movement_search_result = null
	_map_view.clear_overlays()
	_hud.show_outcome(result.outcome)
	_set_presenting(true)
	battle_finished.emit(result)
	return true


func _refresh_attack_targets(state: UnitSnapshot) -> void:
	_attackable_target_hexes.clear()

	if state == null or _battle_session.is_unit_ai_controlled(state.unit_id):
		_map_view.show_targetable_cells(_attackable_target_hexes)
		return

	var targets := _battle_session.get_attackable_targets(state.unit_id)

	for target: UnitSnapshot in targets:
		_attackable_target_hexes.append(target.hex)

	_map_view.show_targetable_cells(_attackable_target_hexes)


func _show_unit_movement(state: UnitSnapshot) -> void:
	_selected_ability_id = StringName()
	_ability_target_hexes.clear()
	_map_view.clear_ability_area()
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
	_hud.show_health(state.health.current, state.health.maximum)
	_hud.show_movement(
		state.turn.movement_remaining,
		state.turn.movement_max
	)
	_hud.show_main_action(state.turn.main_action_available)
	_hud.show_grenade_button(
		state.ability_ids.has(GRENADE_ABILITY_ID)
		and not _battle_session.is_unit_ai_controlled(state.unit_id),
		state.turn.main_action_available
	)

	var definition := _unit_definitions.get(state.unit_id) as UnitDefinition

	if definition == null:
		push_error("Active unit definition is not registered.")
		return

	_hud.show_active_unit(
		definition.display_name
	)
	_hud.show_active_portrait(definition.actor_texture)
	_hud.show_combat_stats(
		state.basic_attack_damage,
		state.basic_attack_range
	)
	_hud.show_basic_attack_button(
		state.basic_attack_range,
		state.turn.main_action_available
	)
	_refresh_turn_order()


func _refresh_turn_order() -> void:
	var entries: Array[Dictionary] = []

	for unit_id: StringName in _battle_session.get_turn_order():
		var state := _battle_session.get_unit(unit_id)

		if state == null:
			continue

		var definition := _unit_definitions.get(unit_id) as UnitDefinition
		var display_name := String(unit_id)
		var texture: Texture2D

		if definition != null:
			display_name = definition.display_name
			texture = definition.actor_texture

		entries.append({
			"unit_id": unit_id,
			"short_name": display_name.left(7).to_upper(),
			"texture": texture,
			"faction": state.faction,
			"defeated": state.health.is_defeated(),
		})

	_hud.show_turn_order(
		entries,
		_battle_session.get_active_unit_id()
	)
