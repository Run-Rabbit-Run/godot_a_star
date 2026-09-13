class_name BattleSession
extends RefCounted


var setup: BattleSetup
var _state: BattleState
var _engine: BattleEngine
var _battle_result: BattleResult
var _side_command_sources: Dictionary[StringName, CommandSource] = {}
var _unit_command_sources: Dictionary[StringName, CommandSource] = {}
var _unit_side_ids: Dictionary[StringName, StringName] = {}


func _init(
	p_setup: BattleSetup,
	p_state: BattleState,
	p_engine: BattleEngine
) -> void:
	setup = p_setup
	_state = p_state
	_engine = p_engine
	_build_command_sources()
	_capture_result()


func get_hex_grid() -> HexGrid:
	return _state.hex_grid.duplicate_grid()


func get_unit(unit_id: StringName) -> UnitSnapshot:
	return _to_snapshot(_engine.get_unit(unit_id))


func get_unit_at(hex: Vector2i) -> UnitSnapshot:
	return _to_snapshot(_engine.get_unit_at(hex))


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
	return true


func get_next_ai_command() -> BattleCommand:
	if is_finished():
		return null

	var source := _get_command_source(get_active_unit_id())

	if source == null or not source.is_automatic():
		return null

	return source.next_command(self)



func step(command: BattleCommand) -> BattleResolution:
	if is_finished():
		return BattleResolution.rejected(
			"Battle is already finished.",
			get_state_revision(),
			get_active_unit_id(),
			get_result()
		)

	var resolution := _engine.execute(command)

	if resolution.battle_result != null:
		_battle_result = resolution.battle_result

	return resolution


func execute_command(command: BattleCommand) -> BattleResolution:
	return step(command)


func apply_map_mutations(
	mutations: Array[MapMutation]
) -> BattleResolution:
	if is_finished():
		return BattleResolution.rejected(
			"Battle is already finished.",
			get_state_revision(),
			get_active_unit_id(),
			get_result()
		)

	var resolution := _engine.apply_map_mutations(mutations)

	if resolution.battle_result != null:
		_battle_result = resolution.battle_result

	return resolution


func _build_command_sources() -> void:
	for side: BattleSideData in setup.sides:
		if side.control_source == BattleControlSource.Value.AI:
			_side_command_sources[side.side_id] = AICommandSource.new(
				side.ai_profile_definition
			)
		else:
			_side_command_sources[side.side_id] = PlayerCommandSource.new()

	for spawn: UnitSpawnData in setup.unit_spawns:
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
	for side: BattleSideData in setup.sides:
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
