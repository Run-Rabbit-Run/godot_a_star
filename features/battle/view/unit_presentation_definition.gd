class_name UnitPresentationDefinition
extends Resource


@export var id: StringName
@export var actor_scene: PackedScene
@export var actor_texture: Texture2D
@export var portrait_texture: Texture2D
## Height of the visible silhouette, excluding transparent canvas padding.
@export var actor_height := 82.0
@export var actor_max_width := 120.0
@export var actor_foot_anchor := Vector2(0.5, 1.0)
@export var actor_color := Color.WHITE
@export var movement_profile: UnitMovementProfile
@export var corpse_texture: Texture2D
## Optional measured body bounds, excluding nearly transparent generator residue.
@export var corpse_visible_region := Rect2()
@export_range(24.0, 120.0, 1.0) var corpse_width := 76.0


var _measured_texture: Texture2D
var _visible_rect := Rect2()


func visible_rect() -> Rect2:
	if actor_texture != _measured_texture:
		_measured_texture = actor_texture
		_visible_rect = Rect2()
		if actor_texture != null:
			var image := actor_texture.get_image()
			if image != null and not image.is_empty():
				_visible_rect = Rect2(image.get_used_rect())
			if not _visible_rect.has_area():
				_visible_rect = Rect2(Vector2.ZERO, actor_texture.get_size())
	return _visible_rect


func texture_scale() -> float:
	var bounds := visible_rect()
	if not bounds.has_area():
		return 1.0
	return minf(actor_height / bounds.size.y, actor_max_width / bounds.size.x)


func height_above_feet() -> float:
	if actor_texture == null:
		return actor_height
	return maxf(0.0, actor_foot_anchor.y * actor_texture.get_height() - visible_rect().position.y) * texture_scale()


func align_to_visible_feet() -> void:
	if actor_texture == null:
		return
	var bounds := visible_rect()
	actor_foot_anchor = Vector2(bounds.get_center().x, bounds.end.y) / actor_texture.get_size()


var _measured_corpse: Texture2D
var _corpse_rect := Rect2()


func corpse_visible_rect() -> Rect2:
	if corpse_visible_region.has_area():
		return corpse_visible_region
	if corpse_texture != _measured_corpse:
		_measured_corpse = corpse_texture
		_corpse_rect = Rect2()
		if corpse_texture != null:
			var image := corpse_texture.get_image()
			if image != null and not image.is_empty():
				_corpse_rect = Rect2(image.get_used_rect())
			if not _corpse_rect.has_area():
				_corpse_rect = Rect2(Vector2.ZERO, corpse_texture.get_size())
	return _corpse_rect
