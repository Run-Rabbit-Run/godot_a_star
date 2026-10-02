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
