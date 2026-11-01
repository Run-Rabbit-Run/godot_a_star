extends RefCounted
## Rules live in the core: handlers own their effects, the session answers rule questions,
## and adapters (AI, controller, presentation) ask instead of re-deriving the rules.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")


## Damages every affected hex by one, to prove any handler can strike obstacles.
class Demolish extends AbilityEffectHandler:
	func validate(_effect: AbilityEffectDefinition) -> String:
		return ""

	func execute_obstacles(_effect: AbilityEffectDefinition, context: BattleEffectContext, _source: StringName, hexes: Array[Vector2i]) -> Array[BattleEvent]:
		var events: Array[BattleEvent] = []
		for hex: Vector2i in hexes:
			events.append_array(context.damage_obstacle(hex, 1))
		return events


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	_check_obstacle_damage_belongs_to_handlers(suite, fixture)
	_check_session_answers_rule_questions(suite, fixture)
	await _check_delivery_comes_from_presentation(suite, fixture)


func _check_obstacle_damage_belongs_to_handlers(suite: Node, fixture: Fixtures) -> void:
	var state := _walled_state(fixture)
	var context := BattleEffectContext.new(state, &"core:test")
	context.target_hex = Vector2i(2, 0)
	var effect := AbilityEffectDefinition.new()
	effect.effect_type_id = &"core:damage"
	effect.parameters = {"amount": 4, "secondary_amount": 1}
	var area: Array[Vector2i] = [Vector2i(1, 0), Vector2i(3, 0), Vector2i(2, 1), Vector2i(2, 0)]
	DamageEffectHandler.new().execute_obstacles(effect, context, &"user", area)
	suite.expect(_hp(state, Vector2i(2, 0)) == 6 and _hp(state, Vector2i(2, 1)) == 9, "Damage strikes each obstacle once: full at the center, secondary elsewhere")
	effect.parameters["affects_obstacles"] = false
	suite.expect(DamageEffectHandler.new().execute_obstacles(effect, context, &"user", area).is_empty() and _hp(state, Vector2i(2, 0)) == 6, "Damage with affects_obstacles off leaves obstacles")
	suite.expect(UnitStatusEffectHandler.new().execute_obstacles(effect, context, &"user", area).is_empty(), "Effects that do not strike obstacles leave them by default")

	state = _walled_state(fixture)
	var api := ModAPI.create_default()
	api.register_effect_handler(&"test:demolish", Demolish.new())
	state.mod_api = api
	var user: UnitState = state.unit_states[&"user"]
	var ability: AbilityDefinition = fixture.ability(&"core:demolish", AbilityDefinition.TargetMode.HEX)
	ability.range = 4
	ability.effects[0].effect_type_id = &"test:demolish"
	user.abilities[ability.id] = ability
	user.ability_cooldowns[ability.id] = 0
	state.turn_service.start()
	var resolution := BattleEngine.new(state, false).execute(UseAbilityCommand.at_hex(user.unit_id, Vector2i(2, 1), ability.id))
	suite.expect(resolution.accepted and _hp(state, Vector2i(2, 1)) == 9 and _hp(state, Vector2i(2, 0)) == 10, "The effect pipeline lets any handler strike obstacles, not only core damage")


func _check_session_answers_rule_questions(suite: Node, fixture: Fixtures) -> void:
	var state := _walled_state(fixture)
	var user: UnitState = state.unit_states[&"user"]
	user.basic_attack_range = 3
	var modes := {&"core:line": [AbilityDefinition.TargetMode.LINE, 0], &"core:path": [AbilityDefinition.TargetMode.PATH, 0], &"core:ring": [AbilityDefinition.TargetMode.SELF, 1], &"core:blast": [AbilityDefinition.TargetMode.HEX, 1]}
	for id: StringName in modes:
		var ability: AbilityDefinition = fixture.ability(id, modes[id][0], modes[id][1])
		ability.uses_attack_range = id == &"core:blast"
		user.abilities[id] = ability
		user.ability_cooldowns[id] = 0
	state.turn_service.start()
	var session := _session(state)
	var snapshot := session.get_unit(user.unit_id)
	var blast := snapshot.abilities.get(&"core:blast") as AbilitySnapshot
	suite.expect(snapshot.abilities.keys().size() == snapshot.ability_ids.size() and blast != null and blast.range == 3 and blast.area_radius == 1 and blast.targets_hex and blast.target_mode == AbilityDefinition.TargetMode.HEX, "A unit snapshot carries one read-only snapshot per ability with its effective range")
	var same := true
	for id: StringName in modes:
		for center: Vector2i in [Vector2i(3, 0), Vector2i(2, 1), user.hex]:
			var expected := AbilityExecutor.get_affected_hexes(state.hex_grid, user.hex, user.get_ability(id), center)
			same = same and session.get_ability_affected_hexes(user.unit_id, id, center) == expected
	suite.expect(same, "The session reports affected cells with the geometry execution uses")
	suite.expect(session.get_ability_affected_hexes(user.unit_id, &"core:unknown", Vector2i.ZERO).is_empty() and session.get_ability_affected_hexes(&"nobody", &"core:line", Vector2i.ZERO).is_empty(), "Unknown units and abilities affect nothing")

	var granite := BattleObstacleDefinition.new()
	granite.id = &"granite"
	granite.hexes.assign([Vector2i(1, 1)])
	state.hex_grid.add_obstacle(granite)
	var far := BattleObstacleDefinition.new()
	far.id = &"far"
	far.hexes.assign([Vector2i(5, 0)])
	far.destructible = true
	state.hex_grid.add_obstacle(far)
	var attackable := session.get_attackable_obstacle_hexes(user.unit_id)
	suite.expect(attackable == [Vector2i(2, 0), Vector2i(2, 1), Vector2i(3, 0)], "Attackable obstacles are destructible hexes within basic range: %s" % str(attackable))
	var engine: BattleEngine = session.get("_engine")
	var agrees := true
	for hex: Vector2i in state.hex_grid.get_cells():
		if state.hex_grid.has_obstacle(hex):
			agrees = agrees and engine.fork_for_prediction().execute(AttackObstacleCommand.new(user.unit_id, hex)).accepted == attackable.has(hex)
	suite.expect(agrees, "The engine accepts an obstacle attack exactly on the hexes the session reports")
	suite.expect(session.get_attackable_obstacle_hexes(&"enemy").is_empty(), "A unit that is not active can attack no obstacle")


## The queue picks the landing spear and the beam from presentation data, never from rules:
## a line ability may be a projectile, a hex ability may be a beam or a landing weapon.
func _check_delivery_comes_from_presentation(suite: Node, fixture: Fixtures) -> void:
	var packages: Array[ContentPackage] = [load("res://content/packages/core/core_package.tres")]
	var core := ContentLoader.load_packages(packages).snapshot
	var deliveries := {}
	for id: StringName in [&"core:spear_throw", &"core:laser", &"core:spear_sweep", &"core:spear_pin"]:
		var presentation := core.get_ability_presentation_definition(core.get_ability_definition(id).presentation_id)
		deliveries[id] = presentation.delivery if presentation != null else -1
	var kinds := AbilityPresentationDefinition.Delivery
	suite.expect(deliveries == {&"core:spear_throw": kinds.RETURNING, &"core:laser": kinds.BEAM, &"core:spear_sweep": kinds.PROJECTILE, &"core:spear_pin": kinds.PROJECTILE}, "Core skills keep their look through presentation data: %s" % str(deliveries))

	var screen := preload("res://features/battle/battle_screen.tscn").instantiate() as BattleScreen
	suite.expect(screen.setup(fixture.request(true)), "Presentation fixture battle starts")
	suite.add_child(screen)
	var controller: BattleController = screen.get("_battle_controller")
	for _frame in range(240):
		await suite.get_tree().process_frame
		if controller.get("_is_initialized") and not controller.get("_is_presenting"):
			break
	var queue: BattlePresentationQueue = controller.get("_presentation_queue")
	var views: BattleUnitViewRegistry = controller.get("_unit_views")
	var map: BattleMapView = controller.get("_map_view")
	queue.set_speed(4.0)
	var abilities: Array[AbilityDefinition] = []
	var presentations: Array[AbilityPresentationDefinition] = []
	var cases := {&"test:line_shot": [AbilityDefinition.TargetMode.LINE, kinds.PROJECTILE], &"test:hex_beam": [AbilityDefinition.TargetMode.HEX, kinds.BEAM], &"test:hex_lob": [AbilityDefinition.TargetMode.HEX, kinds.RETURNING]}
	for id: StringName in cases:
		var ability: AbilityDefinition = fixture.ability(id, cases[id][0])
		ability.presentation_id = StringName("%s_look" % id)
		abilities.append(ability)
		var look := AbilityPresentationDefinition.new()
		look.id = ability.presentation_id
		look.delivery = cases[id][1]
		presentations.append(look)
	var battles: Array[BattleDefinition] = []
	var maps: Array[BattleMapDefinition] = []
	var units: Array[UnitDefinition] = []
	var profiles: Array[AIProfileDefinition] = []
	var races: Array[RaceDefinition] = []
	var scenarios: Array[ScenarioDefinition] = []
	var campaigns: Array[CampaignDefinition] = []
	var unit_looks: Array[UnitPresentationDefinition] = []
	queue.configure(ContentSnapshot.new(battles, maps, units, profiles, races, abilities, scenarios, campaigns, null, null, unit_looks, presentations), views)
	var user_id: StringName = views.actors.keys()[0]
	var user: UnitActor = views.actors[user_id]
	var session: BattleSession = controller.get("_battle_session")
	var center := session.get_unit(user_id).hex + Vector2i(1, 0)
	var cells: Array[Vector2i] = [center]
	var drawn := {}
	for id: StringName in cases:
		await queue.call("_present_area_ability", AreaAbilityUsedEvent.new(user_id, id, center, cells), views.actors, map)
		drawn[id] = [map.get_node_or_null("PiercingBeam") != null, (queue.get("_landed_spears") as Dictionary).has(user_id)]
		for child: Node in map.get_children():
			if child.name in ["PiercingBeam", "AbilityImpactCore", "AbilityImpactRing"]:
				map.remove_child(child)
				child.free()
	suite.expect(drawn[&"test:line_shot"] == [false, false], "A line ability with a projectile look draws no beam")
	suite.expect(drawn[&"test:hex_beam"][0], "A hex ability with a beam look draws a beam")
	suite.expect(drawn[&"test:hex_lob"][1] and is_instance_valid(user), "An ordinary hex ability with a returning look leaves its weapon on the landing hex")
	screen.queue_free()
	await suite.get_tree().process_frame


func _session(state: BattleState) -> BattleSession:
	var setup := BattleSetup.new(state.battle_id, state.hex_grid, [], [], BattleObjectiveDefinition.new(), BattleFaction.Value.PLAYER, state.deterministic_seed)
	return BattleSession.new(setup, state, BattleEngine.new(state, false), null)


## A two-hex wall through the center, a rock beside it and a distant enemy.
func _walled_state(fixture: Fixtures) -> BattleState:
	var cells: Array[Vector2i] = []
	for q in range(0, 6):
		for r in range(0, 2):
			cells.append(Vector2i(q, r))
	var user: UnitState = fixture.unit(&"user", BattleFaction.Value.PLAYER, Vector2i.ZERO, 20, 3)
	var enemy: UnitState = fixture.unit(&"enemy", BattleFaction.Value.ENEMY, Vector2i(5, 1), 20)
	var units: Array[UnitState] = [user, enemy]
	var state: BattleState = fixture.state(cells, units)
	for entry: Array in [[&"wall", [Vector2i(2, 0), Vector2i(3, 0)]], [&"rock", [Vector2i(2, 1)]]]:
		var obstacle := BattleObstacleDefinition.new()
		obstacle.id = entry[0]
		obstacle.hexes.assign(entry[1])
		obstacle.destructible = true
		state.hex_grid.add_obstacle(obstacle)
	return state


func _hp(state: BattleState, hex: Vector2i) -> int:
	var obstacle := state.hex_grid.get_obstacle(hex)
	return obstacle.current_hp if obstacle != null else 0
