extends RefCounted

const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")
const Core := preload("res://content/packages/core/core_package.tres")
const PLAYER := BattleFaction.Value.PLAYER
const ENEMY := BattleFaction.Value.ENEMY
const IDS := [&"repulse", &"attract", &"repulsing_shot", &"attracting_shot", &"ram", &"grapple", &"recoil", &"swap", &"shield_bash", &"fissure", &"intercept", &"watch_closely"]


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	_content(suite, fixture)
	_area(suite, fixture)
	_shots(suite, fixture)
	_travel(suite, fixture)
	_swap_and_shield(suite, fixture)
	_fissure(suite, fixture)
	_intercept(suite, fixture)


static func presentation_request(fixture: Fixtures) -> BattleStartRequest:
	var request := fixture.spear_request()
	var snapshot := request.content_snapshot
	var battle := snapshot.get_battle_definition(request.battle_id)
	var actor := snapshot.get_unit_definition(battle.unit_placements[0].definition_id)
	actor.ability_ids.append(&"core:fissure")
	request.content_snapshot = snapshot.with_battle_document(snapshot.get_map_definition(battle.map_id), battle, [actor])
	return request


func run_presentation(suite: Node) -> void:
	var screen := preload("res://features/battle/battle_screen.tscn").instantiate() as BattleScreen
	suite.expect(screen.setup(presentation_request(suite.fixture)), "The battle screen accepts the fissure fixture")
	suite.add_child(screen)
	await suite.get_tree().process_frame
	await suite.get_tree().process_frame
	var controller: BattleController = screen.get("_battle_controller")
	var session: BattleSession = controller.get("_battle_session")
	var selection: PlayerActionSelection = controller.get("_selection")
	var map: BattleMapView = controller.get("_map_view")
	var actor := session.get_unit(session.get_active_unit_id())
	selection.show_movement_and_attacks(actor)
	suite.expect(selection.select_ability(actor, &"core:fissure"), "The player can select fissure in the battle screen")
	var hud := screen.get_node("BattleMap/BattleUI") as BattleHUD
	var hint := hud.get("_action_label") as Label
	suite.expect(hint.text.contains("ВЫБЕРИТЕ ГЕКС"), "Fissure asks the player for a hex")
	var center := actor.hex
	var preview: ActionPreview
	for hex: Vector2i in session.get_ability_target_hexes(actor.unit_id, &"core:fissure"):
		var candidate := session.preview(UseAbilityCommand.at_hex(actor.unit_id, hex, &"core:fissure"))
		if candidate.accepted and not candidate.relocations.is_empty():
			center = hex
			preview = candidate
			break
	selection.hover(center)
	var overlay := map.get_node("RelocationPreview")
	var arrows := overlay.get_children().filter(func(child: Node) -> bool: return child.name.begins_with("RelocationArrow"))
	suite.expect(preview != null and arrows.size() == preview.relocations.size(), "A hovered fissure renders an arrow for each evacuated unit from %s toward %s (%d arrows)" % [actor.hex, center, arrows.size()])
	selection.hover_exited()
	suite.expect(overlay.get_child_count() == 0, "Relocation arrows clear when the cursor leaves")
	screen.queue_free()
	await suite.get_tree().process_frame


func _content(suite: Node, fixture: Fixtures) -> void:
	var loaded := ContentLoader.load_packages([Core])
	suite.expect(loaded.snapshot != null and loaded.errors.is_empty(), "The base package loads with the new abilities")
	var documents := fixture.skills().builtin_documents()
	for id: StringName in IDS:
		var ability := loaded.snapshot.get_ability_definition(_id(id))
		suite.expect(ability != null and ability.cooldown_turns == 2, "%s is shipped with cooldown 2" % id)
		var document: Dictionary = documents.get(String(_id(id)), {})
		suite.expect(not document.is_empty() and fixture.skills().validate(document).is_empty(), "%s is valid in the skill editor" % id)


func _area(suite: Node, fixture: Fixtures) -> void:
	for id: StringName in [&"repulse", &"attract"]:
		var actor := fixture.unit(&"actor", PLAYER, Vector2i.ZERO)
		var ally := fixture.unit(&"ally", PLAYER, Vector2i(0, 1 if id == &"repulse" else 3))
		var enemy := fixture.unit(&"enemy", ENEMY, Vector2i(1 if id == &"repulse" else 2, 0))
		var immune := fixture.unit(&"immune", ENEMY, Vector2i(-1, 0))
		immune.push_immune = true
		var session := _session(fixture, id, [actor, ally, enemy, immune])
		var command := UseAbilityCommand.at_hex(actor.unit_id, actor.hex, _id(id))
		var preview := session.preview(command)
		suite.expect(preview.accepted and preview.relocations.size() == 2 and not preview.relocations.has(immune.unit_id), "%s forecasts both sides and respects immunity" % id)
		suite.expect(session.step(command).accepted and ally.hex == Vector2i(0, 2) and enemy.hex == Vector2i(2 if id == &"repulse" else 1, 0), "%s moves all eligible targets by one" % id)


func _shots(suite: Node, fixture: Fixtures) -> void:
	for id: StringName in [&"repulsing_shot", &"attracting_shot", &"recoil"]:
		var actor := fixture.unit(&"actor", PLAYER, Vector2i.ZERO)
		actor.basic_attack_range = 4
		var enemy := fixture.unit(&"enemy", ENEMY, Vector2i(3, 0))
		var bystander := fixture.unit(&"bystander", PLAYER, Vector2i(3, 2))
		var session := _session(fixture, id, [actor, enemy, bystander])
		var command := UseAbilityCommand.new(actor.unit_id, enemy.unit_id, _id(id))
		var preview := session.preview(command)
		suite.expect(preview.accepted and session.step(command).accepted, "%s works on a target at attack range" % id)
		suite.expect(enemy.hex == Vector2i(3, 0) and enemy.health.current == (97 if id == &"recoil" else 98), "%s deals the stated primary damage" % id)
		match id:
			&"repulsing_shot":
				suite.expect(bystander.hex == Vector2i(3, 3), "The repulsing shot centers the move on the target")
			&"attracting_shot":
				suite.expect(bystander.hex == Vector2i(3, 1), "The attracting shot centers the move on the target")
			&"recoil":
				suite.expect(actor.hex == Vector2i(-1, 0) and preview.destination == actor.hex, "Recoil moves and previews the shooter, not its target")


func _travel(suite: Node, fixture: Fixtures) -> void:
	var actor := fixture.unit(&"actor", PLAYER, Vector2i.ZERO)
	var enemy := fixture.unit(&"enemy", ENEMY, Vector2i(5, 0))
	var far_enemy := fixture.unit(&"far_enemy", ENEMY, Vector2i(7, 0))
	var session := _session(fixture, &"ram", [actor, enemy, far_enemy])
	suite.expect(session.get_ability_target_hexes(actor.unit_id, _id(&"ram")) == [enemy.hex], "Ram chooses the first enemy after up to four empty steps")
	var result := session.step(UseAbilityCommand.new(actor.unit_id, enemy.unit_id, _id(&"ram")))
	suite.expect(result.accepted and actor.hex == Vector2i(4, 0) and enemy.hex == Vector2i(6, 0) and enemy.health.current == 95, "Ram travels four, hits for five and pushes one")
	actor = fixture.unit(&"actor", PLAYER, Vector2i.ZERO)
	enemy = fixture.unit(&"enemy", ENEMY, Vector2i(4, 0))
	var blocker := fixture.unit(&"blocker", PLAYER, Vector2i(3, 0))
	session = _session(fixture, &"grapple", [actor, enemy, blocker])
	result = session.step(UseAbilityCommand.at_hex(actor.unit_id, enemy.hex, _id(&"grapple")))
	suite.expect(result.accepted and actor.hex == Vector2i(2, 0) and enemy.hex == Vector2i(4, 0), "Grapple pulls the actor and stops at the first blocker")
	actor = fixture.unit(&"actor", PLAYER, Vector2i.ZERO)
	enemy = fixture.unit(&"enemy", ENEMY, Vector2i(1, 0))
	blocker = fixture.unit(&"blocker", PLAYER, Vector2i(2, 0))
	session = _session(fixture, &"watch_closely", [actor, enemy, blocker])
	var targets := session.get_ability_target_hexes(actor.unit_id, _id(&"watch_closely"))
	suite.expect(not targets.has(enemy.hex) and not targets.has(Vector2i(1, 1)) and targets.has(Vector2i(3, 0)), "Dash requires an empty, axial destination")
	result = session.step(UseAbilityCommand.at_hex(actor.unit_id, Vector2i(3, 0), _id(&"watch_closely")))
	suite.expect(result.accepted and actor.hex == Vector2i(3, 0) and enemy.health.current == 99 and blocker.health.current == 100, "Dash crosses units and hurts only enemies")


func _swap_and_shield(suite: Node, fixture: Fixtures) -> void:
	var actor := fixture.unit(&"actor", PLAYER, Vector2i.ZERO)
	var ally := fixture.unit(&"ally", PLAYER, Vector2i(3, 1))
	var enemy := fixture.unit(&"enemy", ENEMY, Vector2i(1, 0))
	var session := _session(fixture, &"swap", [actor, ally, enemy])
	var targets := session.get_ability_target_hexes(actor.unit_id, _id(&"swap"))
	suite.expect(targets.has(ally.hex) and targets.has(enemy.hex) and not targets.has(actor.hex), "Exchange can target either side")
	var result := session.step(UseAbilityCommand.at_hex(actor.unit_id, ally.hex, _id(&"swap")))
	suite.expect(result.accepted and actor.hex == Vector2i(3, 1) and ally.hex == Vector2i.ZERO, "Exchange swaps both positions")
	actor = fixture.unit(&"actor", PLAYER, Vector2i.ZERO)
	ally = fixture.unit(&"ally", PLAYER, Vector2i(0, 1))
	enemy = fixture.unit(&"enemy", ENEMY, Vector2i(1, 0))
	var third := fixture.unit(&"third", ENEMY, Vector2i(1, -1))
	var outside := fixture.unit(&"outside", ENEMY, Vector2i(-1, 0))
	session = _session(fixture, &"shield_bash", [actor, ally, enemy, third, outside])
	result = session.step(UseAbilityCommand.at_hex(actor.unit_id, enemy.hex, _id(&"shield_bash")))
	suite.expect(result.accepted and ally.hex == Vector2i(0, 2) and enemy.hex == Vector2i(2, 0) and third.hex == Vector2i(2, -2), "Shield bash pushes all three cells of the selected side")
	suite.expect(ally.health.current == 99 and enemy.health.current == 99 and third.health.current == 99 and outside.health.current == 100, "Shield bash damages the occupants of the selected side only")


func _fissure(suite: Node, fixture: Fixtures) -> void:
	var actor := fixture.unit(&"actor", PLAYER, Vector2i.ZERO)
	var first := fixture.unit(&"z_first", ENEMY, Vector2i(1, 0))
	var second := fixture.unit(&"a_second", ENEMY, Vector2i(2, 0))
	var cells: Array[Vector2i] = [actor.hex, first.hex, second.hex, Vector2i(3, 0), Vector2i(1, 1)]
	_equip(actor, &"fissure")
	var state := fixture.state(cells, [actor, first, second])
	var session := fixture.ai_session(state)
	var line_start := Vector2i(1, 0)
	var command := UseAbilityCommand.at_hex(actor.unit_id, line_start, _id(&"fissure"))
	suite.expect(not session.get_ability_target_hexes(actor.unit_id, _id(&"fissure")).has(line_start) and not session.step(command).accepted and actor.turn.main_action_available, "A fissure with no complete placement is rejected before spending the action")
	cells.append(Vector2i(2, 1))
	state = fixture.state(cells, [actor, first, second])
	state.hex_grid.set_traversal(line_start, true, 3)
	session = fixture.ai_session(state)
	var preview := session.preview(command)
	suite.expect(preview.accepted and preview.relocations.get(first.unit_id) == [line_start, Vector2i(1, 1)] and preview.relocations.get(second.unit_id) == [Vector2i(2, 0), Vector2i(2, 1)], "Fissure finds a complete matching and previews the actual origins and destinations")
	suite.expect(first.hex == line_start and state.hex_grid.is_traversable(line_start) and state.active_fissures.is_empty(), "Preview leaves the live grid and units unchanged")
	suite.expect(session.step(command).accepted and first.hex == preview.relocations[first.unit_id][1] and second.hex == preview.relocations[second.unit_id][1], "The resolved fissure uses the same destinations as preview")
	suite.expect(FissureService.line(actor.hex, line_start).all(func(hex: Vector2i) -> bool: return state.hex_grid.has_cell(hex) and not state.hex_grid.is_traversable(hex)), "The three fissure cells exist and block movement")
	var copy := session.create_prediction_engine()
	copy.execute(EndPhaseCommand.new(ENEMY))
	suite.expect(copy.get_hex_grid().is_traversable(line_start) and not state.hex_grid.is_traversable(line_start), "Fissure expiry in a copy leaves the live map blocked")
	session.step(EndPhaseCommand.new(ENEMY))
	suite.expect(state.active_fissures.is_empty() and state.hex_grid.is_traversable(line_start) and state.hex_grid.get_movement_cost(line_start) == 3, "Fissure expires on its owner's next phase and preserves cell cost")


func _intercept(suite: Node, fixture: Fixtures) -> void:
	var guard := fixture.unit(&"guard", PLAYER, Vector2i(2, 1))
	var pusher := fixture.unit(&"pusher", PLAYER, Vector2i.ZERO)
	var enemy := fixture.unit(&"enemy", ENEMY, Vector2i(1, 0))
	_equip(pusher, &"repulse")
	var session := _session(fixture, &"intercept", [guard, pusher, enemy])
	var command := UseAbilityCommand.at_hex(guard.unit_id, guard.hex, _id(&"intercept"))
	suite.expect(session.step(command).accepted and guard.statuses.has(UnitStatusCatalog.INTERCEPT_READY), "Intercept readies a single reaction")
	command = UseAbilityCommand.at_hex(pusher.unit_id, pusher.hex, _id(&"repulse"))
	var preview := session.preview(command)
	var change := preview.units.get(enemy.unit_id) as ActionPreview.UnitChange
	suite.expect(preview.accepted and change != null and change.health_after == 98 and guard.statuses.has(UnitStatusCatalog.INTERCEPT_READY), "Forced-entry interception is forecast without consuming the live stance")
	suite.expect(session.step(command).accepted and enemy.hex == Vector2i(2, 0) and enemy.health.current == 98 and not guard.statuses.has(UnitStatusCatalog.INTERCEPT_READY), "A pushed enemy triggers exactly one melee strike and consumes the stance")
	guard = fixture.unit(&"guard", PLAYER, Vector2i.ZERO)
	enemy = fixture.unit(&"enemy", ENEMY, Vector2i(2, 0), 2)
	session = _session(fixture, &"intercept", [guard, enemy])
	session.step(UseAbilityCommand.at_hex(guard.unit_id, guard.hex, _id(&"intercept")))
	var move := MoveCommand.new(enemy.unit_id, Vector2i(0, 1))
	suite.expect(session.step(move).accepted and enemy.health.is_defeated() and HexGrid.get_distance(guard.hex, enemy.hex) == 1, "Interception can stop a regular move with a lethal strike")
	guard = fixture.unit(&"guard", PLAYER, Vector2i.ZERO)
	enemy = fixture.unit(&"enemy", ENEMY, Vector2i(3, 0))
	session = _session(fixture, &"intercept", [guard, enemy])
	session.step(UseAbilityCommand.at_hex(guard.unit_id, guard.hex, _id(&"intercept")))
	session.step(EndPhaseCommand.new(ENEMY))
	suite.expect(not guard.statuses.has(UnitStatusCatalog.INTERCEPT_READY), "An unused stance expires at the start of the next own phase")


func _session(fixture: Fixtures, id: StringName, units: Array[UnitState]) -> BattleSession:
	_equip(units[0], id)
	var cells: Array[Vector2i] = []
	for x in range(-3, 8):
		for y in range(-3, 5):
			cells.append(Vector2i(x, y))
	return fixture.ai_session(fixture.state(cells, units))


func _equip(unit: UnitState, id: StringName) -> void:
	for ability: AbilityDefinition in Core.abilities:
		if ability.id == _id(id):
			unit.abilities[ability.id] = ability
			return


static func _id(id: StringName) -> StringName:
	return StringName("core:" + String(id))
