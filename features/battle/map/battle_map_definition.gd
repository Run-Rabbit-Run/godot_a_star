class_name BattleMapDefinition
extends Resource


@export var id: StringName
# Presentation metadata; never used by battle rules.
@export var background_id: StringName = &"plateau"
@export var presentation_frame := Vector2i.ZERO
@export var obstacles: Array[BattleObstacleDefinition] = []
@export var cells: Array[BattleMapCellDefinition] = []
