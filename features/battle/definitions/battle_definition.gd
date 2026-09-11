class_name BattleDefinition
extends Resource


@export var id: StringName
@export var map_id: StringName
@export var primary_objective: BattleObjectiveDefinition
@export var protected_faction: BattleFaction.Value = BattleFaction.Value.PLAYER
@export var sides: Array[BattleSideDefinition] = []
@export var unit_placements: Array[UnitPlacementDefinition] = []
