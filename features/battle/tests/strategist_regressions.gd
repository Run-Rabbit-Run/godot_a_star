extends RefCounted
## The strategist's health shuttle: once per phase it lands on a hex next to the field, holds that
## hex and raises allied maximum health; its defeat takes the hex away with everything on it.
## Summoned units and constructions keep no faction alive and are not counted in the result.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")

const SHUTTLE := &"core:health_shuttle"
const SHUTTLE_UNIT := &"core:health_shuttle_unit"
## A 2 × 2 rhombus: the hexes touching it from outside, in sorted order.
const RING: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(-1, 2), Vector2i(0, -1), Vector2i(0, 2), Vector2i(1, -1), Vector2i(1, 2), Vector2i(2, -1), Vector2i(2, 0), Vector2i(2, 1)]
const LANDING := Vector2i(-1, 1)


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	_run_targets(suite, fixture)
	_run_landing(suite, fixture)
	_run_collapse(suite, fixture)
	_run_phase_passes(suite, fixture)
	_run_summons_not_counted(suite, fixture)
	_run_prediction(suite, fixture)
	_run_content(suite, fixture)


## The HUD button opens the strategist's abilities; an aimed landing hex outside the board becomes
## clickable, and the landed shuttle shows up on its new hex.
func run_presentation(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var screen := preload("res://features/battle/battle_screen.tscn").instantiate() as BattleScreen
	suite.expect(screen.setup(fixture.spear_request()), "Strategist battle setup accepted")
	suite.add_child(screen)
	var controller: BattleController = screen.get("_battle_controller")
	await _until_idle(suite, controller)
	controller.set_playback_speed(4.0)
	var hud: BattleHUD = controller.get("_hud")
	var session: BattleSession = controller.get("_battle_session")
	var selection: PlayerActionSelection = controller.get("_selection")
	var map: BattleMapView = controller.get("_map_view")
	var router := map.get_node("%BattleInputRouter") as BattleInputRouter
	var button := hud.get_node("HUDRoot/%StrategistButton") as Button
	var popup := hud.get_node("HUDRoot/%StrategistPopup") as Control
	var entry := hud.get_node("HUDRoot/%StrategistAbilityList").get_node_or_null(BattleHUD.get_strategist_button_name(SHUTTLE)) as Button
	suite.expect(not button.disabled and not popup.visible and entry != null and not entry.disabled, "The strategist button is ready in the player phase, its popup closed")
	if entry == null:
		screen.queue_free()
		return
	button.button_pressed = true
	suite.expect(popup.visible, "The strategist button opens the list of its abilities")
	entry.pressed.emit()
	var targets := session.get_strategist_target_hexes(BattleFaction.Value.PLAYER, SHUTTLE)
	var landing_visuals := map.get_node("LandingVisuals") as Node2D
	suite.expect(not popup.visible and selection.is_aiming_ability() and landing_visuals.get_child_count() == targets.size() * 2, "Choosing the shuttle closes the popup and outlines every landing hex")
	suite.expect((router.get("_extra_cells") as Dictionary).size() == targets.size(), "The landing hexes outside the board accept the pointer")
	var active := session.get_unit(session.get_active_unit_id())
	var landing: Vector2i = targets[0]
	var command := selection.command_at(active, landing)
	suite.expect(command is UseStrategistAbilityCommand and selection.command_at(active, active.hex) == null, "Clicking a landing hex means the strategist's landing, other hexes mean nothing")
	controller.call("_on_hex_selected", landing)
	await _until_idle(suite, controller)
	var terrain := map.get_node("%TerrainLayer") as TileMapLayer
	var shuttle := StringName()
	for unit_id: StringName in session.get_turn_order():
		if session.get_unit(unit_id).summoned_by == SHUTTLE:
			shuttle = unit_id
	var actors: Dictionary = controller.get("_unit_views").actors
	suite.expect(terrain.get_cell_source_id(HexCoordinateMapper.axial_to_offset(landing)) != -1, "The landing hex is drawn on the board")
	suite.expect(not shuttle.is_empty() and actors.has(shuttle) and (actors[shuttle] as UnitActor).global_position.is_equal_approx(map.hex_to_global_position(landing)), "The shuttle stands on its hex after the fall")
	entry = hud.get_node("HUDRoot/%StrategistAbilityList").get_node(BattleHUD.get_strategist_button_name(SHUTTLE)) as Button
	suite.expect(entry.disabled and "фазе" in entry.tooltip_text and button.text.ends_with("✓"), "After the use the HUD says the strategist has acted this phase")
	suite.expect(landing_visuals.get_child_count() == 0 and (router.get("_extra_cells") as Dictionary).is_empty(), "The landing outlines and extra hexes are gone")
	suite.expect(not "КРАЯ ПОЛЯ" in (hud.get_node("HUDRoot/%ActionLabel") as Label).text, "The aiming hint does not outlive the landing")
	var cards := (hud.get("_turn_order_container") as Node).get_child_count()
	suite.expect(cards == session.get_turn_order().size() - 1, "The turn order leaves the shuttle out: it takes no turns")
	screen.queue_free()
	await suite.get_tree().process_frame


func _until_idle(suite: Node, controller: BattleController) -> void:
	for _frame in range(900):
		await suite.get_tree().process_frame
		if controller.get("_is_initialized") and not controller.get("_is_presenting"):
			return


func _ability() -> StrategistAbilityDefinition:
	var ability := StrategistAbilityDefinition.new()
	ability.id = SHUTTLE
	ability.display_name = "Шаттл Здоровья"
	ability.one_at_a_time = true
	var effect := AbilityEffectDefinition.new()
	effect.effect_type_id = &"core:landing"
	effect.parameters = {"unit_id": String(SHUTTLE_UNIT), "center_only": true}
	ability.effects.append(effect)
	return ability


func _shuttle_unit() -> UnitDefinition:
	var unit := UnitDefinition.new()
	unit.id = SHUTTLE_UNIT
	unit.display_name = "Шаттл Здоровья"
	unit.base_stats = UnitStatsDefinition.new()
	unit.base_stats.max_health = 4
	unit.base_stats.movement_points = 0
	unit.base_stats.basic_attack_damage = 0
	unit.passive_ability_ids.assign([&"core:ally_max_health"])
	return unit


## hero (0,0) 10/10, ally (1,0) 6/10, enemy (1,1) on a 2 × 2 rhombus with the shuttle known.
func _battle(fixture: Fixtures) -> Dictionary:
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	var hero := fixture.unit(&"hero", BattleFaction.Value.PLAYER, Vector2i(0, 0), 10)
	var ally := fixture.unit(&"ally", BattleFaction.Value.PLAYER, Vector2i(1, 0), 10)
	ally.health.current = 6
	var enemy := fixture.unit(&"enemy", BattleFaction.Value.ENEMY, Vector2i(0, 1), 10)
	enemy.basic_attack_damage = 10
	var state := fixture.state(cells, [hero, ally, enemy])
	state.strategist_abilities[SHUTTLE] = _ability()
	state.unit_definitions[SHUTTLE_UNIT] = _shuttle_unit()
	return {"state": state, "engine": BattleEngine.new(state), "hero": hero, "ally": ally, "enemy": enemy}


func _shuttle_of(state: BattleState) -> UnitState:
	for unit: UnitState in state.unit_states.values():
		if unit.summoned_by == SHUTTLE:
			return unit
	return null


func _count(events: Array[BattleEvent], type: Script) -> int:
	var found := 0
	for event: BattleEvent in events:
		if event.get_script() == type:
			found += 1
	return found


func _index(events: Array[BattleEvent], type: Script) -> int:
	for index in range(events.size()):
		if events[index].get_script() == type:
			return index
	return -1


func _run_targets(suite: Node, fixture: Fixtures) -> void:
	var battle := _battle(fixture)
	var engine: BattleEngine = battle.engine
	suite.expect(engine.get_strategist_ability_ids() == [SHUTTLE] and engine.get_strategist_unavailable_reason(BattleFaction.Value.PLAYER, SHUTTLE).is_empty(), "The player's strategist knows the shuttle and may use it in the player phase")
	suite.expect(engine.get_strategist_target_hexes(BattleFaction.Value.PLAYER, SHUTTLE) == RING, "The shuttle lands only on the missing hexes that touch the field")
	suite.expect(not engine.get_strategist_unavailable_reason(BattleFaction.Value.ENEMY, SHUTTLE).is_empty() and engine.get_strategist_target_hexes(BattleFaction.Value.ENEMY, SHUTTLE).is_empty(), "The enemy faction has no strategist")
	for hex: Vector2i in [Vector2i(0, 0), Vector2i(3, 3)]:
		suite.expect(not engine.execute(UseStrategistAbilityCommand.new(BattleFaction.Value.PLAYER, SHUTTLE, hex)).accepted, "The shuttle cannot land on %s: an existing hex or one away from the field" % hex)
	suite.expect(engine.get_hex_grid().get_cells().size() == 4 and not battle.state.turn_service.is_strategist_used(), "A refused landing changes nothing")


func _run_landing(suite: Node, fixture: Fixtures) -> void:
	var battle := _battle(fixture)
	var engine: BattleEngine = battle.engine
	var state: BattleState = battle.state
	var revision := engine.get_map_revision()
	var resolution := engine.execute(UseStrategistAbilityCommand.new(BattleFaction.Value.PLAYER, SHUTTLE, LANDING))
	suite.expect(resolution.accepted, "The strategist drops the shuttle: %s" % resolution.rejection_reason)
	var events := resolution.events
	suite.expect(not events.is_empty() and events[0] is StrategistAbilityUsedEvent and _index(events, MapMutationEvent) < _index(events, UnitSummonedEvent), "The use comes first, the hex joins the field before the shuttle lands on it")
	suite.expect(state.hex_grid.has_cell(LANDING) and engine.get_map_revision() > revision, "The landing hex becomes part of the battlefield")
	var shuttle := _shuttle_of(state)
	suite.expect(shuttle != null and shuttle.hex == LANDING and shuttle.faction == BattleFaction.Value.PLAYER and shuttle.health.current == 4 and shuttle.health.maximum == 4, "The shuttle stands on its hex with 4 HP and no bonus of its own")
	if shuttle == null:
		return
	suite.expect(shuttle.is_summoned and shuttle.holds_hex and not shuttle.takes_turns(), "The shuttle is a summoned object that holds its hex and takes no turns")
	suite.expect(battle.hero.health.current == 11 and battle.hero.health.maximum == 11 and battle.ally.health.current == 7 and battle.ally.health.maximum == 11, "Allies gain 1 maximum and 1 current health")
	suite.expect(battle.enemy.health.maximum == 10 and _count(events, UnitHealthChangedEvent) == 2, "Only the shuttle's allies gain health, each announced once")
	suite.expect(not engine.get_ready_unit_ids().has(shuttle.unit_id) and engine.get_active_unit_id() == &"hero", "The shuttle is never a ready unit")
	var again := engine.execute(UseStrategistAbilityCommand.new(BattleFaction.Value.PLAYER, SHUTTLE, Vector2i(2, 0)))
	suite.expect(not again.accepted and "фазе" in again.rejection_reason, "The strategist acts once per phase")
	engine.execute(EndPhaseCommand.new(BattleFaction.Value.PLAYER))
	suite.expect(engine.get_active_faction() == BattleFaction.Value.ENEMY and not engine.execute(UseStrategistAbilityCommand.new(BattleFaction.Value.PLAYER, SHUTTLE, Vector2i(2, 0))).accepted, "The strategist does not act in the enemy phase")
	engine.execute(EndPhaseCommand.new(BattleFaction.Value.ENEMY))
	var reason := engine.get_strategist_unavailable_reason(BattleFaction.Value.PLAYER, SHUTTLE)
	suite.expect(engine.get_active_faction() == BattleFaction.Value.PLAYER and not reason.is_empty() and engine.get_strategist_target_hexes(BattleFaction.Value.PLAYER, SHUTTLE).is_empty(), "A new shuttle cannot be called while the previous one stands: %s" % reason)


func _run_collapse(suite: Node, fixture: Fixtures) -> void:
	var battle := _battle(fixture)
	var engine: BattleEngine = battle.engine
	var state: BattleState = battle.state
	engine.execute(UseStrategistAbilityCommand.new(BattleFaction.Value.PLAYER, SHUTTLE, LANDING))
	var shuttle := _shuttle_of(state)
	var water: Array[MapMutation] = [MapMutation.apply_hex_state(LANDING, &"core:water")]
	suite.expect(engine.apply_map_mutations(water).accepted and not state.hex_grid.get_liquid(LANDING).is_empty(), "The shuttle hex takes hex states like any other")
	engine.execute(EndPhaseCommand.new(BattleFaction.Value.PLAYER))
	var hit := engine.execute(AttackCommand.new(&"enemy", shuttle.unit_id))
	suite.expect(hit.accepted and shuttle.health.is_defeated(), "The enemy destroys the shuttle")
	var events := hit.events
	var damage := _index(events, UnitDamagedEvent)
	var removed := _index(events, CorpseRemovedEvent)
	var collapsed := -1
	for index in range(events.size()):
		if events[index] is MapMutationEvent and events[index].kind == MapMutationKind.Value.REMOVE_HEX:
			collapsed = index
	suite.expect(damage >= 0 and damage < removed and removed < collapsed, "The destroyed shuttle's body goes, then its hex")
	suite.expect(not state.hex_grid.has_cell(LANDING) and state.get_corpses_at(LANDING).is_empty() and shuttle.corpse_removed, "The hex leaves the battlefield with the body on it")
	suite.expect(engine.get_hex_layers(LANDING) == [&"", &""], "The hex states of the removed hex are gone")
	suite.expect(battle.hero.health.current == 10 and battle.hero.health.maximum == 10, "A full-health ally loses the bonus with the shuttle")
	suite.expect(battle.ally.health.current == 7 and battle.ally.health.maximum == 10, "A wounded ally keeps its remaining health up to the new maximum")
	engine.execute(EndPhaseCommand.new(BattleFaction.Value.ENEMY))
	suite.expect(engine.get_strategist_unavailable_reason(BattleFaction.Value.PLAYER, SHUTTLE).is_empty() and engine.get_strategist_target_hexes(BattleFaction.Value.PLAYER, SHUTTLE).has(LANDING), "After the shuttle fell the strategist may call a new one, even onto the same hex")


func _run_phase_passes(suite: Node, fixture: Fixtures) -> void:
	var battle := _battle(fixture)
	var engine: BattleEngine = battle.engine
	engine.execute(UseStrategistAbilityCommand.new(BattleFaction.Value.PLAYER, SHUTTLE, LANDING))
	var shuttle := _shuttle_of(battle.state)
	engine.execute(EndTurnCommand.new(&"hero"))
	var last := engine.execute(EndTurnCommand.new(&"ally"))
	var shuttle_turn_ended := false
	for event: BattleEvent in last.events:
		shuttle_turn_ended = shuttle_turn_ended or (event is TurnEndedEvent and event.unit_id == shuttle.unit_id)
	suite.expect(engine.get_active_faction() == BattleFaction.Value.ENEMY and not shuttle_turn_ended, "The phase passes once the units are done; the shuttle has no turn to end")
	battle.state.unit_states[shuttle.unit_id].statuses[UnitStatusCatalog.BURNING] = 1
	engine.execute(EndPhaseCommand.new(BattleFaction.Value.ENEMY))
	engine.execute(EndPhaseCommand.new(BattleFaction.Value.PLAYER))
	suite.expect(shuttle.health.current == 3, "End-of-phase effects still burn the shuttle")


func _run_summons_not_counted(suite: Node, fixture: Fixtures) -> void:
	var units: Dictionary[StringName, UnitState] = {}
	for unit: UnitState in [
		fixture.unit(&"hero", BattleFaction.Value.PLAYER, Vector2i.ZERO),
		fixture.unit(&"shuttle", BattleFaction.Value.PLAYER, Vector2i(1, 0)),
		fixture.unit(&"boss", BattleFaction.Value.ENEMY, Vector2i(4, 0)),
		fixture.unit(&"turret", BattleFaction.Value.ENEMY, Vector2i(5, 0)),
	]:
		units[unit.unit_id] = unit
	units[&"shuttle"].is_summoned = true
	units[&"turret"].is_summoned = true
	var eliminate := ObjectiveSystem.new(EliminateFactionObjective.new(BattleFaction.Value.ENEMY, "All"), BattleFaction.Value.PLAYER)
	units[&"hero"].health.current = 0
	suite.expect(eliminate.get_outcome(units, 1) == BattleOutcome.Value.DEFEAT, "A living shuttle does not keep a fallen squad in the battle")
	units[&"hero"].health.current = 100
	units[&"boss"].health.current = 0
	suite.expect(eliminate.get_outcome(units, 1) == BattleOutcome.Value.VICTORY, "A living enemy turret does not keep a beaten enemy faction alive")
	var survive := ObjectiveSystem.new(SurviveRoundsObjective.new(5, BattleFaction.Value.ENEMY, "Hold"), BattleFaction.Value.PLAYER)
	suite.expect(survive.get_outcome(units, 1) == BattleOutcome.Value.VICTORY, "Holding out ends early once only summoned enemies are left")

	var battle := _battle(fixture)
	var engine: BattleEngine = battle.engine
	engine.execute(UseStrategistAbilityCommand.new(BattleFaction.Value.PLAYER, SHUTTLE, LANDING))
	battle.enemy.health.current = 0
	var result := engine.get_result()
	suite.expect(result != null and result.participants.get(BattleFaction.Value.PLAYER) == 2 and result.defeated.get(BattleFaction.Value.PLAYER, 0) == 0, "The battle result counts only the faction's own units")


func _run_prediction(suite: Node, fixture: Fixtures) -> void:
	var battle := _battle(fixture)
	var session := fixture.ai_session(battle.state)
	var preview := session.preview(UseStrategistAbilityCommand.new(BattleFaction.Value.PLAYER, SHUTTLE, LANDING))
	suite.expect(preview.accepted and preview.units.has(&"hero") and preview.units[&"hero"].health_after == 11, "A preview of the landing shows the allied health gain")
	suite.expect(not battle.state.hex_grid.has_cell(LANDING) and _shuttle_of(battle.state) == null and not battle.state.turn_service.is_strategist_used(), "The preview leaves the live battle untouched")


func _run_content(suite: Node, fixture: Fixtures) -> void:
	var request := fixture.request()
	suite.expect(request != null, "The regression battle loads with the strategist content")
	if request == null:
		return
	var snapshot := request.content_snapshot
	var ability := snapshot.get_strategist_ability_definition(SHUTTLE)
	var unit := snapshot.get_unit_definition(SHUTTLE_UNIT)
	suite.expect(ability != null and ability.validate().is_empty() and ability.one_at_a_time and ContentLoader._find_external_resource(ability, {}).is_empty(), "The core package ships the health shuttle with its effects inline")
	suite.expect(unit != null and unit.base_stats.max_health == 4 and unit.base_stats.movement_points == 0 and unit.passive_ability_ids == [&"core:ally_max_health"], "The shuttle has 4 HP, does not move and carries the allied health passive")
	var session := BattleSessionFactory.create(request).session
	suite.expect(session != null and session.get_strategist_ability_ids() == [SHUTTLE] and session.setup.strategist_abilities.has(SHUTTLE) and session.setup.unit_definitions.has(SHUTTLE_UNIT), "The battle setup resolves the strategist ability and the unit it lands")
	var broken := _ability()
	broken.effects[0].effect_type_id = &"core:damage"
	suite.expect(not broken.validate().is_empty(), "A field-edge ability needs a landing effect")
	var description := AbilityDescription.render_passive(PassiveAbilityCatalog.DEFINITIONS[&"core:ally_max_health"])
	suite.expect("1" in description and not "{" in description, "The allied health passive describes its bonus: %s" % description)
	var override := {"core:ally_max_health": {"kind": "passive", "id": "core:ally_max_health", "name": "Другое имя", "description": "", "attack_bonus": 0, "damage_type": "", "status": "", "levels": 2, "immunity": "", "retaliation": false}}
	suite.expect(int(SkillLibrary.passive_definitions(override)[&"core:ally_max_health"].get("ally_max_health", 0)) == 1, "Renaming the built-in passive keeps its fixed health bonus")
