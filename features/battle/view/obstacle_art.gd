class_name ObstacleArt
extends RefCounted
## Presentation-only atlas regions preserve the source PNGs and their alpha.

const SOURCES: Dictionary = {
	&"hill": preload("res://features/battle/art/obstacles/hill-v1.png"),
	&"river": preload("res://features/battle/art/obstacles/river-v1.png"),
	&"puddle": preload("res://features/battle/art/obstacles/puddle-v1.png"),
	&"trees": preload("res://features/battle/art/obstacles/trees-v1.png"),
	&"rocks": preload("res://features/battle/art/obstacles/rocks-v1.png"),
}
const REGIONS: Dictionary = {
	&"hill": Rect2(29, 172, 1488, 722),
	&"river": Rect2(46, 161, 1684, 603),
	&"puddle": Rect2(39, 37, 1459, 938),
	&"trees": Rect2(111, 35, 1301, 931),
	&"rocks": Rect2(51, 148, 1432, 762),
}
const WIDTHS: Dictionary = {&"hill": 94.0, &"river": 112.0, &"puddle": 90.0, &"trees": 96.0, &"rocks": 88.0}
const ANCHORS: Dictionary = {&"hill": 0.65, &"river": 0.5, &"puddle": 0.5, &"trees": 0.85, &"rocks": 0.75}
static var _textures: Dictionary[StringName, AtlasTexture] = {}

static func texture(id: StringName) -> AtlasTexture:
	if not _textures.has(id):
		var atlas := AtlasTexture.new()
		atlas.atlas = SOURCES[id]
		atlas.region = REGIONS[id]
		_textures[id] = atlas
	return _textures[id]

static func draw(canvas: CanvasItem, center: Vector2, obstacle: BattleObstacleDefinition, hex: Vector2i) -> void:
	var sprite := texture(obstacle.terrain_type)
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
