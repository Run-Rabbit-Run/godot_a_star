class_name UnitActor
extends Node2D


const CUSTOM_TEXTURE_SIZE := 82.0
const READABILITY_SHADER := preload("res://features/battle/units/art/unit_readability.gdshader")


@export_range(0.01, 1.0, 0.01)
var movement_step_duration := 0.12

@export_range(0.01, 1.0, 0.01)
var damage_flash_duration := 0.18

var unit_id: StringName
var _faction_color := Color(0.51, 0.66, 0.75)
var _show_base := true

@onready var _sprite: Sprite2D = %Sprite
@onready var _unit_id_label: Label = %UnitIdLabel
@onready var _combat_role_label: Label = %CombatRoleLabel
@onready var _health_label: Label = %HealthLabel


func _draw() -> void:
	if not _show_base:
		return

	var base_points := PackedVector2Array([
		Vector2(0, -6),
		Vector2(22, 1),
		Vector2(22, 13),
		Vector2(0, 20),
		Vector2(-22, 13),
		Vector2(-22, 1),
	])
	var outline := base_points.duplicate()
	outline.append(base_points[0])
	draw_colored_polygon(base_points, Color(0.08, 0.09, 0.08, 0.28))
	draw_polyline(outline, Color(0.06, 0.07, 0.07, 0.62), 3.2, true)
	draw_polyline(outline, _faction_color, 1.35, true)

func setup(
	p_unit_id: StringName,
	definition: UnitDefinition,
	faction: BattleFaction.Value,
	current_health: int,
	maximum_health: int
) -> void:
	unit_id = p_unit_id
	_faction_color = (
		Color(0.52, 0.69, 0.82)
		if faction == BattleFaction.Value.PLAYER
		else Color(0.77, 0.29, 0.22)
	)
	_show_base = true
	queue_redraw()
	_unit_id_label.text = definition.display_name
	_unit_id_label.visible = false

	if definition.actor_texture != null:
		_sprite.texture = definition.actor_texture
		var rim_material := ShaderMaterial.new()
		rim_material.shader = READABILITY_SHADER
		rim_material.set_shader_parameter(
			"rim_color",
			Color(0.075, 0.082, 0.075, 0.74)
		)
		_sprite.material = rim_material
		var texture_size := definition.actor_texture.get_size()
		var longest_side := maxf(texture_size.x, texture_size.y)

		if longest_side > 0.0:
			_sprite.scale = Vector2.ONE * (
				CUSTOM_TEXTURE_SIZE / longest_side
			)
			# The actor origin is the hex center; align the painted feet to it.
			_sprite.offset = (
				Vector2.ONE * 0.5 - definition.actor_foot_anchor
			) * texture_size

	_combat_role_label.visible = (
		definition.base_stats != null
		and definition.base_stats.basic_attack_range > 1
	)
	_combat_role_label.text = "◎"
	show_health(current_health, maximum_health)
	modulate = definition.actor_color


func show_health(current: int, maximum: int) -> void:
	_health_label.text = str(maxi(current, 0))
	_health_label.visible = current > 0
	var ratio := 0.0 if maximum <= 0 else float(current) / float(maximum)
	var badge_color := Color(0.30, 0.36, 0.27, 0.92)

	if ratio <= 0.33:
		badge_color = Color(0.38, 0.12, 0.11, 0.94)
	elif ratio <= 0.66:
		badge_color = Color(0.48, 0.34, 0.17, 0.93)

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
	for target_position: Vector2 in positions:
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_SINE)
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(
			self,
			"global_position",
			target_position,
			movement_step_duration
		)
		await tween.finished
