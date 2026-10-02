class_name UnitCombatAnimator
extends Node2D

## A single presentation clock owns the pose, projectile, impact and recovery.
const INK := Color("332d29")
const GOLD := Color("dca65c")
const LIGHT := Color("fff0c1")
var _source: Sprite2D
var _target: Sprite2D
var _source_rest: Transform2D
var _target_rest: Transform2D
var _target_color: Color
var _source_direction := Vector2.RIGHT
var _target_direction := Vector2.RIGHT
var _start := Vector2.ZERO
var _finish := Vector2.ZERO
var _ranged := false
var _hit_only := false
var _time := 0.0
var _contact := 0.22
var _flight := 0.16
var _restored := false


static func attack(attacker: UnitActor, target: UnitActor, ranged: bool, contact: Callable) -> Tween:
	var effect := UnitCombatAnimator.new()
	attacker.get_parent().add_child(effect)
	effect._ranged = ranged
	effect._source = attacker.get_combat_sprite()
	effect._source_rest = effect._source.transform
	effect._source_direction = attacker.to_local(target.global_position).normalized()
	effect._start = effect.to_local(attacker.get_combat_anchor(0.68 if ranged else 0.52))
	effect._prepare_target(target)
	effect._flight = clampf(effect._start.distance_to(effect._finish) / 1700.0, 0.08, 0.24)
	effect._contact = 0.14 + effect._flight if ranged else 0.22
	return effect._play(contact)


static func hit(target: UnitActor, contact: Callable) -> Tween:
	var effect := UnitCombatAnimator.new()
	target.get_parent().add_child(effect)
	effect._hit_only = true
	effect._contact = 0.0
	effect._prepare_target(target)
	effect._start = effect._finish - Vector2(30, 0)
	effect._target_direction = Vector2.RIGHT
	return effect._play(contact)


func _prepare_target(target: UnitActor) -> void:
	name = "CombatAnimation"
	z_index = 55
	_target = target.get_combat_sprite()
	_target_rest = _target.transform
	_target_color = _target.modulate
	_finish = to_local(target.get_combat_anchor())
	_target_direction = (target.to_local(to_global(_finish)) - target.to_local(to_global(_start))).normalized()


func _play(contact: Callable) -> Tween:
	var tween := create_tween()
	if _contact > 0.0:
		tween.tween_method(_sample, 0.0, _contact, _contact)
	tween.tween_callback(contact)
	tween.tween_method(_sample, _contact, _contact + 0.30, 0.30)
	tween.tween_callback(_restore)
	# Free on the next frame so the queue can receive this tween's finished signal.
	tween.finished.connect(queue_free)
	return tween


func _sample(time: float) -> void:
	_time = time
	if is_instance_valid(_source):
		var offset := 0.0
		var lean := 0.0
		if _ranged:
			if time < 0.14:
				lean = smoothstep(0.0, 0.14, time) * 0.035
			else:
				var recoil := exp(-(time - 0.14) * 16.0)
				offset = -7.0 * recoil
				lean = -0.07 * recoil
		else:
			if time < 0.13:
				var windup := smoothstep(0.0, 0.13, time)
				offset = -7.0 * windup
				lean = -0.10 * windup
			elif time < _contact:
				var strike := pow((time - 0.13) / (_contact - 0.13), 2.0)
				offset = lerpf(-7.0, 22.0, strike)
				lean = lerpf(-0.10, 0.18, strike)
			else:
				var recovery := 1.0 - smoothstep(_contact + 0.035, _contact + 0.30, time)
				offset = 22.0 * recovery
				lean = 0.18 * recovery
		_source.transform = _source_rest
		_source.position += _source_direction * offset
		_source.rotation += lean * _source_direction.x
	if time >= _contact and is_instance_valid(_target):
		var elapsed := time - _contact
		var kick := sin(minf(elapsed / 0.07, 1.0) * PI * 0.5) * exp(-elapsed * 12.0)
		_target.transform = _target_rest
		_target.position += _target_direction * kick * 9.0
		_target.rotation += _target_direction.x * kick * 0.09
		_target.modulate = _target_color.lerp(Color(1.5, 1.25, 0.85), maxf(0.0, 1.0 - elapsed / 0.10) * 0.8)
	queue_redraw()


func _restore() -> void:
	if _restored:
		return
	_restored = true
	if is_instance_valid(_source):
		_source.transform = _source_rest
	if is_instance_valid(_target):
		_target.transform = _target_rest
		_target.modulate = _target_color


func _exit_tree() -> void:
	_restore()


func _draw() -> void:
	var direction := (_finish - _start).normalized()
	var normal := direction.orthogonal()
	if _ranged and _time >= 0.14 and _time < _contact:
		var travel := clampf((_time - 0.14) / _flight, 0.0, 1.0)
		var muzzle := _start + direction * 24.0
		var head := muzzle.lerp(_finish, travel)
		var tail := head - direction * minf(32.0, muzzle.distance_to(head))
		draw_line(tail, head, Color(GOLD, 0.24), 8.0, true)
		draw_line(tail, head, LIGHT, 2.4, true)
		var flash := maxf(0.0, 1.0 - (_time - 0.14) / 0.065)
		if flash > 0.0:
			draw_colored_polygon(PackedVector2Array([
				muzzle - direction * 5.0, muzzle + normal * 8.0 * flash,
				muzzle + direction * 28.0 * flash, muzzle - normal * 8.0 * flash,
			]), Color(LIGHT, flash))
	if not _ranged and not _hit_only and _time > 0.15 and _time < _contact + 0.10:
		var sweep := clampf((_time - 0.15) / 0.12, 0.0, 1.0)
		var arc := PackedVector2Array()
		var center := _finish - direction * 14.0
		for i in range(19):
			var angle := direction.angle() - 1.25 + sweep * 0.65 + float(i) / 18.0 * 1.5
			arc.append(center + Vector2.from_angle(angle) * 29.0)
		var alpha := minf(1.0, (_contact + 0.10 - _time) / 0.08)
		draw_polyline(arc, Color(INK, alpha * 0.6), 8.0, true)
		draw_polyline(arc, Color(LIGHT, alpha), 3.0, true)
	if _time >= _contact:
		var age := (_time - _contact) / 0.30
		var fade := pow(1.0 - clampf(age, 0.0, 1.0), 2.0)
		for i in range(9):
			var ray := Vector2.from_angle(float(i) * 2.399 + direction.angle())
			var distance := (8.0 + age * (35.0 + (i % 3) * 10.0))
			var point := _finish + ray * distance + Vector2(0, age * age * 16.0)
			draw_line(point - ray * (3.0 + fade * 7.0), point, Color(GOLD if i % 2 else LIGHT, fade), 2.0, true)
		if age < 0.22:
			draw_circle(_finish, 6.0 * (1.0 - age / 0.22), Color(LIGHT, fade))
