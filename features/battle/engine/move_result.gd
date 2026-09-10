class_name MoveResult
extends RefCounted


var is_successful: bool
var unit_id: StringName
var path: Array[Vector2i] = []
var movement_cost: int


func _init(
    p_is_successful: bool,
    p_unit_id: StringName,
    p_path: Array[Vector2i],
    p_movement_cost: int
) -> void:
    is_successful = p_is_successful
    unit_id = p_unit_id
    path.assign(p_path)
    movement_cost = p_movement_cost


static func failure() -> MoveResult:
    var empty_path: Array[Vector2i] = []

    return MoveResult.new(
        false,
        StringName(),
        empty_path,
        0
    )


static func success(
    p_unit_id: StringName,
    p_path: Array[Vector2i],
    p_movement_cost: int
) -> MoveResult:
    return MoveResult.new(
        true,
        p_unit_id,
        p_path,
        p_movement_cost
    )
