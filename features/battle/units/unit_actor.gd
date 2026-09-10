class_name UnitActor
extends Node2D


@export_range(0.01, 1.0, 0.01)
var movement_step_duration := 0.12

@export_range(0.01, 1.0, 0.01)
var damage_flash_duration := 0.18

var unit_id: StringName

@onready var _unit_id_label: Label = %UnitIdLabel


func setup(
	p_unit_id: StringName,
	definition: UnitDefinition
) -> void:
	unit_id = p_unit_id
	_unit_id_label.text = String(p_unit_id)
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
	visible = false


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
