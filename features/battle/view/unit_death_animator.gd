class_name UnitDeathAnimator
extends Node2D

## Temporary dust and one playback-scaled clock; the corpse belongs to UnitActor.
var _sprite: Sprite2D
var _corpse: Sprite2D
var _rest: Transform2D
var _color: Color
var _corpse_scale: Vector2
var _direction := 1.0
var _time := 0.0


static func create(actor: UnitActor, sprite: Sprite2D, corpse: Sprite2D, direction: float) -> Tween:
	var animator := UnitDeathAnimator.new()
	actor.add_child(animator)
	animator.name = "DeathAnimation"
	animator._sprite = sprite
	animator._corpse = corpse
	animator._rest = sprite.transform
	animator._color = sprite.modulate
	animator._corpse_scale = corpse.scale
	animator._direction = direction
	var tween := animator.create_tween()
	tween.tween_method(animator._sample, 0.0, 0.68, 0.68)
	tween.tween_callback(actor.finish_defeat)
	tween.finished.connect(animator.queue_free)
	return tween


func _sample(time: float) -> void:
	_time = time
	var buckle := smoothstep(0.0, 0.12, time)
	var fall := smoothstep(0.10, 0.36, time)
	var landing := smoothstep(0.24, 0.38, time)
	_sprite.transform = _rest
	_sprite.position += Vector2(_direction * 9.0 * fall, 3.0 * buckle)
	_sprite.rotation += _direction * (0.08 * buckle + 0.55 * fall)
	_sprite.scale *= Vector2(1.0 + fall * 0.12, 1.0 - fall * 0.76)
	_sprite.modulate = _color.lerp(Color(0.55, 0.51, 0.45), fall * 0.5)
	_sprite.modulate.a = _color.a * (1.0 - landing)
	_corpse.modulate.a = landing
	var settle := sin(clampf((time - 0.24) / 0.22, 0.0, 1.0) * PI)
	_corpse.scale = _corpse_scale * Vector2(1.0 + settle * 0.045, 1.0 - settle * 0.07)
	queue_redraw()


func _draw() -> void:
	if _time < 0.25:
		return
	var age := clampf((_time - 0.25) / 0.43, 0.0, 1.0)
	var opacity := sin(age * PI) * (1.0 - age) * 0.17
	for i in range(7):
		var angle := float(i) * 2.399
		var point := Vector2(cos(angle) * (16.0 + age * 21.0), sin(angle) * (5.0 + age * 6.0) - age * 4.0)
		draw_circle(point, 3.0 + age * 5.0, Color(0.49, 0.44, 0.35, opacity))
