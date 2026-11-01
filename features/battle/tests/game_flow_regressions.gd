extends RefCounted
## The game build always leads somewhere: a finished battle shows its result with a replay
## and an exit, and a battle that cannot end can still be restarted or left from the menu.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")
const LAUNCHER := preload("res://features/game/game_launcher.gd")

const FRAME_LIMIT := 240


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	_check_result_losses(suite, fixture)
	_check_result_panel(suite)
	await _check_launcher(suite, fixture)


func _check_result_losses(suite: Node, fixture: Fixtures) -> void:
	var cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)]
	var hero: UnitState = fixture.unit(&"hero", BattleFaction.Value.PLAYER, Vector2i.ZERO, 10)
	var ally: UnitState = fixture.unit(&"ally", BattleFaction.Value.PLAYER, Vector2i(2, 0), 10)
	var foe: UnitState = fixture.unit(&"foe", BattleFaction.Value.ENEMY, Vector2i(1, 0), 2)
	ally.health.current = 0
	var units: Array[UnitState] = [hero, foe, ally]
	var state: BattleState = fixture.state(cells, units)
	state.turn_service.start()
	var engine := BattleEngine.new(state, false)
	var resolution := engine.execute(AttackCommand.new(hero.unit_id, foe.unit_id))
	var result := resolution.battle_result
	suite.expect(result != null and result.outcome == BattleOutcome.Value.VICTORY, "The fixture battle ends in victory")
	if result == null:
		return
	var counts := [result.participants.get(BattleFaction.Value.PLAYER), result.participants.get(BattleFaction.Value.ENEMY), result.defeated.get(BattleFaction.Value.PLAYER), result.defeated.get(BattleFaction.Value.ENEMY)]
	suite.expect(counts == [2, 1, 1, 1] and result.participants.size() == 2 and result.defeated.size() == 2, "BattleResult counts participants and losses per side: %s" % str(counts))
	var report := SimulationRunResult.new(SimulationRunStatus.Value.COMPLETED, result, "Battle completed.", 1, result.round_number, 7).to_report()
	suite.expect(report.battle_result.losses == {"PLAYER": {"participants": 2, "defeated": 1}, "ENEMY": {"participants": 1, "defeated": 1}}, "Simulation reports carry the losses")


func _check_result_panel(suite: Node) -> void:
	var defeat := BattleResult.new(&"test:battle", 1, BattleOutcome.Value.DEFEAT, 6, ObjectiveResult.new("Победить всех врагов", false))
	defeat.participants = {BattleFaction.Value.PLAYER: 3, BattleFaction.Value.ENEMY: 4}
	defeat.defeated = {BattleFaction.Value.PLAYER: 3, BattleFaction.Value.ENEMY: 1}
	var panel := BattleResultPanel.create(defeat)
	var text := "%s|%s|%s" % [(panel.find_child("Title", true, false) as Label).text, (panel.find_child("Objective", true, false) as Label).text, (panel.find_child("Summary", true, false) as Label).text]
	suite.expect("ПОРАЖЕНИЕ" in text and "Цель провалена: Победить всех врагов" in text and "Раундов: 6" in text and "Потери отряда: 3 из 3" in text and "Потери противника: 1 из 4" in text, "The result panel shows the outcome, objective, rounds and both sides' losses")
	var pressed: Array[String] = []
	panel.restart_requested.connect(func() -> void: pressed.append("restart"))
	panel.quit_requested.connect(func() -> void: pressed.append("quit"))
	(panel.find_child("Restart", true, false) as Button).pressed.emit()
	(panel.find_child("Quit", true, false) as Button).pressed.emit()
	suite.expect(pressed == ["restart", "quit"], "Result panel buttons request a replay and an exit")
	panel.free()


func _check_launcher(suite: Node, fixture: Fixtures) -> void:
	var launcher: Node = LAUNCHER.new()
	launcher.start_configured_battle = false
	var quits := [0]
	launcher.quit_game = func() -> void: quits[0] += 1
	suite.add_child(launcher)
	suite.expect(launcher.start(fixture.request(true)), "The launcher starts a fixed battle request")
	var first: BattleScreen = launcher.get("_screen")
	await _settle(suite, first)
	var menu := first.find_child("MenuActions", true, false) as VBoxContainer
	var labels: Array[String] = []
	if menu != null:
		for button: Button in menu.get_children():
			labels.append(button.text)
	suite.expect(labels == ["НАЧАТЬ БОЙ ЗАНОВО", "ВЫЙТИ ИЗ ИГРЫ"], "The battle menu offers a restart and an exit: %s" % ", ".join(labels))
	var hud := first.get_node("BattleMap/BattleUI") as BattleHUD
	hud.set_interaction_enabled(false)
	suite.expect(menu != null and not (menu.get_child(0) as Button).disabled and not (menu.get_child(1) as Button).disabled, "Restart and exit stay available while the battle is busy or over")
	(menu.get_child(1) as Button).pressed.emit()
	suite.expect(quits[0] == 1, "The menu exit leaves the game")

	var victory := BattleResult.new(&"test:battle", 1, BattleOutcome.Value.VICTORY, 4, ObjectiveResult.new("Победить всех врагов", true))
	victory.participants = {BattleFaction.Value.PLAYER: 3, BattleFaction.Value.ENEMY: 3}
	victory.defeated = {BattleFaction.Value.PLAYER: 1, BattleFaction.Value.ENEMY: 3}
	first.battle_finished.emit(victory)
	var overlay: CanvasLayer = launcher.get("_overlay")
	var panel := overlay.find_child("BattleResultPanel", true, false) as BattleResultPanel if overlay != null else null
	suite.expect(panel != null and "Потери противника: 3 из 3" in (panel.find_child("Summary", true, false) as Label).text, "A finished battle shows its result panel")
	(panel.find_child("Quit", true, false) as Button).pressed.emit()
	suite.expect(quits[0] == 2, "The result panel exit leaves the game")

	(panel.find_child("Restart", true, false) as Button).pressed.emit()
	launcher.call("restart")
	for _frame in range(FRAME_LIMIT):
		if launcher.get("_screen") != null:
			break
		await suite.get_tree().process_frame
	var second: BattleScreen = launcher.get("_screen")
	var screens := launcher.get_children().filter(func(child: Node) -> bool: return child is BattleScreen)
	suite.expect(second != null and second != first and not is_instance_valid(first) and screens.size() == 1, "Replay replaces the finished battle with exactly one fresh one")
	suite.expect(launcher.get("_overlay") == null and launcher.find_child("BattleResultPanel", true, false) == null, "Replay removes the result panel")
	await _settle(suite, second)
	var session: BattleSession = second.get("_battle_controller").get("_battle_session")
	suite.expect(session.get_round_number() == 1 and not session.is_finished() and second.find_child("MenuActions", true, false) != null, "The replay starts the same battle from its first round with the menu actions")

	launcher.call("_show_message", "Бой остановлен из-за ошибки:\nтест")
	(second.find_child("MenuActions", true, false).get_child(0) as Button).pressed.emit()
	for _frame in range(FRAME_LIMIT):
		if launcher.get("_screen") != null and launcher.get("_screen") != second:
			break
		await suite.get_tree().process_frame
	var third: BattleScreen = launcher.get("_screen")
	suite.expect(third != null and third != second and not is_instance_valid(second) and launcher.get("_overlay") == null, "Restart from the menu works mid-battle and clears a failure message")
	await _settle(suite, third)
	launcher.queue_free()
	await suite.get_tree().process_frame


## Waits until the battle has played its start and waits for the player.
func _settle(suite: Node, screen: BattleScreen) -> void:
	if screen == null:
		return
	var controller: BattleController = screen.get("_battle_controller")
	for _frame in range(FRAME_LIMIT):
		await suite.get_tree().process_frame
		if controller.get("_is_initialized") and not controller.get("_is_presenting"):
			return
