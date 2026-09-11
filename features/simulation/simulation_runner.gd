class_name SimulationRunner
extends RefCounted


func run(request: SimulationRequest) -> SimulationRunResult:
	if request == null or request.battle_start_request == null:
		return SimulationRunResult.new(
			SimulationRunStatus.Value.INVALID_SETUP,
			null,
			"SimulationRequest requires a BattleStartRequest.",
			0,
			0,
			0
		)

	var seed := request.battle_start_request.deterministic_seed

	if request.max_commands <= 0 or request.max_rounds <= 0:
		return SimulationRunResult.new(
			SimulationRunStatus.Value.INVALID_SETUP,
			null,
			"Simulation limits must be positive.",
			0,
			0,
			seed
		)

	if request.cancellation_token.is_cancelled():
		return SimulationRunResult.new(
			SimulationRunStatus.Value.CANCELLED,
			null,
			"Simulation was cancelled before start.",
			0,
			0,
			seed
		)

	var creation := BattleSessionFactory.create(request.battle_start_request)

	if not creation.is_successful:
		return SimulationRunResult.new(
			SimulationRunStatus.Value.INVALID_SETUP,
			null,
			creation.error_message,
			0,
			0,
			seed
		)

	var session := creation.session
	var configuration_error := _connect_ai_to_all_sides(
		session,
		request.fallback_ai_profile
	)

	if not configuration_error.is_empty():
		return SimulationRunResult.new(
			SimulationRunStatus.Value.INVALID_SETUP,
			null,
			configuration_error,
			0,
			session.get_round_number(),
			seed
		)

	var command_count := 0

	while not session.is_finished():
		if request.cancellation_token.is_cancelled():
			return _finish(
				SimulationRunStatus.Value.CANCELLED,
				session,
				"Simulation was cancelled.",
				command_count,
				seed
			)

		if command_count >= request.max_commands:
			return _finish(
				SimulationRunStatus.Value.LIMIT_REACHED,
				session,
				"Command limit reached.",
				command_count,
				seed
			)

		if session.get_round_number() > request.max_rounds:
			return _finish(
				SimulationRunStatus.Value.LIMIT_REACHED,
				session,
				"Round limit reached.",
				command_count,
				seed
			)

		var command := session.get_next_ai_command()

		if command == null:
			return _finish(
				SimulationRunStatus.Value.AI_ERROR,
				session,
				"AI did not produce a command for the active unit.",
				command_count,
				seed
			)

		var resolution := session.step(command)

		if not resolution.accepted:
			return _finish(
				SimulationRunStatus.Value.AI_ERROR,
				session,
				"AI command was rejected: %s" % resolution.rejection_reason,
				command_count,
				seed
			)

		command_count += 1

	return _finish(
		SimulationRunStatus.Value.COMPLETED,
		session,
		"Battle completed.",
		command_count,
		seed
	)


func _connect_ai_to_all_sides(
	session: BattleSession,
	fallback_profile: AIProfileDefinition
) -> String:
	for side: BattleSideData in session.setup.sides:
		var profile := side.ai_profile_definition

		if not AICommandSource.supports(profile):
			profile = fallback_profile

		if not AICommandSource.supports(profile):
			return "No supported AI profile for side %s." % side.side_id

		if not session.set_side_command_source(
			side.side_id,
			AICommandSource.new(profile)
		):
			return "Could not connect AI to side %s." % side.side_id

	return ""


func _finish(
	status: SimulationRunStatus.Value,
	session: BattleSession,
	reason: String,
	command_count: int,
	seed: int
) -> SimulationRunResult:
	return SimulationRunResult.new(
		status,
		session.get_result(),
		reason,
		command_count,
		session.get_round_number(),
		seed
	)