class_name AILastActionPlanner
extends RefCounted


## Finite horizon: one reachable move followed by one main action, using real combat rules.
static func plan(session: BattleSession, trace: Variant = null) -> Dictionary:
	var active := session.get_unit(session.get_active_unit_id())
	var grid := session.get_hex_grid()
	var stay := MovementImpactForecast.evaluate(active, grid, [active.hex])
	if not stay.lethal:
		return {}
	var search := session.get_movement_search(active.unit_id)
	var cells := search.get_reachable_cells()
	cells.sort()
	for cell: Vector2i in cells:
		var forecast := MovementImpactForecast.evaluate(active, grid, search.build_path(cell))
		if forecast.reached and not forecast.lethal:
			return {}

	var base := session.create_prediction_engine()
	var opponents := session.get_living_opponents(active.faction)
	var approach_costs: Array[Dictionary] = []
	for opponent: UnitSnapshot in opponents:
		approach_costs.append(EnemyBrain.get_approach_costs(grid, opponent.hex, active.basic_attack_range))
	var start_approach := _approach(active.hex, opponents, approach_costs)
	var best: Dictionary = {}
	var advance: Dictionary = {}
	var candidates: Array = []
	if not cells.has(active.hex):
		cells.append(active.hex)
		cells.sort()
	for cell: Vector2i in cells:
		var position := base.fork_for_prediction()
		var move: MoveCommand
		if cell != active.hex:
			move = MoveCommand.new(active.unit_id, cell)
			var moved := position.execute(move)
			if not moved.accepted or not moved.terminal_error.is_empty():
				continue
		var actor := position.get_unit(active.unit_id)
		var cost := search.get_cost(cell)
		var approach := _approach(actor.hex, opponents, approach_costs)
		var candidate := {"requested_hex": cell, "reached_hex": actor.hex, "alive_after_move": not actor.health.is_defeated(), "cost": cost, "approach": approach, "actions": []}
		if trace != null:
			candidates.append(candidate)
		# Movement may be cut short by oil, paralysis or death; score actual reached position.
		if move != null and actor.hex != active.hex and approach < start_approach:
			var entry := {"command": move, "approach": approach, "alive": not actor.health.is_defeated(), "cost": cost}
			if advance.is_empty() or _better_advance(entry, advance):
				advance = entry
		if actor.health.is_defeated() or position.get_active_unit_id() != active.unit_id or actor.statuses.get(&"core:paralysis", 0) > 0 or not actor.turn.main_action_available:
			continue
		for command: BattleCommand in _actions(position, actor, grid):
			var forecast := position.fork_for_prediction()
			var resolution := forecast.execute(command)
			if not resolution.accepted or not resolution.terminal_error.is_empty():
				continue
			var enemy_damage := 0
			var friendly_damage := 0
			for event: BattleEvent in resolution.events:
				# Exclude later participants' start-of-turn effects from damage caused by this action.
				if event is TurnEndedEvent:
					break
				if event is UnitDamagedEvent:
					var victim := position.get_unit(event.target_id)
					if victim == null:
						continue
					if victim.faction != active.faction:
						enemy_damage += event.damage
					elif victim.unit_id != active.unit_id or event.source_status_id.is_empty():
						friendly_damage += event.damage
			if trace != null:
				candidate.actions.append({"command": command, "enemy_damage": enemy_damage, "friendly_damage": friendly_damage})
			if enemy_damage <= 0 or friendly_damage > 0:
				continue
			var entry := {"command": command if move == null else move, "followup_command": command, "enemy_damage": enemy_damage, "cost": cost, "hex": actor.hex}
			if best.is_empty() or enemy_damage > best.enemy_damage or (enemy_damage == best.enemy_damage and cost < best.cost):
				best = entry
	if trace != null:
		trace["last_action"] = {"stay_forecast": stay, "candidates": candidates}
	if not best.is_empty():
		best["reason"] = "doomed_maximum_damage"
		if trace != null:
			trace.last_action["selected"] = best
		return best
	if not advance.is_empty():
		advance["reason"] = "doomed_advance_toward_enemy"
		if trace != null:
			trace.last_action["selected"] = advance
		return advance
	return {"command": EndTurnCommand.new(active.unit_id), "reason": "doomed_no_reachable_progress"}


static func _actions(engine: BattleEngine, actor: UnitState, grid: HexGrid) -> Array[BattleCommand]:
	var commands: Array[BattleCommand] = []
	for target: UnitState in engine.get_attackable_targets(actor.unit_id):
		commands.append(AttackCommand.new(actor.unit_id, target.unit_id))
	var ids: Array = actor.abilities.keys()
	ids.sort()
	for id: StringName in ids:
		var ability := actor.get_ability(id)
		# Only built-in stateless handlers can be speculatively executed safely.
		if not _supports_prediction(ability) or not engine.supports_ability_prediction(ability):
			continue
		var areas: Dictionary = {}
		for hex: Vector2i in engine.get_ability_target_hexes(actor.unit_id, id):
			if ability.targets_hex():
				# A line's endpoint only chooses direction. Simulate each direction once.
				if ability.target_mode == AbilityDefinition.TargetMode.LINE:
					var direction := AbilityExecutor.get_line_direction(actor.hex, hex)
					if areas.has(direction):
						continue
					areas[direction] = true
				commands.append(UseAbilityCommand.at_hex(actor.unit_id, hex, id))
			else:
				var target := engine.get_unit_at(hex)
				if target != null:
					commands.append(UseAbilityCommand.new(actor.unit_id, target.unit_id, id))
	return commands


static func _supports_prediction(ability: AbilityDefinition) -> bool:
	# Status application may cause immediate oil explosions; score its real events as well.
	var can_affect_enemy := false
	for effect: AbilityEffectDefinition in ability.effects:
		if effect.effect_type_id not in [&"core:damage", &"core:hex_state", &"core:unit_status", &"core:summon"]:
			return false
		can_affect_enemy = can_affect_enemy or effect.effect_type_id != &"core:summon"
	return can_affect_enemy


static func _approach(hex: Vector2i, opponents: Array[UnitSnapshot], costs: Array[Dictionary]) -> int:
	var closest := 2147483647
	for index in range(opponents.size()):
		var distance: int = costs[index].get(hex, HexGrid.get_distance(hex, opponents[index].hex))
		closest = mini(closest, distance)
	return closest


static func _better_advance(left: Dictionary, right: Dictionary) -> bool:
	if left.alive != right.alive:
		return left.alive
	if left.approach != right.approach:
		return left.approach < right.approach
	return left.cost < right.cost
