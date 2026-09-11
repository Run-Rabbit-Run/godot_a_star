class_name BattleSetup
extends RefCounted


var battle_id: StringName
var hex_grid: HexGrid
var sides: Array[BattleSideData]
var unit_spawns: Array[UnitSpawnData]
var primary_objective_definition: BattleObjectiveDefinition
var protected_faction: BattleFaction.Value
var deterministic_seed: int


func _init(
	p_battle_id: StringName,
	p_hex_grid: HexGrid,
	p_sides: Array[BattleSideData],
	p_unit_spawns: Array[UnitSpawnData],
	p_primary_objective_definition: BattleObjectiveDefinition,
	p_protected_faction: BattleFaction.Value,
	p_deterministic_seed: int
) -> void:
	battle_id = p_battle_id
	hex_grid = p_hex_grid
	sides = p_sides.duplicate()
	unit_spawns = p_unit_spawns.duplicate()
	primary_objective_definition = p_primary_objective_definition
	protected_faction = p_protected_faction
	deterministic_seed = p_deterministic_seed
