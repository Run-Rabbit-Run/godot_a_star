class_name UnitActor
extends Node2D


const CUSTOM_TEXTURE_SIZE := 72.0


@export_range(0.01, 1.0, 0.01)
var movement_step_duration := 0.12

@export_range(0.01, 1.0, 0.01)
var damage_flash_duration := 0.18

var unit_id: StringName

@onready var _sprite: Sprite2D = %Sprite
@onready var _unit_id_label: Label = %UnitIdLabel
@onready var _combat_role_label: Label = %CombatRoleLabel


func setup(
	p_unit_id: StringName,
	definition: UnitDefinition
) -> void:
	unit_id = p_unit_id
	_unit_id_label.text = definition.display_name
	_unit_id_label.visible = false

	if definition.actor_texture != null:
		_sprite.texture = definition.actor_texture
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
	_combat_role_label.text = "◎ ДАЛЬН."
	modulate = definition.actor_color


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
	z_index = 8
	rotation_degrees = -82.0
	modulate = modulate.lerp(Color(0.22, 0.21, 0.19, 0.72), 0.78)
	_combat_role_label.visible = false
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
