class_name AbilityEffectPipeline
extends RefCounted
## Applies an ability's effects to its area and targets. Ability use and the returning
## weapon share it, so every effect obeys one handler contract and one failure rule.


## Runs every effect in order. Stops at the first failure, which is recorded on the
## context; the caller then discards the state the effects ran on. With `skip_defeated`
## a target already defeated when its turn comes is passed over (the returning weapon).
static func apply(context: BattleEffectContext, state: BattleState, ability: AbilityDefinition, user_id: StringName, cells: Array[Vector2i], target_ids: Array[StringName], skip_defeated := false) -> Array[BattleEvent]:
	# A handler that crashes returns an ordinary empty list; its script error fails the run.
	var watch := ScriptErrorWatch.start()
	var events := _run(context, state, ability, user_id, cells, target_ids, skip_defeated, watch)
	if watch.stop() > 0:
		context.fail("An ability effect raised a script error.")
	return events


static func _run(context: BattleEffectContext, state: BattleState, ability: AbilityDefinition, user_id: StringName, cells: Array[Vector2i], target_ids: Array[StringName], skip_defeated: bool, watch: ScriptErrorWatch) -> Array[BattleEvent]:
	var events: Array[BattleEvent] = []
	var user := state.unit_states.get(user_id) as UnitState
	for effect: AbilityEffectDefinition in ability.effects:
		var handler := state.mod_api.get_effect_handler(effect.effect_type_id) if effect != null else null
		if handler == null:
			context.fail("Missing ability effect handler: %s." % (effect.effect_type_id if effect != null else &""))
			return events
		if handler is DamageEffectHandler and effect.parameters.get("affects_obstacles", true):
			_damage_obstacles(state, effect, user, cells, context.target_hex, events)
		if handler.affects_hexes():
			var effect_cells: Array[Vector2i] = []
			if effect.parameters.get("center_only", false):
				effect_cells.append(context.target_hex)
			else:
				effect_cells.assign(cells)
			if not _collect(handler.execute_hexes(effect, context, user_id, effect_cells), effect, context, events, watch):
				return events
		else:
			for target_id: StringName in target_ids:
				if skip_defeated and state.unit_states[target_id].health.is_defeated():
					continue
				if not _collect(handler.execute(effect, context, user_id, target_id), effect, context, events, watch):
					return events
	return events


## Each struck obstacle takes damage once per effect: full at the center, secondary elsewhere.
static func _damage_obstacles(state: BattleState, effect: AbilityEffectDefinition, user: UnitState, cells: Array[Vector2i], center: Vector2i, events: Array[BattleEvent]) -> void:
	var hit: Dictionary[StringName, bool] = {}
	var ordered_cells := cells.duplicate()
	ordered_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return HexGrid.get_distance(center, a) < HexGrid.get_distance(center, b))
	for hex: Vector2i in ordered_cells:
		var obstacle := state.hex_grid.get_obstacle(hex)
		if obstacle == null or hit.has(obstacle.id):
			continue
		hit[obstacle.id] = true
		var amount := user.basic_attack_damage if effect.parameters.get("use_base_attack", false) else int(effect.parameters["amount"] if hex == center else effect.parameters.get("secondary_amount", effect.parameters["amount"]))
		ObstacleService.damage(state, hex, amount, events)


## A handler result must be a list of events; anything else, a script error or a reported
## failure stops the run.
static func _collect(produced: Variant, effect: AbilityEffectDefinition, context: BattleEffectContext, events: Array[BattleEvent], watch: ScriptErrorWatch) -> bool:
	if watch.error_count() > 0:
		context.fail("Effect handler %s raised a script error." % effect.effect_type_id)
		return false
	if not produced is Array:
		context.fail("Effect handler %s returned no event list." % effect.effect_type_id)
		return false
	for event: Variant in produced:
		if not event is BattleEvent:
			context.fail("Effect handler %s returned an invalid event." % effect.effect_type_id)
			return false
		events.append(event)
	return not context.has_failed()
