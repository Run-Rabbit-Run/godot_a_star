class_name HexStateRenderer
extends Node2D
## Artwork of both hex layers; electricity adds sparks tinted by the liquid it runs through.


const ELECTRIC_SPARK_COLORS := {
	&"": Color(0.52, 0.87, 1.0),
	&"core:water": Color(0.46, 0.82, 1.0),
	&"core:acid": Color(0.70, 1.0, 0.54),
}


var _terrain_layer: TileMapLayer


func setup(terrain_layer: TileMapLayer) -> void:
	_terrain_layer = terrain_layer


func render(grid: HexGrid) -> void:
	clear()

	if grid == null or _terrain_layer == null:
		return

	for hex: Vector2i in grid.get_cells():
		if grid.has_layers(hex):
			_render_layers(hex, grid.get_liquid(hex), grid.get_energy(hex))


func remove_hex(hex: Vector2i) -> void:
	for node_name in [
		"HexState_%d_%d_0" % [hex.x, hex.y],
		"HexState_%d_%d_1" % [hex.x, hex.y],
		"ElectricSparks_%d_%d" % [hex.x, hex.y],
	]:
		var visual := get_node_or_null(node_name)

		if visual != null:
			remove_child(visual)
			visual.queue_free()


func set_hex_layers(hex: Vector2i, liquid: StringName, energy: StringName) -> void:
	remove_hex(hex)
	_render_layers(hex, liquid, energy)


func clear() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()


func _render_layers(hex: Vector2i, liquid: StringName, energy: StringName) -> void:
	var center := to_local(_terrain_layer.to_global(
		_terrain_layer.map_to_local(HexCoordinateMapper.axial_to_offset(hex))
	))
	var art_ids := HexStateArt.art_ids(liquid, energy)
	for index in range(art_ids.size()):
		var texture := HexStateArt.texture(art_ids[index])
		if texture == null:
			continue
		var sprite := Sprite2D.new()
		sprite.name = "HexState_%d_%d_%d" % [hex.x, hex.y, index]
		sprite.texture = texture
		sprite.modulate = BattleVisualPalette.STATE_TINT
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		# Reference rim: 90 x 58 inside a projected 94 x 78 hex.
		sprite.scale = Vector2(56.0 * 90.0 / 94.0, 64.0 * 58.0 / 78.0) / texture.get_size()
		sprite.position = center + Vector2(0, -64.0 / 78.0)
		add_child(sprite)
	if energy == &"core:electricity":
		var sparks := ElectricHexParticles.new()
		sparks.name = "ElectricSparks_%d_%d" % [hex.x, hex.y]
		sparks.position = center
		sparks.z_index = 1
		sparks.configure(hex, ELECTRIC_SPARK_COLORS.get(liquid, ELECTRIC_SPARK_COLORS[&""]))
		add_child(sparks)
