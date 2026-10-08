class_name BattleSession
extends RefCounted

## Synchronous observer boundary; the session owns no file or logging settings.
signal diagnostic_record(kind: String, data: Dictionary)


var _setup: BattleSetup
var setup: BattleSetup:
	get:
		return _setup.duplicate_setup()
var _content_snapshot: ContentSnapshot
var content_snapshot: ContentSnapshot:
	get:
		return _content_snapshot
var _state: BattleState
var _engine: BattleEngine
var _battle_result: BattleResult
var _side_command_sources: Dictionary[StringName, CommandSource] = {}
var _unit_command_sources: Dictionary[StringName, CommandSource] = {}
var _unit_side_ids: Dictionary[StringName, StringName] = {}


func _init(
	p_setup: BattleSetup,
	p_state: BattleState,
	p_engine: BattleEngine,
	p_content_snapshot: ContentSnapshot
) -> void:
	_content_snapshot = p_content_snapshot
	_setup = p_setup.duplicate_setup()
	_state = p_state
	_engine = p_engine
	_build_command_sources()
	_capture_result()


## Scalar identity without the deep copy made by the `setup` property.
func get_battle_id() -> StringName:
	return _engine.get_battle_id()


func get_deterministic_seed() -> int:
	return _engine.get_deterministic_seed()


func get_hex_grid() -> HexGrid:
	return _state.hex_grid.duplicate_grid()


## Commands on the returned engine change only its detached prediction state.
func create_prediction_engine() -> BattleEngine:
	return _engine.fork_for_prediction()


func get_initial_resolution() -> BattleResolution:
	return _engine.get_initial_resolution()


func get_unit(unit_id: StringName) -> UnitSnapshot:
	return _to_snapshot(_engine.get_unit(unit_id))


func get_unit_at(hex: Vector2i) -> UnitSnapshot:
	return _to_snapshot(_engine.get_unit_at(hex))


func get_corpses_at(hex: Vector2i) -> Array[UnitSnapshot]:
	return _state.get_corpses_at(hex)


func get_living_units_by_faction(
	faction: BattleFaction.Value
) -> Array[UnitSnapshot]:
	return _to_snapshots(_engine.get_living_units_by_faction(faction))


func get_living_opponents(
	faction: BattleFaction.Value
) -> Array[UnitSnapshot]:
	var opponents: Array[UnitSnapshot] = []

	for candidate: UnitState in _state.unit_states.values():
		if candidate.faction == faction or candidate.health.is_defeated():
			continue

		opponents.append(_to_snapshot(candidate))

	opponents.sort_custom(_is_unit_id_before)
	return opponents


func get_attackable_targets(unit_id: StringName) -> Array[UnitSnapshot]:
	return _to_snapshots(_engine.get_attackable_targets(unit_id))


func get_ability_target_hexes(unit_id: StringName, ability_id: StringName) -> Array[Vector2i]:
	return _engine.get_ability_target_hexes(unit_id, ability_id)


func get_active_unit_id() -> StringName:
	return _engine.get_active_unit_id()


func get_round_number() -> int:
	return _engine.get_round_number()


func get_turn_order() -> Array[StringName]:
	return _engine.get_turn_order()


func get_state_revision() -> int:
	return _engine.get_state_revision()


func get_map_revision() -> int:
	return _engine.get_map_revision()


func get_objective_description() -> String:
	return _engine.get_objective_description()


func get_outcome() -> BattleOutcome.Value:
	return _engine.get_outcome()


func get_movement_search(unit_id: StringName) -> MovementSearchResult:
	return _engine.get_movement_search(unit_id)


func get_result() -> BattleResult:
	_capture_result()
	return _battle_result


func is_finished() -> bool:
	return get_result() != null


func is_unit_ai_controlled(unit_id: StringName) -> bool:
	var source := _get_command_source(unit_id)
	return source != null and source.is_automatic()


func is_active_unit_ai_controlled() -> bool:
	return is_unit_ai_controlled(get_active_unit_id())


func set_side_command_source(
	side_id: StringName,
	source: CommandSource
) -> bool:
	if is_finished() or source == null or _get_side(side_id) == null:
		return false

	_side_command_sources[side_id] = source
	if has_diagnostic_observer():
		diagnostic_record.emit("control_source_changed", {"side_id": side_id, "source_type": source.get_script().get_global_name(), "automatic": source.is_automatic(), "profile": source.profile if source is AICommandSource else null})
	return true


func get_next_ai_command() -> BattleCommand:
	if is_finished():
		return null

	var source := _get_command_source(get_active_unit_id())

	if source == null or not source.is_automatic():
		return null

	var trace := {}
	if has_diagnostic_observer() and source is AICommandSource:
		source.decision_trace = trace
	var command := source.next_command(self)
	if has_diagnostic_observer():
		diagnostic_record.emit("ai_decision", {"source_type": source.get_script().get_global_name(), "profile": source.profile if source is AICommandSource else null, "command": command, "trace": trace, "state": get_diagnostic_state()})
	if source is AICommandSource:
		source.decision_trace = null
	return command



func step(command: BattleCommand) -> BattleResolution:
	if has_diagnostic_observer():
		diagnostic_record.emit("command_requested", {"command": command, "active_control": "ai" if is_active_unit_ai_controlled() else "player", "state": get_diagnostic_state()})
	if is_finished():
		var rejected := BattleResolution.rejected(
			"Battle is already finished.",
			get_state_revision(),
			get_active_unit_id(),
			get_result()
		)
		_record_resolution(rejected)
		return rejected

	var resolution := _engine.execute(command)
	for event: BattleEvent in resolution.events:
		if event is UnitSummonedEvent:
			_unit_side_ids[event.unit.unit_id] = _unit_side_ids.get(event.summoner_id, StringName())
			var source := _unit_command_sources.get(event.summoner_id) as CommandSource
			if source != null:
				_unit_command_sources[event.unit.unit_id] = source

	if resolution.battle_result != null:
		_battle_result = resolution.battle_result

	_record_resolution(resolution)
	return resolution


func execute_command(command: BattleCommand) -> BattleResolution:
	return step(command)


func apply_map_mutations(
	mutations: Array[MapMutation]
) -> BattleResolution:
	if has_diagnostic_observer():
		diagnostic_record.emit("map_mutations_requested", {"mutations": mutations, "state": get_diagnostic_state()})
	if is_finished():
		var rejected := BattleResolution.rejected(
			"Battle is already finished.",
			get_state_revision(),
			get_active_unit_id(),
			get_result()
		)
		_record_resolution(rejected)
		return rejected

	var resolution := _engine.apply_map_mutations(mutations)

	if resolution.battle_result != null:
		_battle_result = resolution.battle_result

	_record_resolution(resolution)
	return resolution


func has_diagnostic_observer() -> bool:
	return diagnostic_record.get_connections().size() > 0


func get_diagnostic_state() -> Dictionary:
	var units: Array[UnitSnapshot] = []
	var ids: Array = _state.unit_states.keys()
	ids.sort()
	for id: StringName in ids:
		units.append(get_unit(id))
	return {"units": units, "grid": get_hex_grid(), "turn_order": get_turn_order(), "active_unit_id": get_active_unit_id(), "round": get_round_number(), "state_revision": get_state_revision(), "map_revision": get_map_revision(), "rng_state": str(_state.random.state), "outcome": get_outcome(), "objective": get_objective_description()}


func _record_resolution(resolution: BattleResolution) -> void:
	if has_diagnostic_observer():
		diagnostic_record.emit("resolution", {"resolution": resolution, "state": get_diagnostic_state()})


func _build_command_sources() -> void:
	for side: BattleSideData in _setup.sides:
		if side.control_source == BattleControlSource.Value.AI:
			_side_command_sources[side.side_id] = AICommandSource.new(
				side.ai_profile_definition
			)
		else:
			_side_command_sources[side.side_id] = PlayerCommandSource.new()

	for spawn: UnitSpawnData in _setup.unit_spawns:
		_unit_side_ids[spawn.unit_id] = spawn.side_id

		if spawn.control_source != BattleControlSource.Value.AI:
			continue

		var side := _get_side(spawn.side_id)

		if (
			side != null
			and side.ai_profile_definition != null
			and spawn.ai_profile_definition != null
			and side.ai_profile_definition.id == spawn.ai_profile_definition.id
		):
			continue

		_unit_command_sources[spawn.unit_id] = AICommandSource.new(
			spawn.ai_profile_definition
		)


func _get_command_source(unit_id: StringName) -> CommandSource:
	var override := _unit_command_sources.get(unit_id) as CommandSource

	if override != null:
		return override

	var side_id: StringName = _unit_side_ids.get(unit_id, StringName())
	return _side_command_sources.get(side_id) as CommandSource


func _get_side(side_id: StringName) -> BattleSideData:
	for side: BattleSideData in _setup.sides:
		if side.side_id == side_id:
			return side

	return null


func _capture_result() -> void:
	if _battle_result == null:
		_battle_result = _engine.get_result()


func _to_snapshot(state: UnitState) -> UnitSnapshot:
	if state == null:
		return null

	return UnitSnapshot.new(state)


func _to_snapshots(states: Array[UnitState]) -> Array[UnitSnapshot]:
	var snapshots: Array[UnitSnapshot] = []

	for state: UnitState in states:
		snapshots.append(_to_snapshot(state))

	return snapshots


func _is_unit_id_before(
	left: UnitSnapshot,
	right: UnitSnapshot
) -> bool:
	return String(left.unit_id) < String(right.unit_id)
