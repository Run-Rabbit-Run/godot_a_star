class_name BattlePresentationQueue
extends Node


var settings := BattlePlaybackSettings.new()
var _active_tweens: Array[Tween] = []
var _content_snapshot: ContentSnapshot
# A basic ranged attack reuses the default projectile look of an ability.
var _basic_attack_delivery := AbilityPresentationDefinition.new()


func _ready() -> void:
	settings.speed_changed.connect(_on_speed_changed)


## Without a snapshot every ability uses the fallback visuals.
func configure(content_snapshot: ContentSnapshot) -> void:
	_content_snapshot = content_snapshot


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

	if event is AreaAbilityUsedEvent:
		return await _present_area_ability(
			event as AreaAbilityUsedEvent,
			unit_actors,
			map_view
		)

	if event is AbilityUsedEvent:
		return await _present_ability(
			event as AbilityUsedEvent,
			unit_actors,
			map_view
		)

	if event is TurnEndedEvent:
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
		event.source_ability_id.is_empty()
		and event.source_hex_state_id.is_empty()
		and attacker_definition != null
		and attacker_definition.base_stats != null
		and attacker_definition.base_stats.basic_attack_range > 1
	):
		if attacker == null:
			push_error("UnitActor is not registered for the ranged attacker.")
			return false

		await _present_delivery(
			_basic_attack_delivery,
			map_view.to_local(attacker.global_position),
			map_view.to_local(actor.global_position),
			map_view,
			"RangedAttack"
		)

	var source_name := _get_display_name(event.attacker_id, unit_definitions)

	if not event.source_hex_state_id.is_empty():
		source_name = HexStateCatalog.get_display_name(event.source_hex_state_id)

	hud.show_attack(
		source_name,
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

	var target_definition := unit_definitions.get(
		event.target_id
	) as UnitDefinition
	var maximum_health := maxi(event.target_health_remaining, 1)

	if target_definition != null and target_definition.base_stats != null:
		maximum_health = target_definition.base_stats.max_health

	actor.show_health(event.target_health_remaining, maximum_health)

	if event.target_defeated:
		actor.present_defeat()

	return true


func _present_ability(
	event: AbilityUsedEvent,
	unit_actors: Dictionary[StringName, UnitActor],
	map_view: BattleMapView
) -> bool:
	var user := unit_actors.get(event.user_id) as UnitActor
	var target := unit_actors.get(event.target_id) as UnitActor

	if user == null or target == null:
		push_error("UnitActor is not registered for the ability user or target.")
		return false

	# The following UnitDamagedEvent flashes the target; here the effect only travels.
	await _present_delivery(
		_get_ability_presentation(event.ability_id, false),
		map_view.to_local(user.global_position),
		map_view.to_local(target.global_position),
		map_view,
		"Ability"
	)
	return true


func _present_area_ability(
	event: AreaAbilityUsedEvent,
	unit_actors: Dictionary[StringName, UnitActor],
	map_view: BattleMapView
) -> bool:
	var user := unit_actors.get(event.user_id) as UnitActor

	if user == null:
		push_error("UnitActor is not registered for the area ability user.")
		return false

	var presentation := _get_ability_presentation(event.ability_id, true)
	var finish := map_view.to_local(
		map_view.hex_to_global_position(event.target_hex)
	)
	await _present_delivery(
		presentation,
		map_view.to_local(user.global_position),
		finish,
		map_view,
		"Ability"
	)

	map_view.show_ability_area(event.affected_hexes)
	var core := Polygon2D.new()
	core.name = "AbilityImpactCore"
	core.polygon = _circle_points(30.0, 28)
	core.color = presentation.impact_color
	core.position = finish
	core.scale = Vector2(0.18, 0.18)
	core.z_index = 52
	map_view.add_child(core)

	var shockwave := Line2D.new()
	shockwave.name = "AbilityImpactRing"
	shockwave.width = 9.0
	shockwave.default_color = Color(0.784, 0.725, 0.604, 0.92)
	shockwave.antialiased = true
	shockwave.closed = true
	shockwave.points = _circle_points(42.0, 32)
	shockwave.position = finish
	shockwave.scale = Vector2(0.2, 0.2)
	shockwave.z_index = 53
	map_view.add_child(shockwave)

	var impact_tween := core.create_tween()
	impact_tween.set_parallel(true)
	impact_tween.set_trans(Tween.TRANS_QUAD)
	impact_tween.set_ease(Tween.EASE_OUT)
	impact_tween.tween_property(core, "scale", Vector2(2.1, 2.1), 0.34)
	impact_tween.tween_property(core, "modulate:a", 0.0, 0.34)
	impact_tween.tween_property(shockwave, "scale", Vector2(2.0, 2.0), 0.34)
	impact_tween.tween_property(shockwave, "modulate:a", 0.0, 0.34)
	_track_tween(impact_tween)
	await impact_tween.finished
	core.queue_free()
	shockwave.queue_free()
	map_view.clear_ability_area()
	return true


func _present_delivery(
	presentation: AbilityPresentationDefinition,
	start: Vector2,
	finish: Vector2,
	map_view: BattleMapView,
	node_prefix: String
) -> void:
	if presentation.delivery == AbilityPresentationDefinition.Delivery.PROJECTILE:
		await _present_projectile(
			presentation,
			start,
			finish,
			map_view,
			node_prefix
		)
	elif presentation.delivery == AbilityPresentationDefinition.Delivery.THROWN:
		await _present_thrown(
			presentation,
			start,
			finish,
			map_view,
			node_prefix
		)


func _present_projectile(
	presentation: AbilityPresentationDefinition,
	start: Vector2,
	finish: Vector2,
	map_view: BattleMapView,
	node_prefix: String
) -> void:
	var tracer := Line2D.new()
	tracer.name = "%sTracer" % node_prefix
	tracer.width = 5.0
	tracer.default_color = presentation.trail_color
	tracer.antialiased = true
	tracer.z_index = 50
	tracer.points = PackedVector2Array([start, finish])
	map_view.add_child(tracer)

	var projectile := Polygon2D.new()
	projectile.name = "%sProjectile" % node_prefix
	projectile.polygon = PackedVector2Array([
		Vector2(-10.0, -5.0),
		Vector2(12.0, 0.0),
		Vector2(-10.0, 5.0),
	])
	projectile.color = presentation.projectile_color
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


func _present_thrown(
	presentation: AbilityPresentationDefinition,
	start: Vector2,
	finish: Vector2,
	map_view: BattleMapView,
	node_prefix: String
) -> void:
	var trail := Line2D.new()
	trail.name = "%sTrail" % node_prefix
	trail.width = 4.0
	trail.default_color = presentation.trail_color
	trail.antialiased = true
	trail.z_index = 50
	trail.points = PackedVector2Array([start, finish])
	map_view.add_child(trail)

	var projectile := Polygon2D.new()
	projectile.name = "%sProjectile" % node_prefix
	projectile.polygon = _circle_points(9.0, 16)
	projectile.color = presentation.projectile_color
	projectile.position = start
	projectile.z_index = 51
	map_view.add_child(projectile)

	var tween := projectile.create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(projectile, "position", finish, 0.28)
	tween.tween_property(projectile, "rotation", TAU * 2.0, 0.28)
	tween.tween_property(trail, "modulate:a", 0.0, 0.28)
	_track_tween(tween)
	await tween.finished
	projectile.queue_free()
	trail.queue_free()


func _get_ability_presentation(
	ability_id: StringName,
	is_area: bool
) -> AbilityPresentationDefinition:
	var presentation: AbilityPresentationDefinition

	if _content_snapshot != null:
		var ability := _content_snapshot.get_ability_definition(ability_id)

		if ability != null and not ability.presentation_id.is_empty():
			presentation = _content_snapshot.get_ability_presentation_definition(
				ability.presentation_id
			)

	if presentation != null:
		return presentation

	# Presentation is optional: an area ability falls back to a throw, a targeted one to a shot.
	var fallback := AbilityPresentationDefinition.new()

	if is_area:
		fallback.delivery = AbilityPresentationDefinition.Delivery.THROWN

	return fallback


func _circle_points(radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()

	for index in range(segments):
		var angle := TAU * float(index) / float(segments)
		points.append(Vector2.from_angle(angle) * radius)

	return points


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
