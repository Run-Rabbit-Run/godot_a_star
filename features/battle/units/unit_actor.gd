class_name UnitActor
extends Node2D


const CUSTOM_TEXTURE_SIZE := 82.0


@export_range(0.01, 1.0, 0.01)
var movement_step_duration := 0.28

@export_range(0.01, 1.0, 0.01)
var damage_flash_duration := 0.18

var unit_id: StringName
var _faction_color := Color(0.51, 0.66, 0.75)
var _show_base := true
var _movement_profile: UnitMovementProfile
var _movement_animator: UnitMovementAnimator

@onready var _sprite: Sprite2D = %Sprite
@onready var _unit_id_label: Label = %UnitIdLabel
@onready var _combat_role_label: Label = %CombatRoleLabel
@onready var _health_label: Label = %HealthLabel


func _draw() -> void:
	if not _show_base:
		return

	var base_points := PackedVector2Array()
	for i in range(49):
		var angle := TAU * float(i) / 48.0
		base_points.append(Vector2(cos(angle) * 29.0, sin(angle) * 11.0))
	draw_colored_polygon(base_points, Color(0.0, 0.0, 0.0, 0.25))
	draw_polyline(base_points, _faction_color, 1.5, true)

func setup(
	p_unit_id: StringName,
	definition: UnitDefinition,
	presentation: UnitPresentationDefinition,
	faction: BattleFaction.Value,
	current_health: int,
	maximum_health: int
) -> void:
	unit_id = p_unit_id
	_movement_profile = presentation.movement_profile if presentation != null else null
	if _movement_profile == null:
		_movement_profile = UnitMovementProfile.new()
		_movement_profile.seconds_per_hex = movement_step_duration
	_faction_color = (
		Color(0.52, 0.69, 0.82)
		if faction == BattleFaction.Value.PLAYER
		else Color(0.77, 0.29, 0.22)
	)
	_show_base = true
	queue_redraw()
	_unit_id_label.text = definition.display_name
	_unit_id_label.visible = false

	if presentation != null and presentation.actor_texture != null:
		_sprite.texture = presentation.actor_texture
		_sprite.material = null
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var texture_size := presentation.actor_texture.get_size()
		var longest_side := maxf(texture_size.x, texture_size.y)

		if longest_side > 0.0:
			_sprite.scale = Vector2.ONE * (
				presentation.actor_height / texture_size.y
			)
			# The actor origin is the hex center; align the painted feet to it.
			_sprite.offset = (
				Vector2.ONE * 0.5 - presentation.actor_foot_anchor
			) * texture_size

	_combat_role_label.visible = false
	var figure_height := presentation.actor_height if presentation != null else CUSTOM_TEXTURE_SIZE
	_health_label.position = Vector2(-36, -figure_height - 29)
	_health_label.size = Vector2(72, 23)
	_combat_role_label.text = "◎"
	show_health(current_health, maximum_health)
	modulate = (
		presentation.actor_color if presentation != null else Color.WHITE
	)


func show_health(current: int, maximum: int) -> void:
	_health_label.text = "%d / %d" % [maxi(current, 0), maximum]
	_health_label.visible = current > 0
	var ratio := 0.0 if maximum <= 0 else float(current) / float(maximum)
	var badge_color := Color(0.07, 0.10, 0.09, 0.94)

	if ratio <= 0.33:
		badge_color = Color(0.20, 0.08, 0.07, 0.94)
	elif ratio <= 0.66:
		badge_color = Color(0.12, 0.11, 0.08, 0.94)

	var style := StyleBoxFlat.new()
	style.bg_color = badge_color
	style.border_color = badge_color.lightened(0.12)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	_health_label.add_theme_stylebox_override("normal", style)

func present_damage() -> void:
	if not visible:
		return

	var base_color := modulate
	var hit_color := base_color.lerp(Color.RED, 0.7)
	var tween := create_tween()
	tween.tween_property(
		self,
		"modulate",
		hit_color,
		damage_flash_duration * 0.5
	)
	tween.tween_property(
		self,
		"modulate",
		base_color,
		damage_flash_duration * 0.5
	)
	await tween.finished


func present_defeat() -> void:
	_show_base = false
	queue_redraw()
	z_index = 8
	rotation_degrees = -82.0
	modulate = modulate.lerp(Color(0.22, 0.21, 0.19, 0.72), 0.78)
	_combat_role_label.visible = false
	_health_label.visible = false
	_unit_id_label.visible = false


func move_along_global_positions(
	positions: Array[Vector2]
) -> void:
	var tween := create_movement_tween(positions)
	if tween != null:
		await tween.finished


func create_movement_tween(positions: Array[Vector2]) -> Tween:
	_movement_animator = UnitMovementAnimator.new()
	return _movement_animator.create_motion(self, _sprite, positions, _movement_profile)


func get_combat_sprite() -> Sprite2D:
	return _sprite


func get_combat_anchor(height_ratio: float = 0.52) -> Vector2:
	var height := _sprite.texture.get_height() * _sprite.scale.y if _sprite.texture != null else CUSTOM_TEXTURE_SIZE
	return to_global(Vector2(0, -height * height_ratio))
