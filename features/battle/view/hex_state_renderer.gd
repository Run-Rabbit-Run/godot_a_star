class_name HexStateRenderer
extends Node2D


const MANIFEST_PATH := "res://features/battle/art/hex_states/manifest.json"
const TEXTURES := {
	&"core:electricity": preload("res://features/battle/art/hex_states/01-electricity.png"),
	&"core:water": preload("res://features/battle/art/hex_states/02-water.png"),
	&"core:fire": preload("res://features/battle/art/hex_states/03-fire.png"),
	&"core:oil": preload("res://features/battle/art/hex_states/04-oil.png"),
	&"core:acid": preload("res://features/battle/art/hex_states/05-acid.png"),
	&"core:electrified_water": preload("res://features/battle/art/hex_states/06-electrified-water.png"),
	&"core:plasma": preload("res://features/battle/art/hex_states/07-plasma.png"),
	&"core:electrified_acid": preload("res://features/battle/art/hex_states/08-electrified-acid.png"),
	&"core:steam": preload("res://features/battle/art/hex_states/09-steam.png"),
	&"core:boiling_acid": preload("res://features/battle/art/hex_states/10-boiling-acid.png"),
	&"core:burning_oil": preload("res://features/battle/art/hex_states/11-burning-oil.png"),
	&"core:acid_vapour": preload("res://features/battle/art/hex_states/12-acid-vapour.png"),
}
const ASSET_IDS := {
	&"core:electricity": "01-electricity",
	&"core:water": "02-water",
	&"core:fire": "03-fire",
	&"core:oil": "04-oil",
	&"core:acid": "05-acid",
	&"core:electrified_water": "06-electrified-water",
	&"core:plasma": "07-plasma",
	&"core:electrified_acid": "08-electrified-acid",
	&"core:steam": "09-steam",
	&"core:boiling_acid": "10-boiling-acid",
	&"core:burning_oil": "11-burning-oil",
	&"core:acid_vapour": "12-acid-vapour",
}
const ELECTRIC_SPARK_COLORS := {
	&"core:electricity": Color(0.52, 0.87, 1.0),
	&"core:electrified_water": Color(0.46, 0.82, 1.0),
	&"core:electrified_acid": Color(0.70, 1.0, 0.54),
}


var _terrain_layer: TileMapLayer
var _placements: Dictionary = {}


func setup(terrain_layer: TileMapLayer) -> void:
	_terrain_layer = terrain_layer
	_load_placements()


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


func _load_placements() -> void:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)

	if file == null:
		push_warning("Hex state visual manifest could not be opened; state VFX are disabled.")
		return

	var manifest := JSON.parse_string(file.get_as_text()) as Dictionary

	if manifest == null:
		push_warning("Hex state visual manifest is invalid; state VFX are disabled.")
		return

	for item: Variant in manifest.get("assets", []):
		if item is not Dictionary:
			continue

		var entry := item as Dictionary
		_placements[String(entry.get("id", ""))] = entry


func _render_state(hex: Vector2i, state_id: StringName) -> void:
	var texture := TEXTURES.get(state_id) as Texture2D
	var asset_id := String(ASSET_IDS.get(state_id, ""))
	var placement := _placements.get(asset_id) as Dictionary

	if texture == null or placement == null:
		push_warning("Hex state visual is missing for %s." % state_id)
		return

	var anchor_values: Array = placement.get("anchor_px", [])

	if anchor_values.size() != 2:
		push_warning("Hex state anchor is invalid for %s." % state_id)
		return

	var sprite_scale := float(placement.get(
		"sprite_scale_for_local_hex_56x64",
		0.0
	))

	if sprite_scale <= 0.0:
		push_warning("Hex state scale is invalid for %s." % state_id)
		return

	var center := to_local(
		_terrain_layer.to_global(
			_terrain_layer.map_to_local(
				HexCoordinateMapper.axial_to_offset(hex)
			)
		)
	)
	var sprite := Sprite2D.new()
	sprite.name = "HexState_%d_%d" % [hex.x, hex.y]
	sprite.texture = texture
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.scale = Vector2.ONE * sprite_scale
	var anchor := Vector2(float(anchor_values[0]), float(anchor_values[1]))
	sprite.position = center - anchor * sprite_scale
	add_child(sprite)

	if ELECTRIC_SPARK_COLORS.has(state_id):
		var sparks := ElectricHexParticles.new()
		sparks.name = "ElectricSparks_%d_%d" % [hex.x, hex.y]
		sparks.position = center
		sparks.z_index = 1
		sparks.configure(hex, ELECTRIC_SPARK_COLORS[state_id])
		add_child(sparks)