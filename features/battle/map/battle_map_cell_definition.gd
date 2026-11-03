class_name BattleMapCellDefinition
extends Resource


@export var hex: Vector2i
@export var movement_cost: int = 1
@export var terrain_id: StringName = &"core:default"
## The two hex layers at the start of the battle; see HexStateCatalog.
@export var liquid_id: StringName = StringName()
@export var energy_id: StringName = StringName()
@export var traversable := true


func _init(
	p_hex: Vector2i = Vector2i.ZERO,
	p_movement_cost: int = 1,
	p_terrain_id: StringName = &"core:default",
	p_traversable: bool = true,
	p_liquid_id: StringName = StringName(),
	p_energy_id: StringName = StringName()
) -> void:
	hex = p_hex
	movement_cost = p_movement_cost
	terrain_id = p_terrain_id
	traversable = p_traversable
	liquid_id = p_liquid_id
	energy_id = p_energy_id


func has_layers() -> bool:
	return not liquid_id.is_empty() or not energy_id.is_empty()
