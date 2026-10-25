class_name BattleMapDefinition
extends Resource

const MIN_GRID_OFFSET_Y := -540
const MAX_GRID_OFFSET_Y := 540

@export var id: StringName
# Presentation metadata; never used by battle rules.
@export var background_id: StringName = &"plateau"
@export var presentation_frame := Vector2i.ZERO
@export var grid_offset_y := 0
@export var has_custom_grid_offset := false
@export var obstacles: Array[BattleObstacleDefinition] = []
@export var cells: Array[BattleMapCellDefinition] = []
