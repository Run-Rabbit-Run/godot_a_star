class_name AITacticalPlanner
extends RefCounted
## The tactical AI policy: for each of its ready units, every reachable hex followed by every
## main action, scored on forecast copies of the battle; the best plan wins, whichever unit it
## belongs to. One decision returns the plan's first command; the next call plans again.

const KILL_BONUS := 4.0
const FRIENDLY_DAMAGE_WEIGHT := 1.5
const FRIENDLY_KILL_PENALTY := 10.0
const SELF_DAMAGE_WEIGHT := 1.0
const SELF_DEATH_PENALTY := 20.0
const THREAT_WEIGHT := 0.5
const APPROACH_WEIGHT := 0.3
const SHOOTER_PRESSURE_BONUS := 2.0
## Units the objective names: an opponent's commander or protected unit is worth more, and its
## defeat may decide the battle; an own one stays out of reach twice as carefully.
const KEY_DAMAGE_WEIGHT := 1.0
const KEY_KILL_BONUS := 10.0
## Forecast executions one decision may spend, shared evenly by the candidate units with a
## floor per unit; beyond its share a unit keeps the best plan found so far.
const DECISION_BUDGET := 300
const MIN_UNIT_BUDGET := 40


## The best plan as {"command", "unit_id", "score", "enemy_damage", "approach_gain"}, or {}
## when none of the units can act.
static func plan(session: BattleSession, unit_ids: Array[StringName], trace: Variant = null) -> Dictionary:
	if unit_ids.is_empty():
		return {}
	var faction := session.get_unit(unit_ids[0]).faction
	var opponents := session.get_living_opponents(faction)
	var threat := _threat_map(session, opponents)
	var base := session.create_prediction_engine()
	var grid := session.get_hex_grid()
	var best: Dictionary = {}
	var evaluated: Array = []
	var simulations := 0
	# Approach costs depend only on the opponent and the attack range: shared by all units.
	var approach_cache: Dictionary = {}
	var keys: Array[StringName] = session.get_objective_target_ids()
	keys.append_array(session.get_protected_unit_ids())
	var budget := maxi(MIN_UNIT_BUDGET, DECISION_BUDGET / unit_ids.size())
	for unit_id: StringName in unit_ids:
		var memo := {"reach": {}, "skipped": 0, "simulations": 0, "approach": approach_cache, "budget": budget, "keys": keys}
		var unit_plan := _plan_unit(session, base, grid, unit_id, opponents, threat, memo)
		simulations += memo.simulations
		if trace != null:
			evaluated.append({"unit_id": unit_id, "plan": unit_plan})
		if not unit_plan.is_empty() and (best.is_empty() or unit_plan.score > best.score):
			best = unit_plan
	if trace != null:
		trace["tactical"] = {"units": evaluated, "simulations": simulations, "selected": best}
	return best


static func _plan_unit(session: BattleSession, base: BattleEngine, grid: HexGrid, unit_id: StringName, opponents: Array[UnitSnapshot], threat: Dictionary[Vector2i, int], memo: Dictionary) -> Dictionary:
	var actor := session.get_unit(unit_id)
	var actor_state := base.get_unit(unit_id)
	if actor == null or not session.can_command(unit_id):
		return {}
	var approach_costs: Array[Dictionary] = []
	for opponent: UnitSnapshot in opponents:
		var key := "%s|%d" % [opponent.hex, actor.basic_attack_range]
		if not memo.approach.has(key):
			memo.approach[key] = EnemyBrain.get_approach_costs(grid, opponent.hex, actor.basic_attack_range)
		approach_costs.append(memo.approach[key])
	var start_approach := _approach(actor.hex, opponents, approach_costs)
	var search := session.get_movement_search(unit_id)
	var cells := search.get_reachable_cells()
	if not cells.has(actor.hex):
		cells.append(actor.hex)
	# Cells nearer the opponents come first, so the budget is spent where the fight is.
	var distances: Dictionary[Vector2i, int] = {}
	for cell: Vector2i in cells:
		var nearest := 1000
		for opponent: UnitSnapshot in opponents:
			nearest = mini(nearest, HexGrid.get_distance(cell, opponent.hex))
		distances[cell] = nearest
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return distances[a] < distances[b] if distances[a] != distances[b] else a < b)
	# A move changes only the actor: the other units keep their hexes in every position.
	var others: Dictionary[Vector2i, UnitState] = {}
	var shooters: Array[Vector2i] = []
	for other_id: StringName in base.get_turn_order():
		var other := base.get_unit(other_id)
		if other_id == unit_id or other.health.is_defeated():
			continue
		others[other.hex] = other
		if other.faction != actor.faction and other.basic_attack_range > 1:
			shooters.append(other.hex)
	var reach := _action_reach(actor_state)
	var context := {"health_before": actor.health.current, "start_approach": start_approach, "threat": threat, "shooters": shooters, "range": actor.basic_attack_range, "faction": actor.faction, "key": memo.keys.has(unit_id)}
	var best: Dictionary = {}
	# Outcomes of area abilities that leave the actor outside; the same from every hex.
	var outcomes: Dictionary = {}
	for cell: Vector2i in cells:
		var move: MoveCommand = MoveCommand.new(unit_id, cell) if cell != actor.hex else null
		context["approach"] = _approach(cell, opponents, approach_costs)
		# Standing there without acting: the route, the end of the turn and the position, forecast
		# without copying the battle.
		var path: Array[Vector2i] = [actor.hex]
		if move != null:
			path = search.build_path(cell)
		var forecast := MovementImpactForecast.evaluate(actor, grid, path)
		if not forecast.reached:
			continue
		var idle := _score(cell, {}, actor.health.current - int(forecast.damage), bool(forecast.lethal), context)
		_keep(best, idle, move if move != null else EndTurnCommand.new(unit_id), unit_id, move != null)
		if memo.simulations >= memo.budget or not _in_reach(cell, opponents, reach):
			continue
		var position := base.fork_for_prediction()
		if move != null:
			memo.simulations += 1
			var moved := position.execute(move)
			if not moved.accepted or not moved.terminal_error.is_empty():
				continue
		var mover := position.get_unit(unit_id)
		if mover.health.is_defeated() or not position.can_command(unit_id) or not mover.turn.main_action_available:
			continue
		for command: BattleCommand in AILastActionPlanner.actions(position, mover, grid, others, memo):
			if memo.simulations >= memo.budget:
				break
			if _misses_everyone(command, mover, opponents):
				continue
			var key := _outcome_key(command, mover, grid)
			var outcome: Dictionary = outcomes.get(key, {}) if not key.is_empty() else {}
			if outcome.is_empty():
				memo.simulations += 1
				outcome = _outcome(position, mover, command, memo.keys)
				if outcome.is_empty():
					continue
				if not key.is_empty():
					outcomes[key] = outcome
			var health_after: int = outcome.health_after
			var defeated: bool = outcome.defeated
			if not key.is_empty():
				# The actor stands outside the area: only its route and turn end touch it.
				health_after = actor.health.current - int(forecast.damage)
				defeated = bool(forecast.lethal)
			var scored := _score(cell, outcome, health_after, defeated, context)
			_keep(best, scored, move if move != null else command, unit_id, move != null)
	return best


## Losses on each side when the mover takes the command, from a forecast; {} if rejected.
static func _outcome(position: BattleEngine, mover: UnitState, command: BattleCommand, keys: Array[StringName]) -> Dictionary:
	var preview := ActionPreview.build(position.fork_for_prediction(), position, command)
	if not preview.accepted:
		return {}
	var outcome := {"enemy_damage": 0, "kills": 0, "key_damage": 0, "key_kills": 0, "friendly_damage": 0, "friendly_kills": 0, "health_after": mover.health.current, "defeated": false}
	for changed_id: StringName in preview.units:
		var change := preview.units[changed_id] as ActionPreview.UnitChange
		var lost := change.health_before - change.health_after
		var unit := position.get_unit(changed_id)
		if changed_id == mover.unit_id:
			outcome.health_after = change.health_after
			outcome.defeated = change.defeated
		elif unit != null and unit.faction != mover.faction:
			outcome.enemy_damage += lost
			outcome.kills += int(change.defeated)
			if keys.has(changed_id):
				outcome.key_damage += lost
				outcome.key_kills += int(change.defeated)
		else:
			outcome.friendly_damage += lost
			outcome.friendly_kills += int(change.defeated)
	return outcome


## Identifies an area ability outcome that does not depend on where the actor stands, or "".
static func _outcome_key(command: BattleCommand, mover: UnitState, grid: HexGrid) -> String:
	if not command is UseAbilityCommand or not command.targets_hex:
		return ""
	var ability := mover.get_ability(command.ability_id)
	if ability == null or ability.melee_attack or ability.target_mode in AILastActionPlanner.ORIGIN_MODES or not AILastActionPlanner.is_local(ability):
		return ""
	if AbilityExecutor.get_affected_hexes(grid, mover.hex, ability, command.target_hex).has(mover.hex):
		return ""
	return "%s@%s" % [ability.id, command.target_hex]


## Score of a plan ending on `cell` with the outcome's losses on each side ({} for no action).
static func _score(cell: Vector2i, outcome: Dictionary, health_after: int, defeated: bool, context: Dictionary) -> Dictionary:
	var enemy_damage: int = outcome.get("enemy_damage", 0)
	var self_loss: int = int(context.health_before) - health_after
	var threat := mini(int(context.threat.get(cell, 0)), maxi(health_after, 0))
	var score := enemy_damage + KILL_BONUS * int(outcome.get("kills", 0))
	score += KEY_DAMAGE_WEIGHT * int(outcome.get("key_damage", 0)) + KEY_KILL_BONUS * int(outcome.get("key_kills", 0))
	score -= FRIENDLY_DAMAGE_WEIGHT * int(outcome.get("friendly_damage", 0)) + FRIENDLY_KILL_PENALTY * int(outcome.get("friendly_kills", 0))
	score -= SELF_DAMAGE_WEIGHT * self_loss + (SELF_DEATH_PENALTY if defeated else 0.0)
	score -= THREAT_WEIGHT * threat * (2.0 if context.key else 1.0)
	# Without damage the position matters: get closer, and pin shooters down in melee.
	if enemy_damage <= 0:
		score -= APPROACH_WEIGHT * float(context.approach)
	if int(context.range) <= 1:
		for shooter: Vector2i in context.shooters:
			if HexGrid.get_distance(shooter, cell) == 1:
				score += SHOOTER_PRESSURE_BONUS
	return {"score": score, "enemy_damage": enemy_damage, "approach_gain": int(context.start_approach) - int(context.approach)}


## The farthest distance any of the unit's attacks or abilities can affect from its hex.
static func _action_reach(unit: UnitState) -> int:
	var reach := unit.basic_attack_range
	for ability_id: StringName in unit.abilities:
		var ability := unit.get_ability(ability_id)
		var extent := ability.get_range(unit) + ability.area_radius
		# Lines and paths run on to the edge of the map.
		if ability.target_mode in [AbilityDefinition.TargetMode.LINE, AbilityDefinition.TargetMode.PATH]:
			extent = 1000
		reach = maxi(reach, extent)
	return reach


static func _in_reach(cell: Vector2i, opponents: Array[UnitSnapshot], reach: int) -> bool:
	for opponent: UnitSnapshot in opponents:
		if HexGrid.get_distance(cell, opponent.hex) <= reach:
			return true
	return false


## A terrain ability whose area holds no opponent and borders none is not worth a forecast.
static func _misses_everyone(command: BattleCommand, mover: UnitState, opponents: Array[UnitSnapshot]) -> bool:
	if not command is UseAbilityCommand or not command.targets_hex:
		return false
	var ability := mover.get_ability(command.ability_id)
	if ability == null or ability.target_mode in [AbilityDefinition.TargetMode.LINE, AbilityDefinition.TargetMode.PATH, AbilityDefinition.TargetMode.SELF]:
		return false
	for opponent: UnitSnapshot in opponents:
		if HexGrid.get_distance(command.target_hex, opponent.hex) <= ability.area_radius + 1:
			return false
	return true


static func _keep(best: Dictionary, scored: Dictionary, command: BattleCommand, unit_id: StringName, moves: bool) -> void:
	if scored.is_empty():
		return
	# Equal scores keep the earlier plan: cells and actions come in a stable order.
	if not best.is_empty() and scored.score <= best.score:
		return
	best.merge(scored, true)
	best["command"] = command
	best["unit_id"] = unit_id
	best["moves"] = moves


## Damage the opponents could deal to a unit standing on each hex in their next phase.
static func _threat_map(session: BattleSession, opponents: Array[UnitSnapshot]) -> Dictionary[Vector2i, int]:
	var threat: Dictionary[Vector2i, int] = {}
	for opponent: UnitSnapshot in opponents:
		var reach := session.get_reach(opponent.unit_id)
		for hex: Vector2i in reach.attack:
			threat[hex] = int(threat.get(hex, 0)) + opponent.basic_attack_damage
	return threat


static func _approach(hex: Vector2i, opponents: Array[UnitSnapshot], costs: Array[Dictionary]) -> int:
	var closest := 1000
	for index in range(opponents.size()):
		closest = mini(closest, int(costs[index].get(hex, HexGrid.get_distance(hex, opponents[index].hex))))
	return closest
