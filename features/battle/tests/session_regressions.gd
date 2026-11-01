extends RefCounted
## Battle session: commands, control of summoned units and headless simulation.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")


func run_commands(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var p := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var e := fixture.unit(&"e", BattleFaction.Value.ENEMY, Vector2i(1, 0))
	var state := fixture.state([p.hex, e.hex, Vector2i(2, 0)], [p, e])
	var engine := BattleEngine.new(state)
	var hp := e.health.current
	var revision := state.state_revision
	var invalid := engine.execute(AttackCommand.new(e.unit_id, p.unit_id))
	suite.expect(not invalid.accepted and state.state_revision == revision and e.health.current == hp, "Rejected attack is side-effect free")
	var attack := engine.execute(AttackCommand.new(p.unit_id, e.unit_id))
	suite.expect(attack.accepted and engine.get_active_unit_id() == e.unit_id, "Basic attack ends own turn")
	var ability := fixture.ability(&"core:test_ability", AbilityDefinition.TargetMode.ENEMY)
	p.abilities[ability.id] = ability
	engine.execute(EndTurnCommand.new(e.unit_id))
	var ability_result := engine.execute(UseAbilityCommand.new(p.unit_id, e.unit_id, ability.id))
	suite.expect(ability_result.accepted and p.ability_cooldowns[ability.id] == 2, "Ability starts cooldown and ends turn")
	engine.execute(EndTurnCommand.new(e.unit_id))
	suite.expect(engine.get_ability_target_hexes(p.unit_id, ability.id).is_empty(), "Cooldown one blocks next own turn")
	engine.execute(EndTurnCommand.new(p.unit_id))
	engine.execute(EndTurnCommand.new(e.unit_id))
	suite.expect(not engine.get_ability_target_hexes(p.unit_id, ability.id).is_empty(), "Cooldown expires on following own turn")
	engine.set("_terminal_error", "Injected stopped state")
	var stopped_revision := state.state_revision
	suite.expect(not engine.execute(EndTurnCommand.new(p.unit_id)).accepted, "Terminal engine rejects further commands")
	suite.expect(not engine.apply_map_mutations([MapMutation.apply_hex_state(p.hex, &"core:fire")]).accepted and state.state_revision == stopped_revision, "Terminal engine rejects external mutations")
	var p2 := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO, 1)
	var e2 := fixture.unit(&"e", BattleFaction.Value.ENEMY, Vector2i(1, 0), 1)
	state = fixture.state([p2.hex, e2.hex], [p2, e2])
	state.hex_grid.set_hex_state(p2.hex, &"core:fire")
	state.hex_grid.set_hex_state(e2.hex, &"core:fire")
	engine = BattleEngine.new(state)
	suite.expect(engine.get_result() != null and engine.get_outcome() == BattleOutcome.Value.DEFEAT, "Simultaneous starting defeat preserves protected-faction policy")


func run_summon_control(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var request := fixture.request()
	if request == null:
		return
	var session := BattleSessionFactory.create(request).session
	var state: BattleState = session.get("_state")
	var active := state.unit_states[session.get_active_unit_id()] as UnitState
	var ability := request.content_snapshot.get_ability_definition(&"core:electric_turret")
	active.abilities[ability.id] = ability
	var targets := session.get_ability_target_hexes(active.unit_id, ability.id)
	suite.expect(not targets.is_empty(), "Summon has an empty target")
	if targets.is_empty():
		return
	var result := session.step(UseAbilityCommand.at_hex(active.unit_id, targets[0], ability.id))
	var summoned := StringName()
	for event: BattleEvent in result.events:
		if event is UnitSummonedEvent:
			summoned = event.unit.unit_id
	suite.expect(result.accepted and not summoned.is_empty(), "Summon creates registered participant")
	var side_ids: Dictionary = session.get("_unit_side_ids")
	var profile := request.content_snapshot.get_ai_profile_definition(&"core:basic_enemy_ai")
	suite.expect(session.set_side_command_source(side_ids[active.unit_id], AICommandSource.new(profile)), "Can change side command source after summon")
	suite.expect(session.is_unit_ai_controlled(summoned), "Summon follows changed side control")


func run_simulation(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var request := fixture.request()
	if request == null:
		return
	var profile := request.content_snapshot.get_ai_profile_definition(&"core:basic_enemy_ai")
	var run := SimulationRunner.new().run(SimulationRequest.new(request, profile, 1, 100))
	suite.expect(run.status == SimulationRunStatus.Value.LIMIT_REACHED or run.status == SimulationRunStatus.Value.COMPLETED, "Simulation has explicit bounded result")
	var deterministic_a := SimulationRunner.new().run(SimulationRequest.new(request, profile, 500, 100))
	var deterministic_b := SimulationRunner.new().run(SimulationRequest.new(request, profile, 500, 100))
	suite.expect(deterministic_a.status == deterministic_b.status and deterministic_a.command_count == deterministic_b.command_count and deterministic_a.round_number == deterministic_b.round_number, "Same seed and content produce same simulation summary")
	suite.expect(deterministic_a.status == SimulationRunStatus.Value.COMPLETED, "Regression battle completes in headless simulation")
	var campaign_packages: Array[ContentPackage] = [load("res://content/packages/core/core_package.tres"), load("res://content/packages/ember_pack/ember_pack.tres")]
	var content := ContentLoader.load_packages(campaign_packages).snapshot
	var campaign := CampaignSession.create(content, &"ember_pack:two_battles")
	suite.expect(campaign != null, "Core campaign can be created")
	if campaign != null:
		var unfinished := BattleResult.new(campaign.get_current_battle_id(), 7, BattleOutcome.Value.IN_PROGRESS, 1, null)
		var current := campaign.current_scenario_id
		suite.expect(not campaign.complete_battle(unfinished).accepted and campaign.current_scenario_id == current and campaign.completed_scenario_ids.is_empty(), "Campaign refuses unfinished battle without changing progress")
	var token := SimulationCancellationToken.new()
	token.cancel()
	run = SimulationRunner.new().run(SimulationRequest.new(request, profile, 100, 100, token))
	suite.expect(run.status == SimulationRunStatus.Value.CANCELLED, "Cancellation before start respected")
	var speed := BattlePlaybackSettings.new()
	suite.expect(not speed.set_speed(NAN) and not speed.set_speed(INF) and not speed.set_speed(0), "Nonfinite and nonpositive speeds rejected")
