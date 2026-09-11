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

	var attack := EnemyBrain.choose_attack(
		active.unit_id,
		active.hex,
		target.unit_id,
		target.hex,
		active.turn.main_action_available
	)

	if attack != null:
		return attack

	if active.turn.movement_remaining <= 0:
		return EndTurnCommand.new(active_unit_id)

	var movement_search := session.get_movement_search(active.unit_id)
	var move := EnemyBrain.choose_move(
		active.unit_id,
		active.hex,
		target.hex,
		movement_search
	)

	if move != null:
		return move

	return EndTurnCommand.new(active_unit_id)
