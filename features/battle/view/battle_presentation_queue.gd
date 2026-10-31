class_name BattlePresentationQueue
extends Node


const SPEAR_GLYPH := preload("res://features/battle/view/spear_glyph.gd")
## Processed frames without tween progress after which a step is completed at once.
const STALL_FRAMES := 30
## Tween time after which an awaited step counts as endless; real steps take seconds.
const MAX_STEP_SECONDS := 120.0

signal _step_closed(id: int)

var _landed_spears: Dictionary[StringName, Node2D] = {}
var settings := BattlePlaybackSettings.new()
var _active_tweens: Array[Tween] = []
var _content_snapshot: ContentSnapshot
var _unit_views: BattleUnitViewRegistry
var _steps: Dictionary[int, Dictionary] = {}
var _closed_steps: Dictionary[int, bool] = {}
var _next_step_id := 0
## Animation steps cut short during the last present(); the controller then snaps the view.
var interrupted_steps := 0


func _ready() -> void:
	settings.speed_changed.connect(_on_speed_changed)
	set_process(false)


## Without a snapshot every ability uses the fallback visuals.
func configure(content_snapshot: ContentSnapshot, unit_views: BattleUnitViewRegistry = null) -> void:
	for spear: Node2D in _landed_spears.values():
		if is_instance_valid(spear):
			spear.queue_free()
	_landed_spears.clear()
	_content_snapshot = content_snapshot
	_unit_views = unit_views


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

	interrupted_steps = 0
	map_view.clear_ranged_attack_cells()

	for event: BattleEvent in resolution.events:
		hud.append_battle_log(BattleLogFormatter.describe(event, unit_definitions, _content_snapshot))
		if event is TurnEndedEvent:
			hud.log_round(event.round_number)
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
	if event is UnitSummonedEvent:
		return _unit_views != null and _unit_views.create_summoned(event as UnitSummonedEvent)
	if event is UnitStatusChangedEvent:
		var status_event := event as UnitStatusChangedEvent
		var actor := _actor(unit_actors, status_event.unit_id)
		if actor != null:
			actor.show_statuses(status_event.statuses)
		return true

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
	var actor := _actor(unit_actors, event.unit_id)

	if actor == null:
		push_error("UnitActor is not registered for the moved unit.")
		return false

	map_view.clear_path()
	var empty_cells: Array[Vector2i] = []
	map_view.show_reachable_cells(empty_cells)

	var positions: Array[Vector2] = []
	for path_index in range(1, event.path.size()):
		positions.append(map_view.hex_to_global_position(event.path[path_index]))
	var tween := actor.create_movement_tween(positions)
	if tween != null:
		_track_tween(tween)
		await _finish(tween)

	return true


func _present_damage(
	event: UnitDamagedEvent,
	unit_actors: Dictionary[StringName, UnitActor],
	unit_definitions: Dictionary[StringName, UnitDefinition],
	map_view: BattleMapView,
	hud: BattleHUD
) -> bool:
	var actor := _actor(unit_actors, event.target_id)

	if actor == null:
		push_error("UnitActor is not registered for the attacked unit.")
		return false

	var attacker := _actor(unit_actors, event.attacker_id)
	var attacker_definition := unit_definitions.get(
		event.attacker_id
	) as UnitDefinition

	var source_name := _get_display_name(event.attacker_id, unit_definitions)

	if not event.source_hex_state_id.is_empty():
		source_name = HexStateCatalog.get_display_name(event.source_hex_state_id)
	if not event.source_status_id.is_empty():
		source_name = UnitStatusCatalog.display_name(event.source_status_id)

	hud.show_attack(
		source_name,
		_get_display_name(event.target_id, unit_definitions),
		event.damage,
		event.target_health_remaining
	)

	var contact := _show_damage_health.bind(event, actor, unit_definitions)
	var tween: Tween
	if (
		(event.source_ability_id.is_empty() or event.source_ability_id == &"core:melee_retaliation")
		and event.source_hex_state_id.is_empty()
		and event.source_status_id.is_empty()
		and attacker != null
		and attacker_definition != null
		and attacker_definition.base_stats != null
	):
		tween = UnitCombatAnimator.attack(
			attacker, actor, attacker_definition.base_stats.basic_attack_range > 1, contact
		)
	else:
		tween = UnitCombatAnimator.hit(actor, contact)
	_track_tween(tween)
	await _finish(tween)
	if event.target_defeated and is_instance_valid(actor):
		var fall_direction := 1.0
		if is_instance_valid(attacker) and attacker != actor:
			fall_direction = -1.0 if attacker.global_position.x > actor.global_position.x else 1.0
		var death := actor.create_defeat_tween(fall_direction)
		if death != null:
			_track_tween(death)
			await _finish(death)
	return true


func _show_damage_health(
	event: UnitDamagedEvent, actor: UnitActor,
	unit_definitions: Dictionary[StringName, UnitDefinition]
) -> void:
	var target_definition := unit_definitions.get(
		event.target_id
	) as UnitDefinition
	var maximum_health := maxi(event.target_health_remaining, 1)

	if target_definition != null and target_definition.base_stats != null:
		maximum_health = target_definition.base_stats.max_health

	actor.show_health(event.target_health_remaining, maximum_health)
	_show_damage_number(event, actor)


func _show_damage_number(event: UnitDamagedEvent, actor: UnitActor) -> void:
	var badge := PanelContainer.new()
	badge.name = "DamageNumber"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.z_index = 100
	var background := DamageTypeColors.get_color(event.damage_type)
	background.a = 0.92
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.set_corner_radius_all(5)
	style.set_border_width_all(1)
	style.border_color = Color(0.04, 0.05, 0.07, 0.65)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	badge.add_theme_stylebox_override("panel", style)
	var number := Label.new()
	number.name = "Number"
	number.text = str(event.damage)
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number.add_theme_font_size_override("font_size", 12)
	number.add_theme_color_override("font_color", Color("10141c"))
	badge.add_child(number)
	actor.get_parent().add_child(badge)
	# Keep the badge square even for larger damage values.
	var minimum := badge.get_combined_minimum_size()
	var side := maxf(22.0, maxf(minimum.x, minimum.y))
	badge.custom_minimum_size = Vector2.ONE * side
	badge.size = Vector2.ONE * side
	badge.global_position = actor.get_combat_anchor() - Vector2(side * 0.5, 42.0)
	var tween := badge.create_tween().set_parallel(true)
	tween.tween_property(badge, "position:y", badge.position.y - 55.0, 0.85)
	tween.tween_property(badge, "modulate:a", 0.0, 0.45).set_delay(0.4)
	_track_tween(tween)
	tween.finished.connect(badge.queue_free)


func _present_ability(
	event: AbilityUsedEvent,
	unit_actors: Dictionary[StringName, UnitActor],
	map_view: BattleMapView
) -> bool:
	var user := _actor(unit_actors, event.user_id)
	var target := _actor(unit_actors, event.target_id)

	if user == null or target == null:
		push_error("UnitActor is not registered for the ability user or target.")
		return false

	# The following UnitDamagedEvent flashes the target; here the effect only travels.
	await _present_delivery(
		_get_ability_presentation(event.ability_id, false),
		map_view.to_local(user.get_combat_anchor(0.68)),
		map_view.to_local(target.get_combat_anchor()),
		map_view,
		"Ability"
	)
	return true


func _present_area_ability(
	event: AreaAbilityUsedEvent,
	unit_actors: Dictionary[StringName, UnitActor],
	map_view: BattleMapView
) -> bool:
	var user := _actor(unit_actors, event.user_id)

	if user == null:
		push_error("UnitActor is not registered for the area ability user.")
		return false

	var presentation := _get_ability_presentation(event.ability_id, true)
	var ability := _content_snapshot.get_ability_definition(event.ability_id) if _content_snapshot != null else null
	if event.is_return or (ability != null and ability.returns_next_turn):
		return await _present_spear(event, user, map_view)
	if ability != null and ability.target_mode == AbilityDefinition.TargetMode.LINE:
		return await _present_beam(user, event.affected_hexes, map_view, presentation.impact_color)
	var finish := map_view.to_local(
		map_view.hex_to_global_position(event.target_hex)
	)
	await _present_delivery(
		presentation,
		map_view.to_local(map_view.hex_to_global_position(event.origin_hex)) if event.is_return else map_view.to_local(user.global_position),
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
	await _finish(impact_tween)
	_free_nodes([core, shockwave])
	map_view.clear_ability_area()
	return true


func _present_beam(user: UnitActor, cells: Array[Vector2i], map_view: BattleMapView, color: Color) -> bool:
	if cells.is_empty():
		return true
	var beam := Line2D.new()
	beam.name = "PiercingBeam"
	beam.width = 9.0
	beam.default_color = color
	beam.antialiased = true
	beam.z_index = 60
	beam.add_point(map_view.to_local(user.get_combat_anchor()))
	beam.add_point(map_view.to_local(map_view.hex_to_global_position(cells.back())) - Vector2(0, 25))
	map_view.add_child(beam)
	map_view.show_ability_area(cells)
	var tween := beam.create_tween()
	tween.tween_property(beam, "width", 2.0, 0.35)
	tween.parallel().tween_property(beam, "modulate:a", 0.0, 0.35)
	_track_tween(tween)
	await _finish(tween)
	_free_nodes([beam])
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
	tracer.points = PackedVector2Array([start, start])
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
	tween.tween_method(func(progress: float) -> void:
		projectile.position = start.lerp(finish, progress)
		var tail := start.lerp(finish, maxf(0.0, progress - 0.16))
		tracer.points = PackedVector2Array([tail, projectile.position])
	, 0.0, 1.0, 0.22)
	_track_tween(tween)
	await _finish(tween)
	_free_nodes([projectile, tracer])


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
	await _finish(tween)
	_free_nodes([projectile, trail])


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


## Waits for a tracked tween without trusting it to finish: a broken animation must not
## block the battle. A tween that stops advancing is completed at once, so its final pose
## and callbacks still apply; one that dies or never ends is cut. Both count as interrupted.
## Returns false when the tween ended without reaching its end.
func _finish(tween: Tween) -> bool:
	var id := _next_step_id
	_next_step_id += 1
	_steps[id] = {"tween": tween, "elapsed": -1.0, "stalled_frames": 0}
	tween.finished.connect(_close_step.bind(id, true), CONNECT_ONE_SHOT)
	set_process(true)
	while not _closed_steps.has(id):
		await _step_closed
	var completed := _closed_steps[id]
	_closed_steps.erase(id)
	return completed


func _close_step(id: int, completed: bool) -> void:
	if not _steps.has(id):
		return
	_steps.erase(id)
	_closed_steps[id] = completed
	_step_closed.emit(id)


func _process(_delta: float) -> void:
	for id: int in _steps.keys():
		if not _steps.has(id):
			continue
		var step := _steps[id]
		var tween: Tween = step.tween
		if not tween.is_valid():
			push_warning("Battle animation ended before finishing; the view will be synchronized.")
			interrupted_steps += 1
			_close_step(id, false)
			continue
		var elapsed := tween.get_total_elapsed_time()
		if elapsed != step.elapsed:
			step.elapsed = elapsed
			step.stalled_frames = 0
		else:
			step.stalled_frames += 1
		if step.stalled_frames < STALL_FRAMES and elapsed <= MAX_STEP_SECONDS:
			continue
		push_warning("Battle animation stopped advancing and was completed at once.")
		interrupted_steps += 1
		# Completing runs the remaining callbacks, restores poses and emits finished.
		tween.custom_step(MAX_STEP_SECONDS)
		if _steps.has(id):
			tween.kill()
			_close_step(id, false)
	if _steps.is_empty():
		set_process(false)


## A freed actor reads as unregistered; casting a freed object would raise a script error.
func _actor(unit_actors: Dictionary[StringName, UnitActor], unit_id: StringName) -> UnitActor:
	var actor: Variant = unit_actors.get(unit_id)
	return actor as UnitActor if is_instance_valid(actor) else null


## An interrupted step may already have lost its effect nodes.
func _free_nodes(nodes: Array) -> void:
	for node: Variant in nodes:
		if is_instance_valid(node):
			(node as Node).queue_free()


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


## Resolve presentation from the event being shown, never the engine's future snapshot.
func _present_spear(event: AreaAbilityUsedEvent, user: UnitActor, map_view: BattleMapView) -> bool:
	var spear: Node2D = _landed_spears.get(event.user_id)
	var start := map_view.to_local(user.get_combat_anchor())
	var finish := map_view.to_local(map_view.hex_to_global_position(event.target_hex))
	if event.is_return:
		start = map_view.to_local(map_view.hex_to_global_position(event.origin_hex)) + Vector2(0, 8)
		finish = map_view.to_local(user.get_combat_anchor())
		_landed_spears.erase(event.user_id)
	if not is_instance_valid(spear):
		spear = SPEAR_GLYPH.new()
		spear.name = "Spear_" + String(event.user_id)
		spear.z_index = 65
		# Match normal 94x78 battlefield art on the 56x64 logical tiles.
		spear.scale = Vector2(56.0 / 94.0, 64.0 / 78.0)
		map_view.add_child(spear)
	spear.position = start
	spear.rotation = (finish - start).angle()
	var flight := spear.create_tween()
	flight.tween_property(spear, "position", finish, clampf(start.distance_to(finish) / 850.0, 0.18, 0.5))
	_track_tween(flight)
	await _finish(flight)
	if not is_instance_valid(spear):
		return true
	if event.is_return:
		spear.queue_free()
	else:
		spear.position = finish + Vector2(0, 8)
		spear.rotation = -0.42
		spear.set_meta("landing_hex", event.target_hex)
		spear.set_meta("owner_id", event.user_id)
		_landed_spears[event.user_id] = spear
	return true
