class_name BattleUnitSpawnDefinition
extends Resource


@export var unit_id: StringName
@export var unit_definition: UnitDefinition
@export var faction: BattleFaction.Value = BattleFaction.Value.PLAYER
@export var hex: Vector2i