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


func get_ability_affected_hexes(unit_id: StringName, ability_id: StringName, center: Vector2i) -> Array[Vector2i]:
	return _engine.get_ability_affected_hexes(unit_id, ability_id, center)


func get_attackable_obstacle_hexes(unit_id: StringName) -> Array[Vector2i]:
	return _engine.get_attackable_obstacle_hexes(unit_id)


## Abilities of the player faction's strategist, sorted by ID; their content is in the snapshot.
func get_strategist_ability_ids() -> Array[StringName]:
	return _engine.get_strategist_ability_ids()


## Why the faction's strategist cannot use the ability now, or "".
func get_strategist_unavailable_reason(faction: BattleFaction.Value, ability_id: StringName) -> String:
	return _engine.get_strategist_unavailable_reason(faction, ability_id)


## Hexes UseStrategistAbilityCommand accepts now; outside the map for a landing.
func get_strategist_target_hexes(faction: BattleFaction.Value, ability_id: StringName) -> Array[Vector2i]:
	return _engine.get_strategist_target_hexes(faction, ability_id)


func get_active_unit_id() -> StringName:
	return _engine.get_active_unit_id()


func get_round_number() -> int:
	return _engine.get_round_number()


func get_active_faction() -> BattleFaction.Value:
	return _engine.get_active_faction()


## The unit that started its turn and has not finished it, or "".
func get_current_unit_id() -> StringName:
	return _engine.get_current_unit_id()


## Units of the acting faction that may still act this phase, in field order.
func get_ready_unit_ids() -> Array[StringName]:
	return _engine.get_ready_unit_ids()


## True when the unit may give a command now: ready, and no other unit has started.
func can_command(unit_id: StringName) -> bool:
	return _engine.can_command(unit_id)


## True while the battle goes on for a living unit of the acting faction that can no longer act
## this phase: it finished its turn, is paralyzed or joined the phase as a summon. An object
## never takes turns, so it never counts.
func has_spent_turn(unit_id: StringName) -> bool:
	var unit := _engine.get_unit(unit_id)
	return (
		unit != null
		and unit.takes_turns()
		and unit.faction == _engine.get_active_faction()
		and not unit.health.is_defeated()
		and not is_finished()
		and not _engine.get_ready_unit_ids().has(unit_id)
	)


func get_turn_order() -> Array[StringName]:
	return _engine.get_turn_order()


func get_state_revision() -> int:
	return _engine.get_state_revision()


func get_map_revision() -> int:
	return _engine.get_map_revision()


func get_objective_description() -> String:
	return _engine.get_objective_description()


## Commanders the player has to defeat.
func get_objective_target_ids() -> Array[StringName]:
	return _engine.get_objective_target_ids()


## Units whose defeat loses the battle.
func get_protected_unit_ids() -> Array[StringName]:
	return _engine.get_protected_unit_ids()


func get_outcome() -> BattleOutcome.Value:
	return _engine.get_outcome()


## What the command would do, from a forecast copy; the live battle never changes.
func preview(command: BattleCommand) -> ActionPreview:
	return ActionPreview.build(_engine.fork_for_prediction(), _engine, command)


## {"move": cells the unit could reach in its next turn, "attack": cells it could hit from there}.
func get_reach(unit_id: StringName) -> Dictionary:
	return _engine.get_reach(unit_id)


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


## The source that decides the unit's commands, or null.
func get_command_source(unit_id: StringName) -> CommandSource:
	return _get_command_source(unit_id)


## Decides at once on the calling thread; the graphical battle computes the same decision on a
## worker thread through prepare_ai_decision() and finish_ai_decision().
func get_next_ai_command() -> BattleCommand:
	var decision := prepare_ai_decision()
	if decision == null:
		return null
	decision.compute()
	return finish_ai_decision(decision)


## A decision of the automatic source that commands the active unit, or null when none decides
## now. Call on the main thread; the decision plans on a detached copy (AIDecision).
func prepare_ai_decision() -> AIDecision:
	if is_finished():
		return null

	var source := _get_command_source(get_active_unit_id())

	if source == null or not source.is_automatic():
		return null

	# Effects forecast on a worker thread report script errors through this shared counter.
	ScriptErrorWatch.install()
	var trace := {}
	if has_diagnostic_observer() and source is AICommandSource:
		source.decision_trace = trace
	return AIDecision.new(source, fork_for_planning(), trace, get_state_revision())


## The command of a computed decision, published to the observers on the calling thread; null
## when the battle changed after the decision was prepared.
func finish_ai_decision(decision: AIDecision) -> BattleCommand:
	var source := decision.source
	if source is AICommandSource:
		source.decision_trace = null
	if decision.state_revision != get_state_revision():
		push_warning("A stale AI decision was discarded: the battle changed while it was computed.")
		return null
	if has_diagnostic_observer():
		diagnostic_record.emit("ai_decision", {"source_type": source.get_script().get_global_name(), "profile": source.profile if source is AICommandSource else null, "command": decision.command, "trace": decision.trace, "state": get_diagnostic_state()})
	return decision.command


## A forecast copy of the battle under the same command sources, without observers, so a
## planner may read it on another thread while this session waits.
func fork_for_planning() -> BattleSession:
	var state := _state.duplicate_for_prediction()
	var fork := BattleSession.new(_setup, state, _engine.fork_onto(state), _content_snapshot)
	fork._side_command_sources = _side_command_sources.duplicate()
	fork._unit_command_sources = _unit_command_sources.duplicate()
	fork._unit_side_ids = _unit_side_ids.duplicate()
	return fork



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
			# The strategist is no unit: what it brings in joins the side of its faction.
			var side_id: StringName = _unit_side_ids.get(event.summoner_id, _side_of_faction(event.unit.faction))
			_unit_side_ids[event.unit.unit_id] = side_id
			var source := _unit_command_sources.get(event.summoner_id) as CommandSource
			if source != null:
				_unit_command_sources[event.unit.unit_id] = source

	if resolution.battle_result != null:
		_battle_result = resolution.battle_result

	_record_resolution(resolution)
	return resolution


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


func _side_of_faction(faction: BattleFaction.Value) -> StringName:
	for side: BattleSideData in _setup.sides:
		if side.faction == faction:
			return side.side_id
	return StringName()


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
