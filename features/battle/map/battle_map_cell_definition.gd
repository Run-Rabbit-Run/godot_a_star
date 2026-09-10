class_name BattleMapCellDefinition
extends Resource


@export var hex: Vector2i
@export var movement_cost: int = 1


func _init(
    p_hex: Vector2i = Vector2i.ZERO,
    p_movement_cost: int = 1
) -> void:
    hex = p_hex
    movement_cost = p_movement_cost
