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
var _presentation: UnitPresentationDefinition
var _corpse: Sprite2D
var _defeat_tween: Tween
var _defeated := false

@onready var _sprite: Sprite2D = %Sprite
@onready var _unit_id_label: Label = %UnitIdLabel
@onready var _combat_role_label: Label = %CombatRoleLabel
@onready var _health_label: Label = %HealthLabel
@onready var _health_bar: ProgressBar = %HealthBar


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
	_presentation = presentation
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
				presentation.texture_scale()
			)
			# The actor origin is the hex center; align the painted feet to it.
			_sprite.offset = (
				Vector2.ONE * 0.5 - presentation.actor_foot_anchor
			) * texture_size

	_combat_role_label.visible = false
	_combat_role_label.text = "◎"
	show_health(current_health, maximum_health)
	modulate = (
		presentation.actor_color if presentation != null else Color.WHITE
	)


func show_health(current: int, maximum: int) -> void:
	_health_label.text = "%d/%d" % [maxi(current, 0), maximum]
	_health_bar.visible = current > 0 and not _defeated
	_health_bar.max_value = maxi(maximum, 1)
	_health_bar.value = clampi(current, 0, maxi(maximum, 1))
	# Fit large custom HP values without making every unit's badge wide.
	var badge_width := maxf(52.0, _health_label.get_minimum_size().x + 10.0)
	_health_bar.position = Vector2(-badge_width * 0.5, 13.0)
	_health_bar.size = Vector2(badge_width, 17.0)
	var ratio := 0.0 if maximum <= 0 else float(current) / float(maximum)
	var bar_color := Color(0.23, 0.48, 0.29)

	if ratio <= 0.33:
		bar_color = Color(0.65, 0.22, 0.17)
	elif ratio <= 0.66:
		bar_color = Color(0.58, 0.43, 0.18)

	var style := StyleBoxFlat.new()
	style.bg_color = bar_color
	style.set_corner_radius_all(2)
	_health_bar.add_theme_stylebox_override("fill", style)

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
	var tween := create_defeat_tween()
	if tween != null:
		await tween.finished


func create_defeat_tween(direction: float = 1.0) -> Tween:
	if _defeated:
		return _defeat_tween if _defeat_tween != null and _defeat_tween.is_running() else null
	_defeated = true
	_show_base = false
	queue_redraw()
	_combat_role_label.visible = false
	_health_bar.visible = false
	_health_label.visible = false
	_unit_id_label.visible = false
	_create_corpse()
	_defeat_tween = UnitDeathAnimator.create(self, _sprite, _corpse, direction)
	return _defeat_tween


func _create_corpse() -> void:
	_corpse = Sprite2D.new()
	_corpse.name = "Corpse"
	_corpse.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var width := _presentation.corpse_width if _presentation != null else 76.0
	if _presentation != null and _presentation.corpse_texture != null:
		_corpse.texture = _presentation.corpse_texture
		var bounds := _presentation.corpse_visible_rect()
		_corpse.scale = Vector2.ONE * width / maxf(bounds.size.x, 1.0)
		_corpse.offset = _corpse.texture.get_size() * 0.5 - bounds.get_center()
	else:
		# Optional presentation fallback for custom units without a painted corpse.
		_corpse.texture = _sprite.texture
		if _corpse.texture != null:
			_corpse.rotation = -PI * 0.5
			var bounds := _presentation.visible_rect() if _presentation != null else Rect2(Vector2.ZERO, _corpse.texture.get_size())
			_corpse.scale = Vector2(0.52, 1.0) * width / maxf(bounds.size.y, 1.0)
			_corpse.offset = _corpse.texture.get_size() * 0.5 - bounds.get_center()
	var material := ShaderMaterial.new()
	material.shader = preload("res://features/battle/art/corpse.gdshader")
	_corpse.material = material
	_corpse.position = Vector2(0, -3)
	_corpse.modulate.a = 0.0
	add_child(_corpse)


func finish_defeat() -> void:
	_sprite.hide()
	_corpse.modulate.a = 1.0
	# Below living units (20) and tactical overlays (8+), above terrain effects (5).
	z_index = 6


func is_presented_as_corpse() -> bool:
	return _defeated


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
	var height := _presentation.height_above_feet() if _presentation != null else CUSTOM_TEXTURE_SIZE
	return to_global(Vector2(0, -height * height_ratio))
