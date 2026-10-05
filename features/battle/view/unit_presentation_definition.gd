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


## Alpha bounds per texture instance. Content snapshots hand out copies of this
## resource, so a per-copy cache would re-read the texture from the GPU on every lookup.
static var _alpha_bounds_by_texture: Dictionary[int, Rect2] = {}


static func _alpha_bounds(texture: Texture2D) -> Rect2:
	if texture == null:
		return Rect2()
	var key := texture.get_instance_id()
	if _alpha_bounds_by_texture.has(key):
		return _alpha_bounds_by_texture[key]
	var bounds := Rect2()
	var image := texture.get_image()
	if image != null and not image.is_empty():
		bounds = Rect2(image.get_used_rect())
	if not bounds.has_area():
		bounds = Rect2(Vector2.ZERO, texture.get_size())
	_alpha_bounds_by_texture[key] = bounds
	return bounds


func visible_rect() -> Rect2:
	return _alpha_bounds(actor_texture)


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


func corpse_visible_rect() -> Rect2:
	if corpse_visible_region.has_area():
		return corpse_visible_region
	return _alpha_bounds(corpse_texture)
