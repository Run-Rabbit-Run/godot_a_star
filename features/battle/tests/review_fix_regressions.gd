extends RefCounted
## Second review fixes: engine revisions, terrain batches, campaign routing, content and presentation copies.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")


## Records how often the default area batch falls back to per-cell execution.
class CountingHexHandler extends AbilityEffectHandler:
	var calls := 0

	func affects_hexes() -> bool:
		return true

	func validate(_effect: AbilityEffectDefinition) -> String:
		return ""

	func execute_hex(_effect: AbilityEffectDefinition, _context: BattleEffectContext, _source: StringName, _hex: Vector2i) -> Array[BattleEvent]:
		calls += 1
		var events: Array[BattleEvent] = []
		return events


func run_review_fixes(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var p := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var e := fixture.unit(&"e", BattleFaction.Value.ENEMY, Vector2i(1, 0))
	var dead := fixture.unit(&"x", BattleFaction.Value.PLAYER, Vector2i(2, 0))
	dead.health.current = 0
	var registry: Dictionary[StringName, UnitState] = {}
	for participant: UnitState in [p, e, dead]:
		registry[participant.unit_id] = participant
	var order: Array[StringName] = [dead.unit_id]
	var cells: Array[Vector2i] = [p.hex, e.hex, dead.hex]
	var objectives := ObjectiveSystem.new(EliminateFactionObjective.new(BattleFaction.Value.ENEMY, "Defeat enemies"), BattleFaction.Value.PLAYER)
	var stuck := BattleState.new(&"core:test", HexGrid.new(cells), registry, order, objectives, 7)
	suite.expect(not BattleEngine.new(stuck).get_initial_resolution().terminal_error.is_empty(), "Initial resolution reports a turn order that cannot start")

	var state := fixture.state([Vector2i.ZERO, Vector2i(1, 0)])
	state.hex_grid.set_hex_state(Vector2i.ZERO, &"core:electricity")
	var unchanged := MapMutationService.apply(state, [MapMutation.apply_hex_state(Vector2i.ZERO, &"core:electricity")])
	suite.expect(unchanged.accepted and unchanged.events.is_empty() and state.map_revision == 0 and state.state_revision == 0, "Unchanged terrain keeps map and state revisions")
	suite.expect(HexStateCatalog.get_damage_type(&"core:acid_vapour") == &"acid" and HexStateCatalog.get_damage_type(&"core:steam") == &"physical", "Hex damage types are explicit")

	var a := Vector2i.ZERO
	var b := Vector2i(1, 0)
	var user := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i(2, 0))
	var enemy := fixture.unit(&"e", BattleFaction.Value.ENEMY, Vector2i(5, 0))
	state = fixture.state([a, b, user.hex, enemy.hex], [user, enemy])
	state.hex_grid.set_hex_state(a, &"core:fire")
	state.hex_grid.set_hex_state(b, &"core:fire")
	var ability := fixture.ability(&"core:test_field", AbilityDefinition.TargetMode.HEX, 1)
	var effect := AbilityEffectDefinition.new()
	effect.effect_type_id = &"core:hex_state"
	effect.parameters = {"state_id": "core:electricity"}
	ability.effects.assign([effect])
	user.abilities[ability.id] = ability
	var used := BattleEngine.new(state).execute(UseAbilityCommand.at_hex(user.unit_id, a, ability.id))
	suite.expect(used.accepted and state.hex_grid.get_hex_state_id(a) == &"core:plasma" and state.hex_grid.get_hex_state_id(b) == &"core:plasma", "Area terrain ability resolves through one handler batch")
	var counting := CountingHexHandler.new()
	var hexes: Array[Vector2i] = [a, b]
	counting.execute_hexes(effect, null, &"", hexes)
	suite.expect(counting.calls == 2, "Default handler batch still resolves every cell")

	var core: ContentPackage = load("res://content/packages/core/core_package.tres")
	var ember: ContentPackage = load("res://content/packages/ember_pack/ember_pack.tres")
	var invalid := ContentLoader.load_packages([core, ember, _review_campaign_package(true)])
	var joined := "\n".join(invalid.errors)
	suite.expect(not invalid.is_successful and "several transitions" in joined and "outside campaign" in joined, "Campaign rejects ambiguous outcomes and routes outside its scenarios")
	suite.expect(ContentLoader.load_packages([core, ember, _review_campaign_package(false)]).is_successful, "Closed campaign graph loads")

	var request := fixture.request()
	if request != null:
		var session := BattleSessionFactory.create(request).session
		suite.expect(session.get_battle_id() == request.battle_id and session.get_deterministic_seed() == request.deterministic_seed, "Session exposes identity without copying setup")
		var document := BattleDocument.from_snapshot(request.content_snapshot, request.battle_id)
		document.battle_definition.unit_placements[0].modifiers = {"bonus": 1}
		var validation := document.validate(request.content_snapshot)
		suite.expect(validation.is_valid and not validation.warnings.is_empty(), "Reserved placement fields produce a warning")

	var presented := fixture.request(true)
	if presented != null:
		var snapshot := presented.content_snapshot
		var battle := snapshot.get_battle_definition(presented.battle_id)
		var definition := snapshot.get_unit_definition(battle.unit_placements[0].definition_id)
		var first_copy := snapshot.get_unit_presentation_definition(definition.presentation_id)
		var second_copy := snapshot.get_unit_presentation_definition(definition.presentation_id)
		var bounds := first_copy.visible_rect()
		var cached := UnitPresentationDefinition._alpha_bounds_by_texture.size()
		suite.expect(first_copy != second_copy and first_copy.actor_texture == second_copy.actor_texture, "Presentation copies share imported textures")
		suite.expect(second_copy.visible_rect() == bounds and UnitPresentationDefinition._alpha_bounds_by_texture.size() == cached, "Presentation copies reuse texture alpha bounds")


func _review_campaign_package(broken: bool) -> ContentPackage:
	var package := ContentPackage.new()
	package.manifest = ContentPackageManifest.new()
	package.manifest.package_id = &"review"
	for dependency_id: StringName in [&"core", &"ember_pack"]:
		var dependency := ContentPackageDependency.new()
		dependency.package_id = dependency_id
		package.manifest.dependencies.append(dependency)
	var first := _review_scenario(&"review:first", &"ember_pack:crossing_battle")
	var second := _review_scenario(&"review:second", &"ember_pack:ash_gate_battle")
	var outside := _review_scenario(&"review:outside", &"ember_pack:ash_gate_battle")
	first.transitions.append(_review_transition(ScenarioTransitionDefinition.Outcome.VICTORY, second.id))
	first.transitions.append(_review_transition(ScenarioTransitionDefinition.Outcome.DEFEAT, &""))
	if broken:
		first.transitions.append(_review_transition(ScenarioTransitionDefinition.Outcome.VICTORY, outside.id))
	second.transitions.append(_review_transition(ScenarioTransitionDefinition.Outcome.VICTORY, outside.id if broken else &""))
	outside.transitions.append(_review_transition(ScenarioTransitionDefinition.Outcome.VICTORY, &""))
	package.scenarios.assign([first, second, outside])
	var campaign := CampaignDefinition.new()
	campaign.id = &"review:campaign"
	campaign.entry_scenario_id = first.id
	campaign.scenario_ids.assign([first.id, second.id])
	package.campaigns.append(campaign)
	return package


func _review_scenario(id: StringName, battle_id: StringName) -> ScenarioDefinition:
	var scenario := ScenarioDefinition.new()
	scenario.id = id
	scenario.battle_id = battle_id
	return scenario


func _review_transition(outcome: ScenarioTransitionDefinition.Outcome, target: StringName) -> ScenarioTransitionDefinition:
	var transition := ScenarioTransitionDefinition.new()
	transition.outcome = outcome
	transition.target_scenario_id = target
	transition.ends_campaign = target.is_empty()
	return transition
