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


func duplicate_setup() -> BattleSetup:
	var copied_sides: Array[BattleSideData] = []
	for side: BattleSideData in sides:
		copied_sides.append(BattleSideData.new(side.side_id, side.faction, side.control_source, side.ai_profile_definition.duplicate(true) if side.ai_profile_definition != null else null))
	var copied_spawns: Array[UnitSpawnData] = []
	for spawn: UnitSpawnData in unit_spawns:
		var copied_abilities: Array[AbilityDefinition] = []
		for ability: AbilityDefinition in spawn.abilities:
			copied_abilities.append(ability.duplicate(true))
		copied_spawns.append(UnitSpawnData.new(spawn.unit_id, spawn.placement_id, spawn.definition_id, spawn.unit_definition.duplicate(true), spawn.side_id, spawn.faction, spawn.control_source, spawn.ai_profile_id, spawn.ai_profile_definition.duplicate(true) if spawn.ai_profile_definition != null else null, spawn.hex, spawn.modifiers, copied_abilities))
	return BattleSetup.new(battle_id, hex_grid.duplicate_grid(), copied_sides, copied_spawns, primary_objective_definition.duplicate(true), protected_faction, deterministic_seed)
