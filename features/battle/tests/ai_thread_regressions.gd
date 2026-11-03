extends RefCounted
## The AI decides on a detached copy of the battle, so the graphical battle computes it on a
## worker thread: the same choice as on the calling thread, the live battle untouched until the
## decision is finished, frames keep coming, and a battle closed mid-decision waits for it.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")

## Tactical decisions compared between the calling thread and a pool thread.
const COMPARED_COMMANDS := 6
const FRAME_LIMIT := 3000


func run(suite: Node) -> void:
	var request := _all_ai_request(suite.fixture)
	suite.expect(request != null, "The regression battle loads with every side under the tactical AI")
	if request == null:
		return
	_check_live_battle_untouched(suite, request)
	_check_worker_matches_caller(suite, request)
	_check_stale_decision(suite, request)
	_check_diagnostics_on_finishing_thread(suite, request)
	await _check_graphical_battle(suite, request)


## The regression battle with every side under the tactical AI.
func _all_ai_request(fixture: Fixtures) -> BattleStartRequest:
	var loaded := fixture.request(true)
	if loaded == null:
		return null
	var snapshot := loaded.content_snapshot
	var battle := snapshot.get_battle_definition(loaded.battle_id)
	for side: BattleSideDefinition in battle.sides:
		side.control_source = BattleControlSource.Value.AI
		side.ai_profile_id = &"core:tactical_enemy_ai"
	return BattleStartRequest.new(battle.id, snapshot.with_battle_document(snapshot.get_map_definition(battle.map_id), battle), loaded.deterministic_seed)


func _check_live_battle_untouched(suite: Node, request: BattleStartRequest) -> void:
	var session := BattleSessionFactory.create(request).session
	var before := _state(session)
	var decision := session.prepare_ai_decision()
	suite.expect(decision != null, "An AI side prepares a decision")
	if decision == null:
		return
	decision.compute()
	suite.expect(decision.command != null and _state(session) == before, "Planning on the copy leaves the live battle unchanged")
	suite.expect(session.finish_ai_decision(decision) == decision.command, "A fresh decision hands over its command")


## Decisions computed on a pool thread equal the decisions made on the calling thread.
func _check_worker_matches_caller(suite: Node, request: BattleStartRequest) -> void:
	var caller := BattleSessionFactory.create(request).session
	var worker := BattleSessionFactory.create(request).session
	var same := true
	var commands := 0
	while same and commands < COMPARED_COMMANDS and not caller.is_finished():
		var expected := caller.get_next_ai_command()
		var decision := worker.prepare_ai_decision()
		if expected == null or decision == null:
			same = false
			break
		WorkerThreadPool.wait_for_task_completion(WorkerThreadPool.add_task(decision.compute))
		var command := worker.finish_ai_decision(decision)
		same = _encode(command) == _encode(expected) and caller.step(expected).accepted and worker.step(command).accepted
		commands += 1
	suite.expect(same and commands > 0 and _state(caller) == _state(worker), "A pool thread plays the same commands as the calling thread (%d commands)" % commands)


func _check_stale_decision(suite: Node, request: BattleStartRequest) -> void:
	var session := BattleSessionFactory.create(request).session
	var decision := session.prepare_ai_decision()
	decision.compute()
	var stepped := session.step(decision.command)
	suite.expect(stepped.accepted and session.finish_ai_decision(decision) == null, "A decision prepared before the battle changed is discarded")


func _check_diagnostics_on_finishing_thread(suite: Node, request: BattleStartRequest) -> void:
	var session := BattleSessionFactory.create(request).session
	var records: Array[Dictionary] = []
	session.diagnostic_record.connect(func(kind: String, data: Dictionary) -> void:
		if kind == "ai_decision":
			records.append({"thread": OS.get_thread_caller_id(), "reason": data.trace.get("reason", "")})
	)
	var decision := session.prepare_ai_decision()
	WorkerThreadPool.wait_for_task_completion(WorkerThreadPool.add_task(decision.compute))
	var command := session.finish_ai_decision(decision)
	suite.expect(command != null and records.size() == 1 and records[0].thread == OS.get_main_thread_id() and not String(records[0].reason).is_empty(), "A pool-thread decision is published once, on the finishing thread, with its reason")


## Frames keep coming while the AI thinks; closing the battle then waits for the planner.
func _check_graphical_battle(suite: Node, request: BattleStartRequest) -> void:
	var screen := preload("res://features/battle/battle_screen.tscn").instantiate() as BattleScreen
	suite.expect(screen.setup(request), "The all-AI battle screen starts")
	suite.add_child(screen)
	var controller: BattleController = screen.get("_battle_controller")
	controller.set_playback_speed(4.0)
	var deciding_frames := 0
	for _frame in range(FRAME_LIMIT):
		deciding_frames = deciding_frames + 1 if controller.is_ai_deciding() else 0
		if deciding_frames >= 2:
			break
		await suite.get_tree().process_frame
	suite.expect(deciding_frames >= 2, "Frames keep coming while the AI decides on a worker thread")
	var decision: AIDecision = controller.get("_ai_decision")
	screen.queue_free()
	await suite.get_tree().process_frame
	suite.expect(not is_instance_valid(screen) and decision != null and decision.command != null, "A battle closed mid-decision is freed after its planner finished")


func _state(session: BattleSession) -> String:
	return JSON.stringify(BattleLogSerializer.encode(session.get_diagnostic_state()))


func _encode(command: BattleCommand) -> String:
	return JSON.stringify(BattleLogSerializer.encode(command))
