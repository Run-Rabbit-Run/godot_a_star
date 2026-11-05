class_name ObstacleArt
extends RefCounted
## Presentation-only atlas regions preserve the source PNGs and their alpha. Flasks are vector
## art (tools/art/generate_flask_art.py), one picture per type and contents.

const FLASKS := "res://features/battle/art/obstacles/flasks/"
const SOURCES: Dictionary = {
	&"hill": preload("res://features/battle/art/obstacles/hill-v1.png"),
	&"river": preload("res://features/battle/art/obstacles/river-v1.png"),
	&"puddle": preload("res://features/battle/art/obstacles/puddle-v1.png"),
	&"trees": preload("res://features/battle/art/obstacles/trees-v1.png"),
	&"rocks": preload("res://features/battle/art/obstacles/rocks-v1.png"),
	&"flask_acid": preload(FLASKS + "flask_acid.svg"),
	&"flask_water": preload(FLASKS + "flask_water.svg"),
	&"flask_oil": preload(FLASKS + "flask_oil.svg"),
	&"flask_electricity": preload(FLASKS + "flask_electricity.svg"),
	&"big_flask_acid": preload(FLASKS + "big_flask_acid.svg"),
	&"big_flask_water": preload(FLASKS + "big_flask_water.svg"),
	&"big_flask_oil": preload(FLASKS + "big_flask_oil.svg"),
	&"big_flask_electricity": preload(FLASKS + "big_flask_electricity.svg"),
	&"pressure_flask": preload(FLASKS + "pressure_flask.svg"),
	&"explosive_flask": preload(FLASKS + "explosive_flask.svg"),
}
## Visible parts of the painted sources; a picture without a region is used whole.
const REGIONS: Dictionary = {
	&"hill": Rect2(0.0, 76.0, 1522.0, 871.0),
	&"river": Rect2(0.0, 112.0, 1758.0, 663.0),
	&"puddle": Rect2(0.0, 7.0, 1528.0, 1009.0),
	&"trees": Rect2(5.0, 15.0, 1512.0, 1009.0),
	&"rocks": Rect2(23.0, 102.0, 1493.0, 828.0),
}
## Drawn width on the 94 px hex and the share of the height above the hex center, by type.
const WIDTHS: Dictionary = {
	&"hill": 94.0, &"river": 112.0, &"puddle": 90.0, &"trees": 96.0, &"rocks": 88.0,
	&"flask": 52.0, &"big_flask": 76.0, &"pressure_flask": 56.0, &"explosive_flask": 54.0,
}
const ANCHORS: Dictionary = {
	&"hill": 0.65, &"river": 0.5, &"puddle": 0.5, &"trees": 0.85, &"rocks": 0.75,
	&"flask": 0.9, &"big_flask": 0.9, &"pressure_flask": 0.9, &"explosive_flask": 0.9,
}
static var _textures: Dictionary[StringName, AtlasTexture] = {}


## The picture of an obstacle: spilling flasks have one per contents.
static func art_id(obstacle: BattleObstacleDefinition) -> StringName:
	if BattleObstacleDefinition.SPILL_TYPES.has(obstacle.terrain_type):
		return StringName("%s_%s" % [obstacle.terrain_type, String(obstacle.contents).trim_prefix("core:")])
	return obstacle.terrain_type


static func texture(id: StringName) -> AtlasTexture:
	if not _textures.has(id):
		var atlas := AtlasTexture.new()
		atlas.atlas = SOURCES[id]
		atlas.region = REGIONS.get(id, Rect2(Vector2.ZERO, atlas.atlas.get_size()))
		_textures[id] = atlas
	return _textures[id]

static func draw(canvas: CanvasItem, center: Vector2, obstacle: BattleObstacleDefinition, hex: Vector2i) -> void:
	var sprite := texture(art_id(obstacle))
	var width: float = WIDTHS[obstacle.terrain_type]
	var dimensions := sprite.get_size() * (width / sprite.get_width())
	var angle := 0.0
	if obstacle.terrain_type == &"river" and obstacle.hexes.size() > 1:
		var direction := obstacle.hexes[1] - obstacle.hexes[0]
		angle = Vector2(94.0 * (direction.x + direction.y * 0.5), 58.5 * direction.y).angle()
	canvas.draw_set_transform(center, angle)
	canvas.draw_texture_rect(sprite, Rect2(Vector2(-dimensions.x * 0.5, -dimensions.y * float(ANCHORS[obstacle.terrain_type])), dimensions), false)
	canvas.draw_set_transform(Vector2.ZERO)
	# One badge for the shared health of the whole footprint.
	if hex == obstacle.hexes[0] and obstacle.destructible:
		canvas.draw_style_box(_badge(), Rect2(center + Vector2(-32, 25), Vector2(64, 19)))
		canvas.draw_string(ThemeDB.fallback_font, center + Vector2(-29, 39), "%d/%d" % [obstacle.current_hp, obstacle.max_hp], HORIZONTAL_ALIGNMENT_CENTER, 58, 12, Color("eee4bb"))

static func _badge() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.055, 0.9)
	style.set_corner_radius_all(4)
	return style
