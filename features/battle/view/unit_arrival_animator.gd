class_name UnitArrivalAnimator
extends Node2D
## A unit falling from the sky onto its hex: the figure drops with a fiery streak while its shadow
## grows on the hex, then lands with a flash, a shock ring and dust. One playback-scaled clock;
## presentation only, the unit already stands on its hex in the battle state.

const DROP_HEIGHT := 640.0
const FALL := 0.62
const IMPACT := 0.42

var _sprite: Sprite2D
var _rest_position: Vector2
var _rest_scale: Vector2
var _height := 80.0
var _time := 0.0


static func create(actor: UnitActor, sprite: Sprite2D, height: float) -> Tween:
	var animator := UnitArrivalAnimator.new()
	animator.name = "ArrivalAnimation"
	actor.add_child(animator)
	# Drawn before the figure: the shadow and dust stay under it, the streak trails above it.
	actor.move_child(animator, 0)
	animator._sprite = sprite
	animator._rest_position = sprite.position
	animator._rest_scale = sprite.scale
	animator._height = height
	animator._sample(0.0)
	var tween := animator.create_tween()
	tween.tween_method(animator._sample, 0.0, FALL + IMPACT, FALL + IMPACT)
	tween.tween_callback(actor.finish_arrival)
	tween.finished.connect(animator.queue_free)
	return tween


## Puts the figure back at rest, as after a completed landing.
func restore() -> void:
	_sprite.position = _rest_position
	_sprite.scale = _rest_scale


func _sample(time: float) -> void:
	_time = time
	var fall := clampf(time / FALL, 0.0, 1.0)
	# Accelerates all the way down, as a falling body does.
	_sprite.position = _rest_position + Vector2(0.0, -DROP_HEIGHT * (1.0 - fall * fall))
	_sprite.scale = _rest_scale
	if time > FALL:
		var impact := clampf((time - FALL) / IMPACT, 0.0, 1.0)
		var squash := sin(impact * PI) * (1.0 - impact) * 0.22
		_sprite.scale = _rest_scale * Vector2(1.0 + squash, 1.0 - squash)
	queue_redraw()


func _draw() -> void:
	var fall := clampf(_time / FALL, 0.0, 1.0)
	# The shadow sharpens as the capsule nears the ground.
	_draw_ellipse(Vector2.ZERO, Vector2(10.0 + 20.0 * fall, 3.0 + 7.0 * fall), Color(0.05, 0.03, 0.02, 0.12 + 0.30 * fall))
	if _time < FALL:
		var top := _sprite.position.y - _height
		var length := 70.0 + 150.0 * fall
		for i in range(6):
			var t := float(i) / 6.0
			var center := Vector2(0.0, top - length * t)
			var color := Color(1.0, 0.86 - 0.5 * t, 0.45 - 0.4 * t, (0.55 - 0.08 * i) * (0.4 + 0.6 * fall))
			draw_circle(center, 11.0 * (1.0 - t * 0.7), color)
		return
	var impact := clampf((_time - FALL) / IMPACT, 0.0, 1.0)
	var fade := 1.0 - impact
	draw_circle(Vector2(0.0, -8.0), 26.0 * (1.0 - impact * 0.5), Color(1.0, 0.95, 0.75, 0.45 * fade * fade))
	_draw_ring(Vector2.ZERO, Vector2(18.0 + 46.0 * impact, 6.0 + 15.0 * impact), Color(0.95, 0.88, 0.66, 0.75 * fade), 3.0)
	for i in range(9):
		var angle := float(i) * 2.399
		var point := Vector2(cos(angle) * (14.0 + impact * 34.0), sin(angle) * (4.0 + impact * 9.0) - impact * 6.0)
		draw_circle(point, 3.0 + impact * 6.0, Color(0.52, 0.46, 0.36, 0.30 * fade))


func _draw_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(32):
		var angle := TAU * float(i) / 32.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)


func _draw_ring(center: Vector2, radius: Vector2, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in range(33):
		var angle := TAU * float(i) / 32.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_polyline(points, color, width, true)
