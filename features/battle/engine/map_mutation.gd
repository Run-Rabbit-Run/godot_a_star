class_name MapMutation
extends RefCounted


var kind: MapMutationKind.Value
var hex: Vector2i
var terrain_id: StringName
var traversable: bool
var movement_cost: int


func _init(
	p_kind: MapMutationKind.Value,
	p_hex: Vector2i,
	p_terrain_id: StringName = StringName(),
	p_traversable: bool = true,
	p_movement_cost: int = 1
) -> void:
	kind = p_kind
	hex = p_hex
	terrain_id = p_terrain_id
	traversable = p_traversable
	movement_cost = p_movement_cost


static func add_hex(
	hex: Vector2i,
	terrain_id: StringName,
	movement_cost: int = 1,
	traversable: bool = true
) -> MapMutation:
	return MapMutation.new(
		MapMutationKind.Value.ADD_HEX,
		hex,
		terrain_id,
		traversable,
		movement_cost
	)


static func remove_hex(hex: Vector2i) -> MapMutation:
	return MapMutation.new(MapMutationKind.Value.REMOVE_HEX, hex)


static func change_terrain(
	hex: Vector2i,
	terrain_id: StringName
) -> MapMutation:
	return MapMutation.new(
		MapMutationKind.Value.CHANGE_TERRAIN,
		hex,
		terrain_id
	)


static func set_traversal(
	hex: Vector2i,
	traversable: bool,
	movement_cost: int = 1
) -> MapMutation:
	return MapMutation.new(
		MapMutationKind.Value.SET_TRAVERSAL,
		hex,
		StringName(),
		traversable,
		movement_cost
	)