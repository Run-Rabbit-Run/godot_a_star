class_name BattleUnitViewRegistry
extends RefCounted


var actors: Dictionary[StringName, UnitActor] = {}
var definitions: Dictionary[StringName, UnitDefinition] = {}
var presentations: Dictionary[StringName, UnitPresentationDefinition] = {}

var _content_snapshot: ContentSnapshot
var _units_parent: Node2D
var _map_view: BattleMapView


func setup(
	content_snapshot: ContentSnapshot,
	units_parent: Node2D,
	map_view: BattleMapView
) -> void:
	_content_snapshot = content_snapshot
	_units_parent = units_parent
	_map_view = map_view


func create_units(
	spawns: Array[UnitSpawnData],
	session: BattleSession
) -> bool:
	clear()

	if (
		_content_snapshot == null
		or _units_parent == null
		or _map_view == null
		or session == null
	):
		push_error("BattleUnitViewRegistry is not configured.")
		return false

	for spawn: UnitSpawnData in spawns:
		var state := session.get_unit(spawn.unit_id)

		if state == null:
			push_error("Unit state is missing: %s." % spawn.unit_id)
			clear()
			return false

		var presentation := _content_snapshot.get_unit_presentation_definition(
			spawn.unit_definition.presentation_id
		)
		var actor := UnitActorFactory.create(
			state,
			spawn.unit_definition,
			presentation,
			_units_parent
		)

		if actor == null:
			push_error("Unit actor could not be created: %s." % spawn.unit_id)
			clear()
			return false

		var viewport_size := _map_view.get_viewport_rect().size
		var screen_scale := minf(viewport_size.x / 1920.0, viewport_size.y / 1080.0)
		actor.scale = Vector2.ONE * screen_scale / _map_view.scale
		actor.global_position = _map_view.hex_to_global_position(state.hex)
		actors[state.unit_id] = actor
		definitions[state.unit_id] = spawn.unit_definition

		if presentation != null:
			presentations[state.unit_id] = presentation

	return true


## Actors are created from the state after these events were applied. Showing the prior
## health lets the presentation queue replay the damage from the real starting value.
func show_health_before(events: Array[BattleEvent]) -> void:
	# Walk backwards so a unit damaged several times ends at its earliest health.
	for index in range(events.size() - 1, -1, -1):
		var damage := events[index] as UnitDamagedEvent

		if damage == null:
			continue

		var actor := actors.get(damage.target_id) as UnitActor
		var definition := get_definition(damage.target_id)

		if actor == null or definition == null or definition.base_stats == null:
			continue

		actor.show_health(
			damage.target_health_remaining + damage.damage,
			definition.base_stats.max_health
		)


func clear() -> void:
	for actor: UnitActor in actors.values():
		if is_instance_valid(actor):
			actor.queue_free()

	actors.clear()
	definitions.clear()
	presentations.clear()


func get_definition(unit_id: StringName) -> UnitDefinition:
	return definitions.get(unit_id) as UnitDefinition


func get_presentation(unit_id: StringName) -> UnitPresentationDefinition:
	return presentations.get(unit_id) as UnitPresentationDefinition


func get_display_name(unit_id: StringName) -> String:
	var definition := get_definition(unit_id)

	if definition == null:
		push_warning("UnitDefinition is not registered for presentation.")
		return String(unit_id)

	return definition.display_name


func get_texture(unit_id: StringName) -> Texture2D:
	var presentation := get_presentation(unit_id)
	if presentation == null:
		return null
	return presentation.portrait_texture if presentation.portrait_texture != null else presentation.actor_texture