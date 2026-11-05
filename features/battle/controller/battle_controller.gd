class_name BattleController
extends Node


signal battle_finished(result: BattleResult)
signal battle_started
signal battle_failed(message: String)
signal _frame_passed


const HEALTH_DISPLAY_CONTROLLER := preload("res://features/battle/view/battle_health_display_controller.gd")


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
var _is_initialized := false
var initialization_error := ""
var _selection := PlayerActionSelection.new()
## A ready player unit chosen by click while no unit has started its turn.
var _selected_unit_id := StringName()
var _active_unit_hud := ActiveUnitHudPresenter.new()
var _is_presenting := false
var _runtime_failed := false
var _completion_emitted := false
var _automatic_run_active := false
## The AI decision computed on a worker thread and its pool task, or null and -1.
var _ai_decision: AIDecision
var _ai_task_id := -1
var _unit_views := BattleUnitViewRegistry.new()

# Read-only compatibility bridge for diagnostics that inspect the old field name.
var _unit_actors: Dictionary[StringName, UnitActor]:
	get:
		return _unit_views.actors


func _ready() -> void:
	set_process(false)


func setup(
	request: BattleStartRequest,
	prepared_session: BattleSession = null
) -> bool:
	var validation := BattleStartRequestValidator.validate(request)

	if not validation.is_valid:
		initialization_error = validation.error_message
		push_error("Battle setup failed: %s" % validation.error_message)
		return false

	if _is_initialization_requested:
		initialization_error = "BattleController setup can only be called once."
		push_error("BattleController setup can only be called once.")
		return false

	if prepared_session == null:
		var result := BattleSessionFactory.create(request)

		if not result.is_successful:
			initialization_error = result.error_message
			return false

		prepared_session = result.session
	elif (
		prepared_session.content_snapshot != request.content_snapshot
		or prepared_session.get_battle_id() != request.battle_id
		or prepared_session.get_deterministic_seed() != request.deterministic_seed
	):
		# The view reads content from the request, so it must describe the same battle.
		initialization_error = "Prepared battle session does not match the start request."
		push_error(initialization_error)
		return false

	_battle_session = prepared_session
	_start_request = request
	if BattleLoggingController.is_feature_enabled():
		var logging := BattleLoggingController.new()
		logging.name = "BattleLoggingController"
		add_child(logging)
		logging.setup(_battle_session, _hud, self)
	_is_initialization_requested = true
	call_deferred("_initialize_battle")
	return true


func set_playback_speed(speed: float) -> bool:
	return _presentation_queue.set_speed(speed)


func apply_map_mutations(
	mutations: Array[MapMutation]
) -> BattleResolution:
	# The session exists right after setup(), but actors and the grid appear only later.
	if not _is_initialized or _is_presenting or _runtime_failed:
		return BattleResolution.rejected(
			"Battle is not ready for a new operation.",
			0,
			StringName()
		)

	_set_presenting(true)
	var resolution := _battle_session.apply_map_mutations(mutations)

	if not resolution.accepted:
		_set_presenting(false)
		return resolution

	var presented := await _present_resolution(
		resolution,
		_unit_views.actors,
		_unit_views.definitions,
		_map_view,
		_hud
	)
	if not presented:
		return resolution
	_refresh_map_revision()
	if not _finish_battle_if_needed(resolution):
		await _continue_turn_cycle()
	return resolution


func _initialize_battle() -> void:
	if _start_request == null:
		push_error("BattleController requires setup before initialization.")
		return

	_battle_setup = _battle_session.setup
	_hex_grid = _battle_session.get_hex_grid()
	_known_map_revision = _battle_session.get_map_revision()
	_map_view.render_grid(_hex_grid)
	_input_router.setup(_hex_grid)
	_unit_views.setup(_start_request.content_snapshot, _units, _map_view)
	_selection.setup(_battle_session, _map_view, _hud, _unit_views, _start_request.content_snapshot)
	_selection.set_grid(_hex_grid)
	_active_unit_hud.setup(_battle_session, _hud, _unit_views, _start_request.content_snapshot)

	if not _unit_views.create_units(
		_battle_setup.unit_spawns,
		_battle_session
	):
		initialization_error = "Battle unit presentation could not be created."
		battle_failed.emit(initialization_error)
		return

	_hud.end_turn_requested.connect(_on_end_turn_requested)
	var health_display := HEALTH_DISPLAY_CONTROLLER.new()
	health_display.name = "HealthDisplayController"
	add_child(health_display)
	health_display.setup(_unit_views.actors, _hud.get_health_alt_check())
	_hud.movement_requested.connect(_on_movement_requested)
	_hud.basic_attack_requested.connect(_on_basic_attack_requested)
	_hud.attack_type_requested.connect(_on_attack_type_requested)
	_hud.ability_requested.connect(_on_ability_requested)
	_hud.strategist_ability_requested.connect(_on_strategist_ability_requested)
	_hud.playback_speed_requested.connect(_on_playback_speed_requested)
	_input_router.hex_selected.connect(_on_hex_selected)
	_input_router.hex_hovered.connect(_on_hex_hovered)
	_input_router.hex_hover_exited.connect(_on_hex_hover_exited)
	_hud.clear_action()
	_hud.show_objective(_objective_text())
	_presentation_queue.configure(_start_request.content_snapshot, _unit_views)
	_set_presenting(true)
	var initial_resolution := _battle_session.get_initial_resolution()
	# Initial events can already include skipped turns crossing round boundaries.
	_hud.log_round(1)
	# Actors were created after the start effects; replay their damage from the prior health.
	_unit_views.show_health_before(initial_resolution.events)
	var was_initial_presented := await _present_resolution(
		initial_resolution,
		_unit_views.actors,
		_unit_views.definitions,
		_map_view,
		_hud
	)

	if not was_initial_presented:
		return

	_is_initialized = true
	battle_started.emit()

	if _finish_battle_if_needed():
		return

	_set_presenting(false)

	var active := _battle_session.get_unit(_acting_unit_id())

	if active != null:
		_show_unit_movement(active)

		if _battle_session.is_active_unit_ai_controlled():
			_set_presenting(true)
			await _run_ai_turns()


func _on_hex_selected(axial_cell: Vector2i) -> void:
	if _is_presenting or _battle_session == null:
		return

	var active_unit_id := _acting_unit_id()

	if active_unit_id.is_empty():
		return

	var active := _battle_session.get_unit(active_unit_id)

	if active == null:
		push_error("Active unit snapshot is not registered.")
		return

	if _battle_session.is_unit_ai_controlled(active.unit_id):
		return

	# Before any unit starts, clicking another ready unit of the player chooses it.
	var clicked := _battle_session.get_unit_at(axial_cell)
	if (
		clicked != null
		and clicked.unit_id != active.unit_id
		and not _selection.is_aiming_ability()
		and _battle_session.can_command(clicked.unit_id)
		and not _battle_session.is_unit_ai_controlled(clicked.unit_id)
	):
		_selected_unit_id = clicked.unit_id
		_show_unit_movement(clicked)
		return

	var command := _selection.command_at(active, axial_cell)

	if command == null:
		return

	var resolution := _battle_session.step(command)

	if not resolution.accepted:
		return

	_set_presenting(true)
	var was_presented := await _present_resolution(
		resolution,
		_unit_views.actors,
		_unit_views.definitions,
		_map_view,
		_hud
	)
	_refresh_map_revision()

	if _finish_battle_if_needed(resolution):
		return

	if was_presented and _acting_unit_id() != active_unit_id:
		await _continue_turn_cycle()
		return

	_set_presenting(false)

	if not was_presented:
		return

	active = _battle_session.get_unit(active_unit_id)

	if active != null:
		_show_unit_movement(active)


func _on_hex_hovered(axial_cell: Vector2i) -> void:
	_selection.hover(axial_cell)


func _on_hex_hover_exited() -> void:
	_selection.hover_exited()


func _on_ability_requested(ability_id: StringName) -> void:
	if _is_presenting or _battle_session == null:
		return

	var active := _battle_session.get_unit(_acting_unit_id())

	_selection.select_ability(active, ability_id)


## Aims the strategist's ability: its landing hexes become clickable although the grid lacks them.
func _on_strategist_ability_requested(ability_id: StringName) -> void:
	if _is_presenting or _battle_session == null or _battle_session.is_active_unit_ai_controlled():
		return
	if _selection.select_strategist_ability(ability_id):
		_input_router.set_extra_cells(_selection.get_extra_target_cells())


func _on_movement_requested() -> void:
	if _is_presenting or _battle_session == null:
		return

	var active := _battle_session.get_unit(_acting_unit_id())

	if (
		active == null
		or _battle_session.is_unit_ai_controlled(active.unit_id)
	):
		return

	_show_unit_movement(active)


func _on_basic_attack_requested() -> void:
	if _is_presenting or _battle_session == null:
		return

	var active := _battle_session.get_unit(_acting_unit_id())

	if (
		active == null
		or _battle_session.is_unit_ai_controlled(active.unit_id)
		or not active.turn.main_action_available
	):
		return

	_show_unit_movement(active)


## The next attack of the shown unit takes its other damage type; nothing changes in the battle
## until the attack is made.
func _on_attack_type_requested() -> void:
	if _is_presenting or _battle_session == null:
		return
	var active := _battle_session.get_unit(_acting_unit_id())
	if active == null or not _selection.cycle_attack_damage_type():
		return
	_active_unit_hud.show(active, _selection.attack_damage_type())


func _on_playback_speed_requested(speed: float) -> void:
	if not set_playback_speed(speed):
		push_warning("Requested playback speed is outside allowed range.")


func _on_end_turn_requested() -> void:
	if _is_presenting or _battle_session == null or _battle_session.is_active_unit_ai_controlled():
		return

	_set_presenting(true)
	var resolution := _battle_session.step(
		EndTurnCommand.new(_acting_unit_id())
	)

	if not resolution.accepted:
		if not _finish_battle_if_needed(resolution):
			push_error(resolution.rejection_reason)
			_set_presenting(false)
		return

	var presented := await _present_resolution(
		resolution,
		_unit_views.actors,
		_unit_views.definitions,
		_map_view,
		_hud
	)
	if not presented or _finish_battle_if_needed(resolution):
		return
	await _continue_turn_cycle()


## The objective with the units it names: commanders to defeat and units to keep alive.
func _objective_text() -> String:
	var parts: PackedStringArray = [_battle_session.get_objective_description()]
	for entry: Array in [["командир", _battle_session.get_objective_target_ids()], ["сохранить", _battle_session.get_protected_unit_ids()]]:
		var names: PackedStringArray = []
		for unit_id: StringName in entry[1]:
			names.append(_unit_views.get_display_name(unit_id))
		if not names.is_empty():
			parts.append("%s: %s" % [entry[0], ", ".join(names)])
	return " · ".join(parts)


## The started unit, else the player's chosen ready unit, else the engine's default.
func _acting_unit_id() -> StringName:
	var current := _battle_session.get_current_unit_id()
	if not current.is_empty():
		return current
	if not _selected_unit_id.is_empty() and _battle_session.can_command(_selected_unit_id) and not _battle_session.is_unit_ai_controlled(_selected_unit_id):
		return _selected_unit_id
	_selected_unit_id = StringName()
	return _battle_session.get_active_unit_id()


func _continue_turn_cycle() -> void:
	if _runtime_failed:
		return
	_refresh_map_revision()
	var active_unit_id := _acting_unit_id()
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
	if _automatic_run_active or _runtime_failed:
		return
	_automatic_run_active = true
	await _execute_ai_turns()
	_automatic_run_active = false


func _execute_ai_turns() -> void:
	var guard := AutomaticRunGuard.new()

	while (
		not _battle_session.is_finished()
		and _battle_session.is_active_unit_ai_controlled()
	):
		# Commands without animation still hand the frame back instead of spinning.
		await _next_frame()
		if _runtime_failed:
			return

		var command := await _decide_ai_command()
		if _runtime_failed:
			return

		if command == null:
			_fail_runtime("AI command source did not provide a command.")
			return

		# The tactical AI picks its unit itself; the guard counts the unit that acts.
		var active := _battle_session.get_unit(ActionPreview.actor_of(command))

		if active == null:
			_fail_runtime("AI-controlled active unit is not registered.")
			return

		var limit_error := guard.check(active, _battle_session.get_round_number())
		if not limit_error.is_empty():
			_fail_runtime(limit_error)
			return

		_show_unit_movement(active)

		var resolution := _battle_session.step(command)

		if not resolution.accepted:
			_fail_runtime("AI command was rejected: %s" % resolution.rejection_reason)
			return

		guard.record(resolution, _battle_session.get_round_number())
		if not await _present_resolution(
			resolution,
			_unit_views.actors,
			_unit_views.definitions,
			_map_view,
			_hud
		):
			_set_presenting(false)
			return

		_refresh_map_revision()

		if _finish_battle_if_needed(resolution):
			return

	var active := _battle_session.get_unit(_acting_unit_id())

	if active != null:
		_show_unit_movement(active)

	_set_presenting(false)


## The AI plans its next command on a worker thread over a copy of the battle, while frames
## keep coming; the live session is not touched until the decision is finished here.
func _decide_ai_command() -> BattleCommand:
	var decision := _battle_session.prepare_ai_decision()
	if decision == null:
		return null
	_ai_decision = decision
	_ai_task_id = WorkerThreadPool.add_task(decision.compute, false, "Battle AI decision")
	while _ai_task_id >= 0 and not WorkerThreadPool.is_task_completed(_ai_task_id):
		await _next_frame()
	_collect_ai_task()
	return _battle_session.finish_ai_decision(decision)


## True while the AI computes its next command on a worker thread.
func is_ai_deciding() -> bool:
	return _ai_task_id >= 0


## Every pool task is collected once: a finished one at once, a running one when it ends.
func _collect_ai_task() -> void:
	if _ai_task_id < 0:
		return
	WorkerThreadPool.wait_for_task_completion(_ai_task_id)
	_ai_task_id = -1
	_ai_decision = null


func _exit_tree() -> void:
	# A battle closed mid-decision waits for its planner, which reads only its own copy.
	_collect_ai_task()


## Awaits a signal of this node, so a freed battle drops the waiting loop silently.
func _next_frame() -> void:
	set_process(true)
	await _frame_passed


func _process(_delta: float) -> void:
	set_process(false)
	_frame_passed.emit()


func _refresh_map_revision() -> void:
	var revision := _battle_session.get_map_revision()

	if revision == _known_map_revision:
		return

	_known_map_revision = revision
	_hex_grid = _battle_session.get_hex_grid()
	_input_router.setup(_hex_grid)
	_selection.set_grid(_hex_grid)
	_map_view.clear_overlays()

	var active := _battle_session.get_unit(_acting_unit_id())

	if active != null:
		_show_unit_movement(active)


func _set_presenting(is_presenting: bool) -> void:
	is_presenting = is_presenting or _runtime_failed
	_is_presenting = is_presenting
	_input_router.set_interaction_enabled(not is_presenting)
	_hud.set_interaction_enabled(not is_presenting)

	_selection.enabled = not is_presenting

	if is_presenting:
		var none: Array[Vector2i] = []
		_input_router.set_extra_cells(none)
		_selection.clear()


func _finish_battle_if_needed(
	resolution: BattleResolution = null
) -> bool:
	if _runtime_failed or _completion_emitted:
		return true
	var result: BattleResult

	if resolution != null:
		result = resolution.battle_result

	if result == null:
		result = _battle_session.get_result()

	if result == null:
		return false

	_selection.forget_movement()
	_map_view.clear_overlays()
	_hud.show_outcome(result.outcome)
	_set_presenting(true)
	_completion_emitted = true
	battle_finished.emit(result)
	return true


## The active unit's options on the map and its panels in the HUD.
func _show_unit_movement(state: UnitSnapshot) -> void:
	var none: Array[Vector2i] = []
	_input_router.set_extra_cells(none)
	_selection.show_movement_and_attacks(state)
	_active_unit_hud.show(state, _selection.attack_damage_type())


func _present_resolution(resolution: BattleResolution, actors: Dictionary[StringName, UnitActor], definitions: Dictionary[StringName, UnitDefinition], map_view: BattleMapView, hud: BattleHUD) -> bool:
	# Retain spawn definitions even if an earlier event prevents their presentation.
	for event: BattleEvent in resolution.events:
		if event is UnitSummonedEvent:
			_unit_views.definitions[event.unit.unit_id] = event.definition
	var presented := await _presentation_queue.present(resolution, actors, definitions, map_view, hud)
	if not presented or not resolution.terminal_error.is_empty():
		_synchronize_view()
		_fail_runtime(resolution.terminal_error if not resolution.terminal_error.is_empty() else "Battle presentation failed; state was synchronized and playback stopped.")
		return false
	# A cut animation is optional presentation: the view snaps to the session and play goes on.
	if _presentation_queue.interrupted_steps > 0:
		_synchronize_view()
	# Units that have had their turn stay dimmed until their faction's next phase.
	_unit_views.show_spent_turns(_battle_session)
	return true


## Rebuilds the map, actors, health, statuses and bodies from the authoritative session.
func _synchronize_view() -> void:
	_hex_grid = _battle_session.get_hex_grid()
	_known_map_revision = _battle_session.get_map_revision()
	_input_router.setup(_hex_grid)
	_selection.set_grid(_hex_grid)
	_map_view.render_grid(_hex_grid)
	_unit_views.synchronize(_battle_session)


func _fail_runtime(message: String) -> void:
	if _runtime_failed:
		return
	_runtime_failed = true
	initialization_error = message
	_hud.append_battle_log("Бой остановлен: %s" % message)
	_set_presenting(true)
	battle_failed.emit(message)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _is_presenting:
		_on_movement_requested()
		get_viewport().set_input_as_handled()
