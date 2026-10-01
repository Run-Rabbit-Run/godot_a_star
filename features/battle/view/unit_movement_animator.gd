class_name UnitMovementAnimator
extends RefCounted

const WALK_SHADER := preload("res://features/battle/art/movement/walk.gdshader")

var _actor: Node2D
var _sprite: Sprite2D
var _profile: UnitMovementProfile
var _points: Array[Vector2] = []
var _distances: Array[float] = [0.0]
var _length := 0.0
var _rest_position: Vector2
var _rest_rotation: float
var _rest_material: Material
var _material: ShaderMaterial


## One tween owns both travel and gait so live speed changes cannot desynchronise them.
func create_motion(
	actor: Node2D, sprite: Sprite2D, destinations: Array[Vector2],
	profile: UnitMovementProfile
) -> Tween:
	_actor = actor
	_sprite = sprite
	_profile = profile
	_points = [actor.global_position]
	for destination: Vector2 in destinations:
		var distance: float = _points.back().distance_to(destination)
		if distance > 0.001:
			_length += distance
			_points.append(destination)
			_distances.append(_length)
	if _points.size() < 2:
		return null

	_rest_position = sprite.position
	_rest_rotation = sprite.rotation
	_rest_material = sprite.material
	_material = ShaderMaterial.new()
	_material.shader = WALK_SHADER
	_material.set_shader_parameter("stride", profile.stride)
	_material.set_shader_parameter("leg_start", profile.leg_start)
	_material.set_shader_parameter("leg_split", profile.leg_split)
	# Custom actor materials keep their own rendering; transform gait still applies.
	if _rest_material == null:
		sprite.material = _material
	var tween := actor.create_tween()
	var duration := maxf(profile.seconds_per_hex, 0.05) * (_points.size() - 1)
	tween.tween_method(_sample, 0.0, 1.0, duration)
	tween.tween_callback(_finish)
	return tween


func _sample(progress: float) -> void:
	# Short acceleration/deceleration at the route ends, constant speed between hexes.
	const RAMP := 0.15
	var travel := progress
	if progress < RAMP:
		travel = progress * progress / (2.0 * RAMP)
	elif progress > 1.0 - RAMP:
		travel = 1.0 - RAMP - pow(1.0 - progress, 2.0) / (2.0 * RAMP)
	else:
		travel = progress - RAMP * 0.5
	travel /= 1.0 - RAMP
	var distance := clampf(travel, 0.0, 1.0) * _length
	var segment := 0
	while segment < _points.size() - 2 and distance > _distances[segment + 1]:
		segment += 1
	var fraction := (distance - _distances[segment]) / (
		_distances[segment + 1] - _distances[segment]
	)
	_actor.global_position = _points[segment].lerp(_points[segment + 1], fraction)
	var phase := travel * (_points.size() - 1) * TAU
	var strength := smoothstep(0.0, 0.1, progress) * smoothstep(0.0, 0.1, 1.0 - progress)
	var direction := (_points[segment + 1] - _points[segment]).normalized()
	_sprite.position = _rest_position + Vector2(0.0, -absf(sin(phase)) * _profile.lift * strength)
	_sprite.rotation = _rest_rotation + deg_to_rad(
		(sin(phase) * _profile.sway_degrees + direction.x * _profile.lean_degrees) * strength
	)
	_material.set_shader_parameter("phase", phase)
	_material.set_shader_parameter("strength", strength)


func _finish() -> void:
	_actor.global_position = _points.back()
	_sprite.position = _rest_position
	_sprite.rotation = _rest_rotation
	_sprite.material = _rest_material
