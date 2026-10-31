class_name BattleState
extends RefCounted


var battle_id: StringName
var hex_grid: HexGrid
var unit_states: Dictionary[StringName, UnitState]
var turn_service: TurnService
var objective_system: ObjectiveSystem
var deterministic_seed: int
var random: RandomNumberGenerator
var mod_api: ModAPI
var state_revision := 0
var map_revision := 0
## A forecast or transaction copy: its owner discards it, so effects apply to it directly.
var is_detached := false


func _init(
	p_battle_id: StringName,
	p_hex_grid: HexGrid,
	p_unit_states: Dictionary[StringName, UnitState],
	p_turn_order: Array[StringName],
	p_objective_system: ObjectiveSystem,
	p_deterministic_seed: int,
	p_mod_api: ModAPI = null
) -> void:
	battle_id = p_battle_id
	hex_grid = p_hex_grid
	unit_states = p_unit_states
	turn_service = TurnService.new(p_turn_order)
	objective_system = p_objective_system
	deterministic_seed = p_deterministic_seed
	mod_api = p_mod_api if p_mod_api != null else ModAPI.create_default()
	random = RandomNumberGenerator.new()
	random.seed = deterministic_seed


## Defeated states persist at their last hex; several bodies may share a cell.
## Return detached snapshots so future corpse mechanics do not mutate state via queries.
func get_corpses_at(hex: Vector2i) -> Array[UnitSnapshot]:
	var corpses: Array[UnitSnapshot] = []
	for unit: UnitState in unit_states.values():
		if unit.hex == hex and unit.health.is_defeated():
			corpses.append(UnitSnapshot.new(unit))
	corpses.sort_custom(func(a: UnitSnapshot, b: UnitSnapshot) -> bool:
		return String(a.unit_id) < String(b.unit_id)
	)
	return corpses


## Rule definitions/objectives and frozen handlers are read-only; runtime and RNG are detached.
func duplicate_for_prediction() -> BattleState:
	var units: Dictionary[StringName, UnitState] = {}
	for id: StringName in unit_states:
		units[id] = unit_states[id].duplicate_state()
	var copy := BattleState.new(battle_id, hex_grid.duplicate_grid(), units, turn_service.get_turn_order(), objective_system, deterministic_seed, mod_api.frozen_copy())
	copy.turn_service = turn_service.duplicate_service()
	copy.random.state = random.state
	copy.state_revision = state_revision
	copy.map_revision = map_revision
	copy.is_detached = true
	return copy


## Takes over a completed transaction copy in place: holders of this state, its grid and
## its units keep valid references. New units from the copy join the registry as they are.
func adopt(scratch: BattleState) -> void:
	for id: StringName in scratch.unit_states:
		if unit_states.has(id):
			unit_states[id].copy_from(scratch.unit_states[id])
		else:
			unit_states[id] = scratch.unit_states[id]
	hex_grid.replace_with(scratch.hex_grid)
	turn_service.copy_from(scratch.turn_service)
	random.state = scratch.random.state
	state_revision = scratch.state_revision
	map_revision = scratch.map_revision
