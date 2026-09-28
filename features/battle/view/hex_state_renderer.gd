class_name HexStateRenderer
extends Node2D


const ELECTRIC_SPARK_COLORS := {
	&"core:electricity": Color(0.52, 0.87, 1.0),
	&"core:electrified_water": Color(0.46, 0.82, 1.0),
	&"core:electrified_acid": Color(0.70, 1.0, 0.54),
}


var _terrain_layer: TileMapLayer


func setup(terrain_layer: TileMapLayer) -> void:
	_terrain_layer = terrain_layer


func render(grid: HexGrid) -> void:
	clear()

	if grid == null or _terrain_layer == null:
		return

	for hex: Vector2i in grid.get_cells():
		var state_id := grid.get_hex_state_id(hex)

		if state_id.is_empty():
			continue

		_render_state(hex, state_id)


func remove_hex(hex: Vector2i) -> void:
	for node_name in [
		"HexState_%d_%d" % [hex.x, hex.y],
		"ElectricSparks_%d_%d" % [hex.x, hex.y],
	]:
		var visual := get_node_or_null(node_name)

		if visual != null:
			remove_child(visual)
			visual.queue_free()


func clear() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()


func _render_state(hex: Vector2i, state_id: StringName) -> void:
	var texture := HexStateArt.texture(state_id)
	if texture == null:
		return
	var center := to_local(_terrain_layer.to_global(
		_terrain_layer.map_to_local(HexCoordinateMapper.axial_to_offset(hex))
	))
	var sprite := Sprite2D.new()
	sprite.name = "HexState_%d_%d" % [hex.x, hex.y]
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# Reference rim: 90 x 58 inside a projected 94 x 78 hex.
	sprite.scale = Vector2(56.0 * 90.0 / 94.0, 64.0 * 58.0 / 78.0) / texture.get_size()
	sprite.position = center + Vector2(0, -64.0 / 78.0)
	add_child(sprite)
	if ELECTRIC_SPARK_COLORS.has(state_id):
		var sparks := ElectricHexParticles.new()
		sparks.name = "ElectricSparks_%d_%d" % [hex.x, hex.y]
		sparks.position = center
		sparks.z_index = 1
		sparks.configure(hex, ELECTRIC_SPARK_COLORS[state_id])
		add_child(sparks)
