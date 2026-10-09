class_name MapMutationEvent
extends BattleEvent


var kind: MapMutationKind.Value
var hex: Vector2i
var terrain_id: StringName
var traversable: bool
var movement_cost: int
var hex_state_id: StringName
var hex_state_turns := 0
## Duration-only updates do not repeat exposure or rebuild the state artwork.
var hex_state_changed := true


func _init(
	p_kind: MapMutationKind.Value,
	p_hex: Vector2i,
	p_terrain_id: StringName,
	p_traversable: bool,
	p_movement_cost: int
) -> void:
	kind = p_kind
	hex = p_hex
	terrain_id = p_terrain_id
	traversable = p_traversable
	movement_cost = p_movement_cost
