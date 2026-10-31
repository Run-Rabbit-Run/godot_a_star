class_name AILastActionPlanner
extends RefCounted


## Their affected area depends on the user's hex, not only on the chosen center.
const ORIGIN_MODES := [AbilityDefinition.TargetMode.LINE, AbilityDefinition.TargetMode.PATH, AbilityDefinition.TargetMode.SELF]
## Effects that change only units inside the area; terrain effects may spread across the map.
const LOCAL_EFFECTS := [&"core:damage", &"core:unit_status"]


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
	# Every position fork inherits this search instead of repeating it inside its move.
	base.get_movement_search(active.unit_id)
	var opponents := session.get_living_opponents(active.faction)
	var approach_costs: Array[Dictionary] = []
	for opponent: UnitSnapshot in opponents:
		approach_costs.append(EnemyBrain.get_approach_costs(grid, opponent.hex, active.basic_attack_range))
	var start_approach := _approach(active.hex, opponents, approach_costs)
	var best: Dictionary = {}
	var advance: Dictionary = {}
	var candidates: Array = []
	# A move changes only the actor: other units and the map stay as they are, so one
	# simulated outcome serves every position whose hex the outcome does not touch.
	var others: Dictionary[Vector2i, UnitState] = {}
	for id: StringName in base.get_turn_order():
		var unit := base.get_unit(id)
		if unit != null and id != active.unit_id and not unit.health.is_defeated():
			others[unit.hex] = unit
	var memo := {"outcomes": {}, "reach": {}, "simulations": 0, "skipped": 0}
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
		for command: BattleCommand in _actions(position, actor, grid, others, memo):
			var scored := _score(position, actor, grid, others, command, cost, best, memo)
			if scored.is_empty():
				continue
			if trace != null:
				var record := {"command": command}
				for key: String in ["enemy_damage", "friendly_damage", "reused", "skipped"]:
					if scored.has(key):
						record[key] = scored[key]
				candidate.actions.append(record)
			if scored.has("skipped") or scored.enemy_damage <= 0 or scored.friendly_damage > 0:
				continue
			if _improves(best, scored.enemy_damage, cost):
				best = {"command": command if move == null else move, "followup_command": command, "enemy_damage": scored.enemy_damage, "cost": cost, "hex": actor.hex}
	if trace != null:
		trace["last_action"] = {"stay_forecast": stay, "candidates": candidates, "simulations": memo.simulations, "skipped_without_opponents": memo.skipped}
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


static func _actions(engine: BattleEngine, actor: UnitState, grid: HexGrid, others: Dictionary[Vector2i, UnitState], memo: Dictionary) -> Array[BattleCommand]:
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
				if _misses_opponents(ability, actor, grid, others, hex, memo):
					memo.skipped += 1
					continue
				commands.append(UseAbilityCommand.at_hex(actor.unit_id, hex, id))
			else:
				var target := engine.get_unit_at(hex)
				if target != null:
					commands.append(UseAbilityCommand.new(actor.unit_id, target.unit_id, id))
	return commands


## True when a local effect at this center provably removes no opponent HP.
static func _misses_opponents(ability: AbilityDefinition, actor: UnitState, grid: HexGrid, others: Dictionary[Vector2i, UnitState], center: Vector2i, memo: Dictionary) -> bool:
	if not _is_local(ability):
		return false
	var unit_hit := false
	if ability.target_mode in ORIGIN_MODES:
		for hex: Vector2i in AbilityExecutor.get_affected_hexes(grid, actor.hex, ability, center):
			var unit := others.get(hex) as UnitState
			if unit != null:
				if unit.faction != actor.faction:
					return false
				unit_hit = true
	else:
		# Any other area is every cell within its radius of the center.
		var reach := _centers_reaching(others, actor.faction, ability.area_radius, memo)
		if reach.opponents.has(center):
			return false
		unit_hit = reach.units.has(center) or HexGrid.get_distance(actor.hex, center) <= ability.area_radius
	# A physical hit on an own unit starts no terrain reaction, but a melee hit lets any
	# defender retaliate with its own damage type.
	return not unit_hit or (_is_physical(ability) and not ability.melee_attack)


## Centers whose area of this radius covers another unit or an opponent. Other units never
## move while the actor's options are explored, so each radius is computed once per plan.
static func _centers_reaching(others: Dictionary[Vector2i, UnitState], faction: BattleFaction.Value, radius: int, memo: Dictionary) -> Dictionary:
	if not memo.reach.has(radius):
		var units: Dictionary[Vector2i, bool] = {}
		var opponents: Dictionary[Vector2i, bool] = {}
		for hex: Vector2i in others:
			var opponent := others[hex].faction != faction
			for dq: int in range(-radius, radius + 1):
				for dr: int in range(maxi(-radius, -dq - radius), mini(radius, radius - dq) + 1):
					var center := hex + Vector2i(dq, dr)
					units[center] = true
					if opponent:
						opponents[center] = true
		memo.reach[radius] = {"units": units, "opponents": opponents}
	return memo.reach[radius]


## Equal damage keeps the earlier candidate unless the new one moves less.
static func _improves(best: Dictionary, enemy_damage: int, cost: int) -> bool:
	return best.is_empty() or enemy_damage > best.enemy_damage or (enemy_damage == best.enemy_damage and cost < best.cost)


## Opponent HP removed and friendly damage of one main action from the actor's current hex.
## Returns {} for a rejected command, or "skipped" when the action provably cannot become the plan.
static func _score(position: BattleEngine, actor: UnitState, grid: HexGrid, others: Dictionary[Vector2i, UnitState], command: BattleCommand, cost: int, best: Dictionary, memo: Dictionary) -> Dictionary:
	var ability: AbilityDefinition
	if command is UseAbilityCommand:
		ability = actor.get_ability(command.ability_id)
	# Retaliation depends on the actor's distance to each defender.
	if ability == null or ability.melee_attack:
		return _simulate(position, actor, command, memo)
	var center: Vector2i = command.target_hex if command.targets_hex else position.get_unit(command.target_id).hex
	var area := AbilityExecutor.get_affected_hexes(grid, actor.hex, ability, center)
	var key := _outcome_key(ability, grid, others, area, center)
	var cached: Dictionary = memo.outcomes.get(key, {})
	if not cached.is_empty():
		if not area.has(actor.hex) and not cached.changed.has(actor.hex):
			return {"enemy_damage": cached.enemy_damage, "friendly_damage": cached.friendly_damage, "reused": true}
		# Without an elemental hit on the actor its presence adds only its own damage:
		# opponents and allies lose exactly what they lose when the actor stands elsewhere.
		if _is_physical(ability) and (cached.enemy_damage <= 0 or cached.friendly_damage > 0 or not _improves(best, cached.enemy_damage, cost)):
			return {"skipped": "cannot_improve_plan"}
	var scored := _simulate(position, actor, command, memo)
	# Only an outcome that never touched the actor describes the same action from another hex.
	if cached.is_empty() and not scored.is_empty() and not area.has(actor.hex) and not scored.changed.has(actor.hex):
		memo.outcomes[key] = scored
	return scored


## Identifies the outcome of an ability for an actor standing outside everything it touches.
static func _outcome_key(ability: AbilityDefinition, grid: HexGrid, others: Dictionary[Vector2i, UnitState], area: Array[Vector2i], center: Vector2i) -> String:
	if not _is_local(ability):
		# Terrain effects change every cell of the area.
		var cells := area.duplicate()
		cells.sort()
		return str([ability.id, center, cells])
	# Local effects reach only units and obstacles in the area; the unit or obstacle at
	# the center takes full damage, everything else the secondary amount.
	var hit_ids: Array[StringName] = []
	for hex: Vector2i in area:
		var unit := others.get(hex) as UnitState
		if unit != null:
			hit_ids.append(unit.unit_id)
	hit_ids.sort()
	var center_unit := others.get(center) as UnitState if area.has(center) else null
	var obstacle_center: Variant = center if grid.has_obstacle(center) and area.has(center) else null
	return str([ability.id, hit_ids, center_unit.unit_id if center_unit != null else &"", _obstacle_hexes(grid, area), obstacle_center])


static func _simulate(position: BattleEngine, actor: UnitState, command: BattleCommand, memo: Dictionary) -> Dictionary:
	memo.simulations += 1
	var resolution := position.fork_for_prediction().execute(command)
	if not resolution.accepted or not resolution.terminal_error.is_empty():
		return {}
	var enemy_damage := 0
	var friendly_damage := 0
	# Hexes where a standing unit was hit, exposed or caught by a reaction.
	var changed: Dictionary[Vector2i, bool] = {}
	for event: BattleEvent in resolution.events:
		# Exclude later participants' start-of-turn effects from damage caused by this action.
		if event is TurnEndedEvent:
			break
		if event is MapMutationEvent and event.hex_state_changed:
			changed[event.hex] = true
		if event is UnitDamagedEvent:
			var victim := position.get_unit(event.target_id)
			if victim == null:
				continue
			if victim.faction != actor.faction:
				enemy_damage += event.damage
			elif victim.unit_id != actor.unit_id or event.source_status_id.is_empty():
				friendly_damage += event.damage
	return {"enemy_damage": enemy_damage, "friendly_damage": friendly_damage, "changed": changed}


static func _is_local(ability: AbilityDefinition) -> bool:
	for effect: AbilityEffectDefinition in ability.effects:
		if effect.effect_type_id not in LOCAL_EFFECTS:
			return false
	return true


## No elemental damage: a hit unit starts no terrain reaction.
static func _is_physical(ability: AbilityDefinition) -> bool:
	for effect: AbilityEffectDefinition in ability.effects:
		if effect.effect_type_id == &"core:damage" and StringName(effect.parameters.get("damage_type", "physical")) != &"physical":
			return false
	return true


static func _obstacle_hexes(grid: HexGrid, area: Array[Vector2i]) -> Array[Vector2i]:
	var hexes: Array[Vector2i] = []
	for hex: Vector2i in area:
		if grid.has_obstacle(hex):
			hexes.append(hex)
	hexes.sort()
	return hexes


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
