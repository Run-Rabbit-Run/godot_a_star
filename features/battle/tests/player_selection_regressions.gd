extends RefCounted
## Player action selection: what a hovered hex shows and what a clicked hex means.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var screen := preload("res://features/battle/battle_screen.tscn").instantiate() as BattleScreen
	suite.expect(screen.setup(fixture.spear_request()), "Selection battle setup accepted")
	suite.add_child(screen)
	await suite.get_tree().process_frame
	await suite.get_tree().process_frame
	var controller: BattleController = screen.get("_battle_controller")
	var selection: PlayerActionSelection = controller.get("_selection")
	var session: BattleSession = controller.get("_battle_session")
	var map: BattleMapView = controller.get("_map_view")
	var path_layer := map.get_node("%PathLayer") as TileMapLayer
	var area_layer := map.get_node("%AbilityAreaLayer") as TileMapLayer
	var active := session.get_unit(session.get_active_unit_id())

	var destination := Vector2i(999, 999)
	for hex: Vector2i in session.get_movement_search(active.unit_id).get_reachable_cells():
		if hex != active.hex and session.get_unit_at(hex) == null:
			destination = hex
			break
	selection.hover(destination)
	suite.expect(path_layer.get_used_cells().has(HexCoordinateMapper.axial_to_offset(destination)), "Hovering a reachable hex shows the path to it")
	suite.expect(selection.command_at(active, destination) is MoveCommand, "Clicking a reachable empty hex means moving")

	# Step next to an opponent through the session, then show the new options.
	var approach := _hex_next_to_opponent(session, active)
	if approach != active.hex:
		session.step(MoveCommand.new(active.unit_id, approach))
		active = session.get_unit(active.unit_id)
		selection.show_movement_and_attacks(active)
	var targets := session.get_attackable_targets(active.unit_id)
	suite.expect(not targets.is_empty(), "The active unit reaches an opponent to attack")
	if not targets.is_empty():
		selection.hover(targets[0].hex)
		suite.expect(map.get("_cursor_mode") != BattleMapView.CursorMode.DEFAULT and path_layer.get_used_cells().is_empty(), "Hovering an attackable opponent shows the attack cursor, not a path")
		suite.expect(selection.command_at(active, targets[0].hex) is AttackCommand, "Clicking an attackable opponent means attacking")

	suite.expect(not selection.select_ability(active, &"core:not_an_ability"), "A unit cannot aim an ability it does not have")
	var area_ability := StringName()
	for ability_id: StringName in active.ability_ids:
		var ability: AbilitySnapshot = active.abilities[ability_id]
		if ability.targets_hex and not session.get_ability_target_hexes(active.unit_id, ability_id).is_empty():
			area_ability = ability_id
			break
	suite.expect(not area_ability.is_empty() and selection.select_ability(active, area_ability), "The active unit aims a hex ability")
	if not area_ability.is_empty():
		var center: Vector2i = session.get_ability_target_hexes(active.unit_id, area_ability)[0]
		selection.hover(center)
		suite.expect(not area_layer.get_used_cells().is_empty() and path_layer.get_used_cells().is_empty(), "Hovering an ability target shows its area instead of a path")
		var command := selection.command_at(active, center)
		suite.expect(command is UseAbilityCommand and (command as UseAbilityCommand).ability_id == area_ability, "Clicking an ability target means using the aimed ability")
		selection.hover_exited()
		suite.expect(area_layer.get_used_cells().is_empty() and map.get("_cursor_mode") == BattleMapView.CursorMode.DEFAULT, "Leaving the map clears the area and the cursor")

	selection.show_movement_and_attacks(active)
	suite.expect(selection.command_at(active, destination) is MoveCommand, "Showing movement again drops the aimed ability")
	controller.call("_set_presenting", true)
	if not targets.is_empty():
		selection.hover(targets[0].hex)
		suite.expect(map.get("_cursor_mode") == BattleMapView.CursorMode.DEFAULT, "No attack cursor while events are presented")
	controller.call("_set_presenting", false)
	screen.queue_free()
	await suite.get_tree().process_frame
	await _run_phase_choice(suite, fixture)


## Inside a phase the player picks which ready unit acts, until one has started its turn.
func _run_phase_choice(suite: Node, fixture: Fixtures) -> void:
	var screen := preload("res://features/battle/battle_screen.tscn").instantiate() as BattleScreen
	suite.expect(screen.setup(fixture.spear_request()), "Phase choice battle setup accepted")
	suite.add_child(screen)
	await suite.get_tree().process_frame
	await suite.get_tree().process_frame
	var controller: BattleController = screen.get("_battle_controller")
	var session: BattleSession = controller.get("_battle_session")
	var first: StringName = controller.call("_acting_unit_id")
	var ready := session.get_ready_unit_ids()
	var other := StringName()
	for unit_id: StringName in ready:
		if unit_id != first and session.get_movement_search(unit_id).get_reachable_cells().size() > 1:
			other = unit_id
			break
	suite.expect(ready.size() > 1 and not other.is_empty(), "The player phase offers several ready units")
	if other.is_empty():
		screen.queue_free()
		return
	await controller.call("_on_hex_selected", session.get_unit(other).hex)
	suite.expect(controller.call("_acting_unit_id") == other and session.get_current_unit_id().is_empty(), "Clicking another ready unit chooses it without starting its turn")
	var destination := Vector2i(999, 999)
	for hex: Vector2i in session.get_movement_search(other).get_reachable_cells():
		if session.get_unit_at(hex) == null:
			destination = hex
			break
	await controller.call("_on_hex_selected", destination)
	suite.expect(session.get_current_unit_id() == other, "Moving the chosen unit starts its turn")
	await controller.call("_on_hex_selected", session.get_unit(first).hex)
	suite.expect(controller.call("_acting_unit_id") == other, "A started unit cannot be swapped for another")
	var hud: BattleHUD = controller.get("_hud")
	var round_label := hud.get_node("HUDRoot/%RoundLabel") as Label
	suite.expect(round_label != null and round_label.text.contains("ФАЗА ИГРОКА"), "The round label names the acting phase")
	await controller.call("_on_end_phase_requested")
	suite.expect(session.get_active_faction() == BattleFaction.Value.ENEMY and session.get_ready_unit_ids().size() > 0, "Ending the phase passes the turn to the enemy faction")
	screen.queue_free()
	await suite.get_tree().process_frame


## A reachable empty hex within basic attack range of a living opponent, or the unit's own hex.
func _hex_next_to_opponent(session: BattleSession, active: UnitSnapshot) -> Vector2i:
	var reachable := session.get_movement_search(active.unit_id).get_reachable_cells()
	reachable.sort()
	for opponent: UnitSnapshot in session.get_living_opponents(active.faction):
		if HexGrid.get_distance(active.hex, opponent.hex) <= active.basic_attack_range:
			return active.hex
		for hex: Vector2i in reachable:
			if session.get_unit_at(hex) == null and HexGrid.get_distance(hex, opponent.hex) <= active.basic_attack_range:
				return hex
	return active.hex
