extends RefCounted
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")

func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var cells: Array[Vector2i] = []
	for x in range(-5, 6):
		for y in range(-5, 6):
			cells.append(Vector2i(x, y))
	var user: UnitState = fixture.unit(&"spear", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var enemy: UnitState = fixture.unit(&"enemy", BattleFaction.Value.ENEMY, Vector2i(2, 0))
	var ally: UnitState = fixture.unit(&"ally", BattleFaction.Value.PLAYER, Vector2i(1, 0))
	var beyond: UnitState = fixture.unit(&"beyond", BattleFaction.Value.ENEMY, Vector2i(5, 0))
	for id: String in ["spear_throw", "spear_sweep", "spear_pin"]:
		var ability := load("res://features/abilities/definitions/" + id + ".tres") as AbilityDefinition
		user.abilities[ability.id] = ability
		suite.expect(ability.validate().is_empty(), "Spear ability validates: " + id)
	var state: BattleState = fixture.state(cells, [user, ally, enemy, beyond])
	var engine := BattleEngine.new(state)
	var targets := engine.get_ability_target_hexes(user.unit_id, &"core:spear_throw")
	suite.expect(targets.has(Vector2i(2, 1)), "Throw accepts non-axis hex")
	suite.expect(targets.has(Vector2i(4, 0)) and not targets.has(Vector2i(5, 0)), "Throw range is four")
	var rejected := engine.execute(UseAbilityCommand.at_hex(user.unit_id, Vector2i(5, 0), &"core:spear_throw"))
	suite.expect(not rejected.accepted and user.turn.main_action_available and user.pending_spear_return.is_empty(), "Illegal throw is atomic")
	var result := engine.execute(UseAbilityCommand.at_hex(user.unit_id, Vector2i(4, 0), &"core:spear_throw"))
	suite.expect(result.accepted, "Throw accepted")
	suite.expect(enemy.health.current == 97 and ally.health.current == 97, "Throw hits both factions")
	suite.expect(beyond.health.current == 100 and user.health.current == 100, "Throw stops at target and excludes owner")
	suite.expect(not user.pending_spear_return.is_empty(), "Return is pending after throw")
	var predicted := engine.fork_for_prediction()
	predicted.execute(EndTurnCommand.new(ally.unit_id))
	predicted.execute(EndTurnCommand.new(enemy.unit_id))
	predicted.execute(EndTurnCommand.new(beyond.unit_id))
	suite.expect(not user.pending_spear_return.is_empty() and enemy.health.current == 97, "Forecast return does not mutate live state")
	engine.execute(EndTurnCommand.new(ally.unit_id))
	engine.execute(EndTurnCommand.new(enemy.unit_id))
	var returned := engine.execute(EndTurnCommand.new(beyond.unit_id))
	suite.expect(enemy.health.current == 94 and ally.health.current == 94 and user.health.current == 100, "Return damages path once and excludes owner")
	suite.expect(user.pending_spear_return.is_empty(), "Pending return consumed")
	var boundary := -1
	var damage_index := -1
	for index in range(returned.events.size()):
		if returned.events[index] is TurnEndedEvent:
			boundary = index
		if returned.events[index] is UnitDamagedEvent and damage_index < 0:
			damage_index = index
	suite.expect(boundary >= 0 and damage_index > boundary, "Return follows previous turn boundary")
	var path := AbilityExecutor.get_path_hexes(state.hex_grid, Vector2i.ZERO, Vector2i(2, 1))
	suite.expect(path.size() == 3 and path[-1] == Vector2i(2, 1), "Non-axis path has one hex per step")
	suite.expect(not path.has(Vector2i.ZERO), "Path excludes source")
	# Sweep reads current base attack, includes allies, excludes owner and distant cells.
	user.basic_attack_damage = 7
	ally.hex = Vector2i(1, 0)
	enemy.hex = Vector2i(0, 1)
	var sweep := engine.execute(UseAbilityCommand.at_hex(user.unit_id, user.hex, &"core:spear_sweep"))
	suite.expect(sweep.accepted, "Sweep targets owner's hex")
	suite.expect(ally.health.current == 87 and enemy.health.current == 87, "Sweep uses current base damage on both factions")
	suite.expect(user.health.current == 100 and beyond.health.current == 100, "Sweep excludes self and distant units")
	# Pin status is observed before automatic end-turn can consume a skipped victim turn.
	state.turn_service.start()
	user.turn.start_turn()
	enemy.hex = Vector2i(2, 0)
	var pin := AbilityExecutor.execute(state, UseAbilityCommand.new(user.unit_id, enemy.unit_id, &"core:spear_pin"))
	suite.expect(pin.accepted and enemy.health.current == 80, "Pin deals current base damage at range two")
	suite.expect(enemy.statuses.get(&"core:paralysis", 0) == 1, "Pin applies one paralysis level")
	# Basic melee retaliation, no chain, no main action expenditure on defender.
	var attacker: UnitState = fixture.unit(&"attacker", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var defender: UnitState = fixture.unit(&"defender", BattleFaction.Value.ENEMY, Vector2i(1, 0))
	attacker.passive_ability_ids = [&"core:melee_retaliation"]
	defender.passive_ability_ids = [&"core:melee_retaliation"]
	defender.basic_attack_damage = 5
	state = fixture.state(cells, [attacker, defender])
	engine = BattleEngine.new(state)
	var attack := engine.execute(AttackCommand.new(attacker.unit_id, defender.unit_id))
	suite.expect(attack.accepted and defender.health.current == 98 and attacker.health.current == 95, "Melee attack gets one retaliation without chain")
	var damage_count := 0
	for event: BattleEvent in attack.events:
		if event is UnitDamagedEvent:
			damage_count += 1
	suite.expect(damage_count == 2, "Exactly attack and response damage events")
	suite.expect(defender.turn.main_action_available, "Response does not spend defender action")
	var events: Array[BattleEvent] = []
	defender.statuses[&"core:paralysis"] = 1
	RetaliationService.respond(state, attacker, defender, events)
	suite.expect(events.is_empty(), "Paralyzed defender cannot respond")
	defender.statuses.clear()
	defender.health.current = 0
	RetaliationService.respond(state, attacker, defender, events)
	suite.expect(events.is_empty(), "Defeated defender cannot respond")
	defender.health.current = 100
	defender.hex = Vector2i(2, 0)
	RetaliationService.respond(state, attacker, defender, events)
	suite.expect(events.is_empty(), "Response has melee reach")
	defender.hex = Vector2i(1, 0)
	attacker.basic_attack_range = 3
	attacker.turn.start_turn()
	state.turn_service.start()
	engine.execute(AttackCommand.new(attacker.unit_id, defender.unit_id))
	suite.expect(attacker.health.current == 95, "Ranged attack at adjacent hex does not trigger response")
	# Return resolves even when owner is paralyzed, and uses current occupants.
	user.pending_spear_return = {"hex": Vector2i(4, 0), "ability_id": &"core:spear_throw"}
	user.statuses[&"core:paralysis"] = 1
	enemy.hex = Vector2i(4, 0)
	var before := enemy.health.current
	state = fixture.state(cells, [user, enemy])
	events.clear()
	SpearReturnService.resolve(state, user, events)
	suite.expect(enemy.health.current == before - 3 and user.pending_spear_return.is_empty(), "Return includes endpoint and works while paralyzed")
	SpearReturnService.resolve(state, user, events)
	suite.expect(enemy.health.current == before - 3, "Return is not delivered twice")
	user.pending_spear_return = {"hex": Vector2i(4, 0), "ability_id": &"core:spear_throw"}
	user.health.current = 0
	SpearReturnService.resolve(state, user, events)
	suite.expect(enemy.health.current == before - 3 and user.pending_spear_return.is_empty(), "Defeated owner cannot return spear")

	# Geometry stays contiguous and reversible for all off-axis endpoints.
	var geometry_ok := true
	for target_hex: Vector2i in cells:
		if HexGrid.get_distance(Vector2i.ZERO, target_hex) > 4:
			continue
		var forward := AbilityExecutor.get_path_hexes(state.hex_grid, Vector2i.ZERO, target_hex)
		var reverse := AbilityExecutor.get_path_hexes(state.hex_grid, target_hex, Vector2i.ZERO)
		var previous := Vector2i.ZERO
		for hex: Vector2i in forward:
			geometry_ok = geometry_ok and HexGrid.get_distance(previous, hex) == 1
			previous = hex
		forward.erase(target_hex)
		reverse.erase(Vector2i.ZERO)
		reverse.reverse()
		geometry_ok = geometry_ok and forward == reverse
	suite.expect(geometry_ok, "Every range-four path is contiguous and reversible")
	# Missing map cells do not stop the spear.
	var sparse_cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i(2, 0), Vector2i(4, 0)]
	var sparse_path := AbilityExecutor.get_path_hexes(HexGrid.new(sparse_cells), Vector2i.ZERO, Vector2i(4, 0))
	suite.expect(sparse_path == [Vector2i(2, 0), Vector2i(4, 0)], "Spear crosses absent cells without extending past endpoint")
	user.health.current = 100
	user.statuses.clear()
	user.hex = Vector2i.ZERO
	user.pending_spear_return = {"hex": Vector2i(4, 0), "ability_id": &"core:spear_throw"}
	enemy.hex = Vector2i(2, 0)
	enemy.health.current = 3
	enemy.statuses.clear()
	state = fixture.state(cells, [enemy, user])
	engine = BattleEngine.new(state)
	var terminal := engine.execute(EndTurnCommand.new(enemy.unit_id))
	suite.expect(terminal.accepted and terminal.battle_result != null and enemy.health.is_defeated(), "Lethal return finishes battle at owner turn start")
	suite.expect(user.pending_spear_return.is_empty(), "Lethal return is consumed")
	# Adjacent sweep can trigger a response; pin paralyzes its victim before responses.
	user.health.current = 100
	user.turn.start_turn()
	user.ability_cooldowns.clear()
	enemy.health.current = 100
	enemy.hex = Vector2i(1, 0)
	enemy.statuses.clear()
	enemy.passive_ability_ids = [&"core:melee_retaliation"]
	enemy.basic_attack_damage = 5
	state = fixture.state(cells, [user, enemy])
	engine = BattleEngine.new(state)
	engine.execute(UseAbilityCommand.at_hex(user.unit_id, user.hex, &"core:spear_sweep"))
	suite.expect(user.health.current == 95 and enemy.health.current == 93, "Melee sweep triggers one response")
	user.turn.start_turn()
	state.turn_service.start()
	var pin_health := user.health.current
	var adjacent_pin := AbilityExecutor.execute(state, UseAbilityCommand.new(user.unit_id, enemy.unit_id, &"core:spear_pin"))
	suite.expect(adjacent_pin.accepted and user.health.current == pin_health and enemy.statuses.get(&"core:paralysis", 0) == 1, "Pin disables response through paralysis")
	# A defender's lethal response advances the defeated attacker's turn normally.
	attacker.basic_attack_range = 1
	attacker.health.current = 1
	attacker.turn.start_turn()
	defender.health.current = 100
	state = fixture.state(cells, [attacker, defender])
	engine = BattleEngine.new(state)
	var lethal_response := engine.execute(AttackCommand.new(attacker.unit_id, defender.unit_id))
	suite.expect(lethal_response.accepted and attacker.health.is_defeated() and lethal_response.battle_result != null, "Lethal response resolves the battle")
	var encoded: Dictionary = BattleLogSerializer.encode(UnitSnapshot.new(user))
	suite.expect(encoded.has("pending_spear_return"), "Diagnostics include pending return state")

func run_editor(suite: Node) -> void:
	var editor := preload("res://tools/units/unit_editor.tscn").instantiate() as UnitEditor
	suite.add_child(editor)
	await suite.get_tree().process_frame
	var active: MenuButton = editor.get("_active_menu")
	var passive: MenuButton = editor.get("_passive_menu")
	suite.expect(active != null and passive != null, "Two ability dropdowns exist")
	var popup := active.get_popup()
	suite.expect(not popup.hide_on_checkable_item_selection, "Multiple selection leaves dropdown open")
	for index in range(popup.item_count):
		if popup.get_item_metadata(index) in ["core:spear_throw", "core:spear_sweep"]:
			popup.index_pressed.emit(index)
	var data: Dictionary = editor.get("_document")
	suite.expect(data.abilities.has("core:spear_throw") and data.abilities.has("core:spear_sweep"), "Dropdown selects multiple active abilities")
	editor.call("_undo_edit")
	suite.expect((editor.get("_document") as Dictionary).abilities.size() == 1, "Dropdown selection supports undo")
	editor.call("_redo_edit")
	suite.expect((editor.get("_document") as Dictionary).abilities.size() == 2, "Dropdown selection supports redo")
	for index in range(passive.get_popup().item_count):
		if passive.get_popup().get_item_metadata(index) == "core:melee_retaliation":
			passive.get_popup().index_pressed.emit(index)
	suite.expect((editor.get("_document") as Dictionary).passives.has("core:melee_retaliation"), "Passive dropdown selects retaliation")
	suite.expect(UnitLibrary.validate(editor.get("_document")).is_empty(), "Selected active and passive IDs validate")
	editor.queue_free()
	await suite.get_tree().process_frame


func run_presentation(suite: Node) -> void:
	var request := preload("res://tools/units/spear_preview.gd").create_request()
	var screen := preload("res://features/battle/battle_screen.tscn").instantiate() as BattleScreen
	suite.expect(screen.setup(request), "Spear visual battle setup accepted")
	suite.add_child(screen)
	await suite.get_tree().process_frame
	await suite.get_tree().process_frame
	var controller: BattleController = screen.get("_battle_controller")
	var queue: BattlePresentationQueue = controller.get("_presentation_queue")
	queue.set_speed(4.0)
	var session: BattleSession = controller.get("_battle_session")
	var owner_id := session.get_active_unit_id()
	var hud := screen.get_node("BattleMap/BattleUI") as BattleHUD
	var sweep_button := hud.find_child(BattleHUD.get_ability_button_name(&"core:spear_sweep"), true, false) as Button
	var attack := session.get_unit(owner_id).basic_attack_damage
	suite.expect(sweep_button != null and sweep_button.tooltip_text.contains("%d урона (физический)" % attack), "Battle ability tooltip shows the description with the acting unit's attack")
	controller.call("_on_ability_requested", &"core:spear_throw")
	await controller.call("_on_hex_selected", Vector2i(4, 6))
	var landed: Dictionary = queue.get("_landed_spears")
	suite.expect(landed.size() == 1 and landed.has(owner_id), "Throw leaves one persistent spear on landing hex")
	var glyph: Node2D = landed.get(owner_id)
	suite.expect(is_instance_valid(glyph) and glyph.visible and glyph.get_meta("landing_hex") == Vector2i(4, 6), "Visible spear represents actual landing hex")
	var map: BattleMapView = controller.get("_map_view")
	suite.expect(glyph.global_position.distance_to(map.hex_to_global_position(Vector2i(4, 6))) < 16, "Spear is drawn at landing hex on battlefield")
	await controller.call("_on_end_turn_requested")
	suite.expect(is_instance_valid(glyph) and (queue.get("_landed_spears") as Dictionary).has(owner_id), "Spear persists during another unit's turn")
	for _turn in range(4):
		await controller.call("_on_end_turn_requested")
	await suite.get_tree().process_frame
	suite.expect((queue.get("_landed_spears") as Dictionary).is_empty() and not is_instance_valid(glyph), "Return removes stationary spear without duplicate leftover")
	suite.expect(session.get_active_unit_id() == owner_id and session.get_unit(owner_id).pending_spear_return.is_empty(), "Spear presentation preserves return mechanics")
	screen.queue_free()
	await suite.get_tree().process_frame
