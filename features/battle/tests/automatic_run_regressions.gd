extends RefCounted
## Automatic play is bounded by what the rules allow, not by a fixed number of commands:
## long progressing stretches continue, a stuck turn or a stalemate stops with a clear reason.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")

## Six AI units on two far islands: every round takes six automatic commands.
const ISLAND_A: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]
const ISLAND_B: Array[Vector2i] = [Vector2i(12, 0), Vector2i(13, 0), Vector2i(14, 0), Vector2i(12, 1), Vector2i(13, 1), Vector2i(14, 1)]
const FRAME_LIMIT := 6000


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	_check_guard(suite, fixture)
	await _check_stalemate_battle(suite)


func _check_guard(suite: Node, fixture: Fixtures) -> void:
	var unit: UnitState = fixture.unit(&"ai", BattleFaction.Value.ENEMY, Vector2i.ZERO, 10, 3)
	var hit := BattleResolution.success([UnitDamagedEvent.new(&"ai", &"target", 1, 5, false)], 0, &"ai")
	var idle := BattleResolution.success([TurnEndedEvent.new(&"ai", &"ai", 1)], 0, &"ai")

	var guard := AutomaticRunGuard.new()
	var error := ""
	var commands := 0
	for round_number in range(1, 401):
		unit.turns_started += 1
		for index in range(3):
			error = guard.check(UnitSnapshot.new(unit), round_number)
			if not error.is_empty():
				break
			guard.record(hit if index == 0 else idle, round_number)
			commands += 1
		if not error.is_empty():
			break
	suite.expect(error.is_empty() and commands == 1200, "A progressing automatic stretch runs far past the old 128-command limit")

	guard = AutomaticRunGuard.new()
	var stopped_at := _first_stop(guard, unit, 1, 100, idle)
	suite.expect(stopped_at == 1 + AutomaticRunGuard.ROUNDS_WITHOUT_PROGRESS, "Rounds without progress stop automatic play (round %d)" % stopped_at)

	guard = AutomaticRunGuard.new()
	_first_stop(guard, unit, 1, 20, idle)
	guard.record(hit, 20)
	stopped_at = _first_stop(guard, unit, 21, 100, idle)
	suite.expect(stopped_at == 20 + AutomaticRunGuard.ROUNDS_WITHOUT_PROGRESS, "Damage restarts the stalemate count (round %d)" % stopped_at)

	var state_change := MapMutationEvent.new(MapMutationKind.Value.APPLY_HEX_STATE, Vector2i.ZERO, &"core:default", true, 1)
	var harmless := UnitDamagedEvent.new(&"ai", &"target", 0, 5, false)
	var status := UnitStatusChangedEvent.new(unit, {})
	var busy := BattleResolution.success([state_change, harmless, status], 0, &"ai")
	guard = AutomaticRunGuard.new()
	stopped_at = _first_stop(guard, unit, 1, 100, busy)
	suite.expect(stopped_at == 1 + AutomaticRunGuard.ROUNDS_WITHOUT_PROGRESS, "Applied states, absorbed hits and status decay are not progress")
	var obstacle := MapMutationEvent.new(MapMutationKind.Value.SET_TRAVERSAL, Vector2i.ZERO, &"core:default", true, 1)
	obstacle.obstacle_changed = true
	var summoned := UnitSummonedEvent.new(&"ai", unit, UnitDefinition.new())
	var reset_by: Array[String] = []
	for progress: BattleEvent in [obstacle, summoned]:
		guard = AutomaticRunGuard.new()
		_first_stop(guard, unit, 1, 20, idle)
		guard.record(BattleResolution.success([progress], 0, &"ai"), 20)
		if _first_stop(guard, unit, 21, 100, idle) == 20 + AutomaticRunGuard.ROUNDS_WITHOUT_PROGRESS:
			reset_by.append(progress.get_script().get_global_name())
	suite.expect(reset_by.size() == 2, "Obstacle damage and summons are progress: %s" % ", ".join(reset_by))

	guard = AutomaticRunGuard.new()
	var turn_limit := unit.turn.movement_max + 1 + AutomaticRunGuard.TURN_COMMAND_MARGIN
	var accepted := 0
	while guard.check(UnitSnapshot.new(unit), 1).is_empty() and accepted < 100:
		accepted += 1
	suite.expect(accepted == turn_limit, "One turn stops after movement + 1 + margin commands (%d)" % accepted)
	accepted = 0
	guard = AutomaticRunGuard.new()
	for index in range(100):
		if index % 4 == 0:
			unit.turns_started += 1
		if guard.check(UnitSnapshot.new(unit), 1).is_empty():
			accepted += 1
	suite.expect(accepted == 100, "Consecutive turns of the same unit each get their own bound")

	guard = AutomaticRunGuard.new()
	error = ""
	var last_round := 0
	for round_number in range(1, 1000):
		unit.turns_started += 1
		error = guard.check(UnitSnapshot.new(unit), round_number)
		last_round = round_number
		if not error.is_empty():
			break
		guard.record(hit, round_number)
	suite.expect("without player input" in error and last_round == 1 + AutomaticRunGuard.MAX_ROUNDS, "Even a progressing stretch has an absolute round bound (round %d)" % last_round)


## Plays one command per round with the given resolution; returns the round that stopped.
func _first_stop(guard: AutomaticRunGuard, unit: UnitState, from_round: int, to_round: int, resolution: BattleResolution) -> int:
	for round_number in range(from_round, to_round + 1):
		unit.turns_started += 1
		if not guard.check(UnitSnapshot.new(unit), round_number).is_empty():
			return round_number
		guard.record(resolution, round_number)
	return -1


## Two AI sides that can never reach each other: the battle stops with a stalemate after
## more than 128 automatic commands, and every command gives the frame back.
func _check_stalemate_battle(suite: Node) -> void:
	var packages: Array[ContentPackage] = [load("res://content/packages/core/core_package.tres")]
	var content := ContentLoader.load_packages(packages)
	suite.expect(content.is_successful, "Core content loads for the stalemate battle")
	if not content.is_successful:
		return
	var battle := content.snapshot.get_battle_definition(&"core:debug_battle")
	var map := content.snapshot.get_map_definition(battle.map_id)
	map.cells.clear()
	map.obstacles.clear()
	for hex: Vector2i in ISLAND_A + ISLAND_B:
		var cell := BattleMapCellDefinition.new()
		cell.hex = hex
		map.cells.append(cell)
	for side: BattleSideDefinition in battle.sides:
		side.control_source = BattleControlSource.Value.AI
		side.ai_profile_id = &"core:basic_enemy_ai"
	var placements: Array[UnitPlacementDefinition] = []
	for index in range(3):
		for player in [true, false]:
			var placement := UnitPlacementDefinition.new()
			placement.placement_id = StringName("%s_%d" % ["player" if player else "enemy", index])
			placement.definition_id = &"core:debug_player" if player else &"core:debug_enemy"
			placement.side_id = &"player" if player else &"enemy"
			placement.start_hex = ISLAND_A[index] if player else ISLAND_B[index + 3]
			placements.append(placement)
	battle.unit_placements = placements
	var request := BattleStartRequest.new(battle.id, content.snapshot.with_battle_document(map, battle), 3)
	var screen := preload("res://features/battle/battle_screen.tscn").instantiate() as BattleScreen
	suite.expect(screen.setup(request), "Two-AI island battle is accepted")
	suite.add_child(screen)
	var controller: BattleController = screen.get("_battle_controller")
	# The expected stop is asserted here; the screen's handler would log it as an error.
	controller.battle_failed.disconnect(screen._on_battle_failed)
	var stopped := {}
	controller.battle_failed.connect(func(message: String) -> void:
		stopped["message"] = message
		stopped["frame"] = Engine.get_process_frames()
	)
	controller.set_playback_speed(4.0)
	var start_frame := Engine.get_process_frames()
	for _frame in range(FRAME_LIMIT):
		if not stopped.is_empty():
			break
		await suite.get_tree().process_frame
	var session: BattleSession = controller.get("_battle_session")
	var rounds := session.get_round_number()
	suite.expect("no progress" in String(stopped.get("message", "")), "A two-AI stalemate stops with an explicit no-progress reason: %s" % stopped.get("message", "still running"))
	suite.expect(rounds >= AutomaticRunGuard.ROUNDS_WITHOUT_PROGRESS and rounds * placements.size() > 128, "The stalemate runs past the old limit before stopping (%d rounds)" % rounds)
	suite.expect(int(stopped.get("frame", start_frame)) - start_frame >= rounds * placements.size(), "Every automatic command gives the frame back")
	suite.expect(not session.is_finished() and not controller.get("_completion_emitted"), "A stalemate is not reported as a battle result")
	screen.queue_free()
	await suite.get_tree().process_frame
