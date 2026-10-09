class_name AICommandSource
extends CommandSource


const BASIC_MELEE_POLICY := &"basic_melee"

var profile: AIProfileDefinition
## Populated only while a diagnostic observer is attached. Never used for decisions.
var decision_trace: Variant = null


func _init(p_profile: AIProfileDefinition) -> void:
	profile = p_profile


static func supports(p_profile: AIProfileDefinition) -> bool:
	return (
		p_profile != null
		and p_profile.policy_id == BASIC_MELEE_POLICY
	)


func is_automatic() -> bool:
	return true


func next_command(session: BattleSession) -> BattleCommand:
	if session == null or session.is_finished():
		return null

	var active_unit_id := session.get_active_unit_id()
	var active := session.get_unit(active_unit_id)

	if active == null or active.health.is_defeated():
		_trace("reason", "active_missing_or_defeated")
		return EndTurnCommand.new(active_unit_id)

	if not active.turn.main_action_available:
		_trace("reason", "main_action_unavailable")
		return EndTurnCommand.new(active_unit_id)

	var opponents := session.get_living_opponents(active.faction)
	var target := EnemyBrain.choose_target(active.hex, opponents)
	_trace("opponents", opponents)
	_trace("approach_target", target)

	if target == null:
		_trace("reason", "no_opponents")
		return EndTurnCommand.new(active_unit_id)

	var last_action := AILastActionPlanner.plan(session, decision_trace)
	if not last_action.is_empty():
		_trace("reason", last_action.reason)
		return last_action.command

	# Prefer an ordinary attack when it can already reach an opponent.
	var attackable_targets := session.get_attackable_targets(active.unit_id)
	_trace("attackable_targets", attackable_targets)
	var attack_target := EnemyBrain.choose_target(
		active.hex,
		attackable_targets
	)

	if attack_target != null:
		_trace("reason", "basic_attack_in_range")
		return AttackCommand.new(active.unit_id, attack_target.unit_id)

	var ability_command := _choose_ability_command(session, active, opponents)

	if ability_command != null:
		_trace("reason", "first_safe_usable_ability")
		return ability_command

	if active.turn.movement_remaining <= 0:
		_trace("reason", "movement_exhausted")
		var obstacle_command := _choose_obstacle_command(session, active, target)
		return obstacle_command if obstacle_command != null else EndTurnCommand.new(active_unit_id)

	var movement_search := session.get_movement_search(active.unit_id)
	var move := EnemyBrain.choose_move(
		active.unit_id,
		active.hex,
		target.hex,
		movement_search,
		session.get_hex_grid(),
		active.health.current,
		active.basic_attack_range,
		active,
		decision_trace
	)

	if move != null:
		_trace("reason", "approach_with_hazard_forecast")
		return move

	var obstacle_command := _choose_obstacle_command(session, active, target)
	if obstacle_command != null:
		return obstacle_command

	_trace("reason", "no_improving_safe_move")
	return EndTurnCommand.new(active_unit_id)


func _choose_obstacle_command(session: BattleSession, active: UnitSnapshot, target: UnitSnapshot) -> AttackObstacleCommand:
	var grid := session.get_hex_grid()
	var candidates := grid.get_cells_in_range(active.hex, active.basic_attack_range)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return HexGrid.get_distance(a, target.hex) < HexGrid.get_distance(b, target.hex) if HexGrid.get_distance(a, target.hex) != HexGrid.get_distance(b, target.hex) else a < b)
	for hex: Vector2i in candidates:
		var obstacle := grid.get_obstacle(hex)
		if obstacle != null and obstacle.destructible and HexGrid.get_distance(hex, target.hex) < HexGrid.get_distance(active.hex, target.hex):
			_trace("reason", "clear_destructible_obstacle")
			return AttackObstacleCommand.new(active.unit_id, hex)
	return null


func _choose_ability_command(
	session: BattleSession,
	active: UnitSnapshot,
	opponents: Array[UnitSnapshot]
) -> UseAbilityCommand:
	var allies := session.get_living_units_by_faction(active.faction)
	_trace("allies", allies)
	if decision_trace != null:
		decision_trace["ability_candidates"] = []

	for ability_id: StringName in active.ability_ids:
		var target_hexes := session.get_ability_target_hexes(
			active.unit_id,
			ability_id
		)
		var radius: int = active.ability_area_radii.get(ability_id, 0)
		var mode: int = active.ability_target_modes.get(ability_id, AbilityDefinition.TargetMode.AUTO)
		var evaluations: Array = []
		if decision_trace != null:
			decision_trace["ability_candidates"].append({"ability_id": ability_id, "legal_hexes": target_hexes, "radius": radius, "target_mode": mode, "cooldown": active.ability_cooldowns.get(ability_id, 0), "evaluations": evaluations})
		if mode == AbilityDefinition.TargetMode.EMPTY_HEX:
			if not target_hexes.is_empty():
				return UseAbilityCommand.at_hex(active.unit_id, target_hexes[0], ability_id)
			continue
		if mode == AbilityDefinition.TargetMode.LINE:
			var ability := AbilityDefinition.new()
			ability.target_mode = AbilityDefinition.TargetMode.LINE
			for center: Vector2i in target_hexes:
				var cells := AbilityExecutor.get_affected_hexes(session.get_hex_grid(), active.hex, ability, center)
				var hits := 0
				var friendly := false
				for ally: UnitSnapshot in allies:
					friendly = friendly or cells.has(ally.hex)
				for enemy: UnitSnapshot in opponents:
					if cells.has(enemy.hex):
						hits += 1
				if decision_trace != null:
					evaluations.append({"center": center, "affected_hexes": cells, "enemy_hits": hits, "friendly_fire": friendly})
				if hits > 0 and not friendly:
					return UseAbilityCommand.at_hex(active.unit_id, center, ability_id)
			continue
		if not active.ability_hex_targets.get(ability_id, false):
			for opponent: UnitSnapshot in opponents:
				if decision_trace != null:
					evaluations.append({"target_id": opponent.unit_id, "legal": target_hexes.has(opponent.hex), "allies_in_radius": _count_units_in_radius(opponent.hex, radius, allies) if radius > 0 else 0})
				if target_hexes.has(opponent.hex) and (radius == 0 or _count_units_in_radius(opponent.hex, radius, allies) == 0):
					return UseAbilityCommand.new(active.unit_id, opponent.unit_id, ability_id)
			continue

		if radius <= 0:
			for opponent: UnitSnapshot in opponents:
				if target_hexes.has(opponent.hex):
					return UseAbilityCommand.at_hex(
						active.unit_id,
						opponent.hex,
						ability_id
					)

			continue

		var best_count := 0
		var best_center := Vector2i.ZERO

		for center: Vector2i in target_hexes:
			if decision_trace != null:
				evaluations.append({"center": center, "allies_in_radius": _count_units_in_radius(center, radius, allies), "enemies_in_radius": _count_units_in_radius(center, radius, opponents)})
			# Allies include the acting unit, so the blast never covers it.
			if _count_units_in_radius(center, radius, allies) > 0:
				continue

			var count := _count_units_in_radius(center, radius, opponents)

			if count > best_count:
				best_count = count
				best_center = center

		if best_count > 0:
			return UseAbilityCommand.at_hex(
				active.unit_id,
				best_center,
				ability_id
			)

	return null


static func _count_units_in_radius(
	center: Vector2i,
	radius: int,
	units: Array[UnitSnapshot]
) -> int:
	var count := 0

	for unit: UnitSnapshot in units:
		if HexGrid.get_distance(center, unit.hex) <= radius:
			count += 1

	return count


func _trace(key: String, value: Variant) -> void:
	if decision_trace != null:
		decision_trace[key] = value
