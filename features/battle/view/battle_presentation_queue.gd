class_name BattlePresentationQueue
extends Node


var settings := BattlePlaybackSettings.new()
var _active_tweens: Array[Tween] = []


func _ready() -> void:
	settings.speed_changed.connect(_on_speed_changed)


func set_speed(value: float) -> bool:
	return settings.set_speed(value)


func present(
	resolution: BattleResolution,
	unit_actors: Dictionary[StringName, UnitActor],
	unit_definitions: Dictionary[StringName, UnitDefinition],
	map_view: BattleMapView,
	hud: BattleHUD
) -> bool:
	if resolution == null or not resolution.accepted:
		return false

	for event: BattleEvent in resolution.events:
		var was_presented := await _present_event(
			event,
			unit_actors,
			unit_definitions,
			map_view,
			hud
		)

		if not was_presented:
			return false

	return true


func _present_event(
	event: BattleEvent,
	unit_actors: Dictionary[StringName, UnitActor],
	unit_definitions: Dictionary[StringName, UnitDefinition],
	map_view: BattleMapView,
	hud: BattleHUD
) -> bool:
	if event is UnitMovedEvent:
		return await _present_move(
			event as UnitMovedEvent,
			unit_actors,
			map_view
		)

	if event is UnitDamagedEvent:
		return await _present_damage(
			event as UnitDamagedEvent,
			unit_actors,
			unit_definitions,
			map_view,
			hud
		)

	if event is TurnEndedEvent or event is AbilityUsedEvent:
		return true

	if event is MapMutationEvent:
		map_view.apply_map_event(event as MapMutationEvent)
		return true

	push_error("Unsupported BattleEvent in presentation queue.")
	return false


func _present_move(
	event: UnitMovedEvent,
	unit_actors: Dictionary[StringName, UnitActor],
	map_view: BattleMapView
) -> bool:
	var actor := unit_actors.get(event.unit_id) as UnitActor

	if actor == null:
		push_error("UnitActor is not registered for the moved unit.")
		return false

	map_view.clear_path()
	var empty_cells: Array[Vector2i] = []
	map_view.show_reachable_cells(empty_cells)

	for path_index in range(1, event.path.size()):
		var tween := actor.create_tween()
		tween.set_trans(Tween.TRANS_SINE)
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(
			actor,
			"global_position",
			map_view.hex_to_global_position(event.path[path_index]),
			actor.movement_step_duration
		)
		_track_tween(tween)
		await tween.finished

	return true


func _present_damage(
	event: UnitDamagedEvent,
	unit_actors: Dictionary[StringName, UnitActor],
	unit_definitions: Dictionary[StringName, UnitDefinition],
	map_view: BattleMapView,
	hud: BattleHUD
) -> bool:
	var actor := unit_actors.get(event.target_id) as UnitActor

	if actor == null:
		push_error("UnitActor is not registered for the attacked unit.")
		return false

	var attacker := unit_actors.get(event.attacker_id) as UnitActor
	var attacker_definition := unit_definitions.get(
		event.attacker_id
	) as UnitDefinition

	if (
		attacker_definition != null
		and attacker_definition.base_stats != null
		and attacker_definition.base_stats.basic_attack_range > 1
	):
		if attacker == null:
			push_error("UnitActor is not registered for the ranged attacker.")
			return false

		await _present_ranged_projectile(
			attacker,
			actor,
			map_view
		)

	hud.show_attack(
		_get_display_name(event.attacker_id, unit_definitions),
		_get_display_name(event.target_id, unit_definitions),
		event.damage,
		event.target_health_remaining
	)

	if actor.visible:
		var base_color := actor.modulate
		var hit_color := base_color.lerp(Color.RED, 0.7)
		var tween := actor.create_tween()
		tween.tween_property(
			actor,
			"modulate",
			hit_color,
			actor.damage_flash_duration * 0.5
		)
		tween.tween_property(
			actor,
			"modulate",
			base_color,
			actor.damage_flash_duration * 0.5
		)
		_track_tween(tween)
		await tween.finished

	if event.target_defeated:
		actor.visible = false

	return true


func _present_ranged_projectile(
	attacker: UnitActor,
	target: UnitActor,
	map_view: BattleMapView
) -> void:
	var start := map_view.to_local(attacker.global_position)
	var finish := map_view.to_local(target.global_position)
	var tracer := Line2D.new()
	tracer.name = "RangedAttackTracer"
	tracer.width = 5.0
	tracer.default_color = Color(1.0, 0.78, 0.16, 0.9)
	tracer.antialiased = true
	tracer.z_index = 50
	tracer.points = PackedVector2Array([start, finish])
	map_view.add_child(tracer)

	var projectile := Polygon2D.new()
	projectile.name = "RangedAttackProjectile"
	projectile.polygon = PackedVector2Array([
		Vector2(-10.0, -5.0),
		Vector2(12.0, 0.0),
		Vector2(-10.0, 5.0),
	])
	projectile.color = Color(1.0, 0.92, 0.35, 1.0)
	projectile.position = start
	projectile.rotation = (finish - start).angle()
	projectile.z_index = 51
	map_view.add_child(projectile)

	var tween := projectile.create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(
		projectile,
		"position",
		finish,
		0.22
	)
	tween.tween_property(
		tracer,
		"modulate:a",
		0.0,
		0.22
	)
	_track_tween(tween)
	await tween.finished
	projectile.queue_free()
	tracer.queue_free()


func _track_tween(tween: Tween) -> void:
	tween.set_speed_scale(settings.speed)
	_active_tweens.append(tween)
	tween.finished.connect(_on_tween_finished.bind(tween))


func _on_tween_finished(tween: Tween) -> void:
	_active_tweens.erase(tween)


func _on_speed_changed(speed: float) -> void:
	for tween: Tween in _active_tweens:
		if is_instance_valid(tween):
			tween.set_speed_scale(speed)


func _get_display_name(
	unit_id: StringName,
	unit_definitions: Dictionary[StringName, UnitDefinition]
) -> String:
	var definition := unit_definitions.get(unit_id) as UnitDefinition

	if definition == null:
		return String(unit_id)

	return definition.display_name
