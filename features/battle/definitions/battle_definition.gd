class_name BattleDefinition
extends Resource


@export var id: StringName
@export var primary_objective: BattleObjectiveDefinition
@export var protected_faction: BattleFaction.Value = BattleFaction.Value.PLAYER
@export var unit_spawns: Array[BattleUnitSpawnDefinition] = []