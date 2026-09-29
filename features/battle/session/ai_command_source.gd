class_name AICommandSource
extends CommandSource


const BASIC_MELEE_POLICY := &"basic_melee"

var profile: AIProfileDefinition


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
		return EndTurnCommand.new(active_unit_id)

	if not active.turn.main_action_available:
		return EndTurnCommand.new(active_unit_id)

	var opponents := session.get_living_opponents(active.faction)
	var target := EnemyBrain.choose_target(active.hex, opponents)

	if target == null:
		return EndTurnCommand.new(active_unit_id)

	# Prefer an ordinary attack when it can already reach an opponent.
	var attack_target := EnemyBrain.choose_target(
		active.hex,
		session.get_attackable_targets(active.unit_id)
	)

	if attack_target != null:
		return AttackCommand.new(active.unit_id, attack_target.unit_id)

	var ability_command := _choose_ability_command(session, active, opponents)

	if ability_command != null:
		return ability_command

	if active.turn.movement_remaining <= 0:
		return EndTurnCommand.new(active_unit_id)

	var movement_search := session.get_movement_search(active.unit_id)
	var move := EnemyBrain.choose_move(
		active.unit_id,
		active.hex,
		target.hex,
		movement_search,
		session.get_hex_grid(),
		active.health.current,
		active.basic_attack_range
	)

	if move != null:
		return move

	return EndTurnCommand.new(active_unit_id)


func _choose_ability_command(
	session: BattleSession,
	active: UnitSnapshot,
	opponents: Array[UnitSnapshot]
) -> UseAbilityCommand:
	var allies := session.get_living_units_by_faction(active.faction)

	for ability_id: StringName in active.ability_ids:
		var target_hexes := session.get_ability_target_hexes(
			active.unit_id,
			ability_id
		)
		var radius: int = active.ability_area_radii.get(ability_id, 0)

		if radius <= 0:
			for opponent: UnitSnapshot in opponents:
				if target_hexes.has(opponent.hex):
					return UseAbilityCommand.new(
						active.unit_id,
						opponent.unit_id,
						ability_id
					)

			continue

		var best_count := 0
		var best_center := Vector2i.ZERO

		for center: Vector2i in target_hexes:
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
