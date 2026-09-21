class_name BattleMapCellDefinition
extends Resource


@export var hex: Vector2i
@export var movement_cost: int = 1
@export var terrain_id: StringName = &"core:default"
@export var hex_state_id: StringName = StringName()
@export var traversable := true


func _init(
	p_hex: Vector2i = Vector2i.ZERO,
	p_movement_cost: int = 1,
	p_terrain_id: StringName = &"core:default",
	p_traversable: bool = true,
	p_hex_state_id: StringName = StringName()
) -> void:
	hex = p_hex
	movement_cost = p_movement_cost
	terrain_id = p_terrain_id
	traversable = p_traversable
	hex_state_id = p_hex_state_id