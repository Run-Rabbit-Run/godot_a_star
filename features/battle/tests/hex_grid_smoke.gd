## Самодостаточный smoke критического пути боя без внешнего test framework.
extends SceneTree


var _failures: Array[String] = []
var _checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_coordinate_mapping()
	_check_hex_grid()
	_check_movement_search()
	_check_turn_state()
	_check_turn_service()
	_check_battle_engine()
	_check_ranged_attack()
	_check_grenade_ability()
	_check_battle_session_factory()
	await _check_battle_scene()

	if _failures.is_empty():
		print("Battle smoke passed (%d checks)" % _checks)
		quit()
		return

	for failure in _failures:
		printerr("FAIL: ", failure)

	quit(1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1

	if not condition:
		_failures.append(message)


func _check_coordinate_mapping() -> void:
	var map_cells: Array[Vector2i] = [
		Vector2i.ZERO,
		Vector2i(11, 7),
		Vector2i(-3, -5),
	]

	for map_cell in map_cells:
		var axial_cell := HexCoordinateMapper.offset_to_axial(map_cell)
		_expect(
			HexCoordinateMapper.axial_to_offset(axial_cell) == map_cell,
			"Offset/axial conversion must round-trip for %s." % map_cell
		)


func _check_hex_grid() -> void:
	var cells: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(1, -1),
		Vector2i(0, -1),
		Vector2i(-1, 0),
		Vector2i(-1, 1),
		Vector2i(0, 1),
	]
	var movement_costs: Dictionary[Vector2i, int] = {
		Vector2i.ZERO: 0,
		Vector2i(1, 0): 2,
	}
	var grid := HexGrid.new(cells, movement_costs)

	_expect(grid.get_cells().size() == 7, "HexGrid must keep seven unique cells.")
	_expect(grid.get_neighbors(Vector2i.ZERO).size() == 6, "Center must have six neighbors.")
	_expect(grid.get_neighbors(Vector2i(1, 0)).size() == 3, "Edge cell must be clipped to existing neighbors.")
	_expect(grid.get_neighbors(Vector2i(10, 10)).is_empty(), "Missing cell must have no neighbors.")
	_expect(grid.get_movement_cost(Vector2i.ZERO) == 1, "Movement cost must be clamped to one.")
	_expect(grid.get_movement_cost(Vector2i(1, 0)) == 2, "Explicit movement cost must be preserved.")
	_expect(grid.get_movement_cost(Vector2i(10, 10)) == -1, "Missing cell cost must be minus one.")
	_expect(grid.get_cells_in_range(Vector2i.ZERO, 1).size() == 7, "Radius one must include center and six neighbors.")
	_expect(grid.get_cells_in_range(Vector2i.ZERO, -1).is_empty(), "Negative range must be empty.")
	_expect(HexGrid.get_distance(Vector2i.ZERO, Vector2i(2, -1)) == 2, "Axial distance must use cube geometry.")


func _check_movement_search() -> void:
	var cells: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(2, 0),
		Vector2i(3, 0),
	]
	var movement_costs: Dictionary[Vector2i, int] = {
		Vector2i(0, 0): 1,
		Vector2i(1, 0): 1,
		Vector2i(2, 0): 2,
		Vector2i(3, 0): 2,
	}
	var blocked_cells: Dictionary[Vector2i, bool] = {}
	var grid := HexGrid.new(cells, movement_costs)
	var result := MovementService.search(
		grid,
		Vector2i.ZERO,
		3,
		blocked_cells
	)
	var expected_path: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(2, 0),
	]

	_expect(result.get_cost(Vector2i(2, 0)) == 3, "Weighted route must cost 1 + 2.")
	_expect(result.get_cost(Vector2i(3, 0)) == -1, "Two difficult entries must exceed three points.")
	_expect(result.build_path(Vector2i(2, 0)) == expected_path, "Search result must restore the complete path.")
	_expect(result.build_path(Vector2i(3, 0)).is_empty(), "Unreachable destination must have no path.")
	_expect(MovementService.get_reachable_cells(grid, Vector2i.ZERO, 3, blocked_cells).size() == 3, "Legacy reachable API must stay compatible.")

	var blocked: Dictionary[Vector2i, bool] = {
		Vector2i(1, 0): true,
	}
	var blocked_result := MovementService.search(
		grid,
		Vector2i.ZERO,
		3,
		blocked
	)
	_expect(blocked_result.get_reachable_cells() == [Vector2i.ZERO], "Search must not pass through a blocked cell.")


func _check_turn_state() -> void:
	var clamped_turn := TurnState.new(-3)
	var turn := TurnState.new(3)

	_expect(clamped_turn.movement_max == 0 and clamped_turn.movement_remaining == 0, "TurnState must clamp a negative maximum.")
	_expect(not turn.spend_movement(-1), "Negative movement spend must be rejected.")
	_expect(not turn.spend_movement(4), "Overspending movement must be rejected.")
	_expect(turn.spend_movement(2) and turn.movement_remaining == 1, "Valid movement spend must reduce the remainder.")
	turn.start_turn()
	_expect(turn.movement_remaining == 3, "Starting a turn must restore movement.")


func _check_turn_service() -> void:
	var source_order: Array[StringName] = [&"alpha", &"beta"]
	var service := TurnService.new(source_order)
	source_order.clear()

	_expect(service.get_active_unit_id().is_empty(), "TurnService must be inactive before start.")
	_expect(service.advance_turn().is_empty(), "Advance before start must not activate a unit.")
	_expect(service.start() == &"alpha", "Start must select the copied first unit.")
	_expect(service.advance_turn() == &"beta", "Advance must select the next unit.")
	_expect(service.advance_turn() == &"alpha", "Turn order must wrap to the first unit.")

	var empty_order: Array[StringName] = []
	var empty_service := TurnService.new(empty_order)
	_expect(empty_service.start().is_empty() and empty_service.advance_turn().is_empty(), "Empty turn order must remain inactive.")


func _check_battle_engine() -> void:
	var cells: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(2, 0),
	]
	var grid := HexGrid.new(cells)
	var player := UnitState.new(
		&"player",
		&"player_definition",
		BattleFaction.Value.PLAYER,
		Vector2i(0, 0),
		TurnState.new(3),
		HealthState.new(10),
		2
	)
	var enemy_turn := TurnState.new(3)
	enemy_turn.spend_movement(2)
	var enemy := UnitState.new(
		&"enemy",
		&"enemy_definition",
		BattleFaction.Value.ENEMY,
		Vector2i(2, 0),
		enemy_turn,
		HealthState.new(10),
		2
	)
	var states: Dictionary[StringName, UnitState] = {
		player.unit_id: player,
		enemy.unit_id: enemy,
	}
	var order: Array[StringName] = [player.unit_id, enemy.unit_id]
	var objective := EliminateFactionObjective.new(
		BattleFaction.Value.ENEMY,
		"Eliminate enemies."
	)
	var objective_system := ObjectiveSystem.new(
		objective,
		BattleFaction.Value.PLAYER
	)
	var battle_state := BattleState.new(
		&"smoke_battle",
		grid,
		states,
		order,
		objective_system,
		123
	)
	var engine := BattleEngine.new(battle_state)

	_expect(engine.get_active_unit_id() == player.unit_id, "BattleEngine must start with the first unit.")
	_expect(
		engine.get_attackable_targets(player.unit_id).is_empty(),
		"Melee unit must not target an enemy two hexes away."
	)
	var inactive_move := engine.execute(
		MoveCommand.new(enemy.unit_id, Vector2i(1, 0))
	)
	_expect(not inactive_move.accepted, "Inactive unit command must be rejected.")
	_expect(inactive_move.state_revision == 0, "Rejected command must not change the state revision.")
	var player_move := engine.execute(
		MoveCommand.new(player.unit_id, Vector2i(1, 0))
	)
	_expect(player_move.accepted, "Active unit must execute a reachable move.")
	_expect(player_move.events.size() == 1 and player_move.events[0] is UnitMovedEvent, "Accepted move must emit UnitMovedEvent.")
	_expect(player_move.state_revision == 1, "Accepted command must increment the state revision.")
	_expect(player.hex == Vector2i(1, 0) and player.turn.movement_remaining == 2, "Move must update position and spend its cost.")
	var enemy_turn_resolution := engine.execute(EndTurnCommand.new(player.unit_id))
	_expect(enemy_turn_resolution.accepted and engine.get_active_unit_id() == enemy.unit_id, "Ending turn must activate the enemy.")
	_expect(enemy.turn.movement_remaining == 3, "Starting enemy turn must restore its movement.")
	var player_turn_resolution := engine.execute(EndTurnCommand.new(enemy.unit_id))
	_expect(player_turn_resolution.accepted and engine.get_active_unit_id() == player.unit_id, "Second ending must wrap to the player.")
	_expect(player.turn.movement_remaining == 3, "Starting player turn must restore its movement.")
	var unknown_turn := engine.execute(EndTurnCommand.new(&"missing"))
	_expect(not unknown_turn.accepted, "Unknown unit turn must be rejected.")


func _check_ranged_attack() -> void:
	var cells: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(2, 0),
		Vector2i(3, 0),
	]
	var ranged := UnitState.new(
		&"ranged",
		&"ranged_definition",
		BattleFaction.Value.PLAYER,
		Vector2i(0, 0),
		TurnState.new(3),
		HealthState.new(8),
		4,
		3
	)
	var target := UnitState.new(
		&"target",
		&"target_definition",
		BattleFaction.Value.ENEMY,
		Vector2i(3, 0),
		TurnState.new(3),
		HealthState.new(10),
		2
	)
	var states: Dictionary[StringName, UnitState] = {
		ranged.unit_id: ranged,
		target.unit_id: target,
	}
	var order: Array[StringName] = [ranged.unit_id, target.unit_id]
	var objective := EliminateFactionObjective.new(
		BattleFaction.Value.ENEMY,
		"Eliminate enemies."
	)
	var objective_system := ObjectiveSystem.new(
		objective,
		BattleFaction.Value.PLAYER
	)
	var battle_state := BattleState.new(
		&"ranged_smoke_battle",
		HexGrid.new(cells),
		states,
		order,
		objective_system,
		321
	)
	var engine := BattleEngine.new(battle_state)
	var targets := engine.get_attackable_targets(ranged.unit_id)
	_expect(
		targets.size() == 1 and targets[0].unit_id == target.unit_id,
		"Ranged unit must target an enemy at its maximum range."
	)

	var resolution := engine.execute(
		AttackCommand.new(ranged.unit_id, target.unit_id)
	)
	_expect(resolution.accepted, "Ranged attack at distance three must be accepted.")
	_expect(
		resolution.events.size() == 1
		and resolution.events[0] is UnitDamagedEvent,
		"Ranged attack must emit UnitDamagedEvent."
	)
	_expect(
		target.health.current == 6,
		"Ranged attack must apply basic attack damage."
	)
	_expect(
		not ranged.turn.main_action_available,
		"Ranged attack must spend the main action."
	)
	_expect(
		EnemyBrain.choose_attack(
			&"ai_ranged",
			Vector2i.ZERO,
			&"player",
			Vector2i(3, 0),
			3,
			true
		) != null,
		"AI must choose a basic attack when the target is in ranged reach."
	)
	_expect(
		EnemyBrain.choose_attack(
			&"ai_melee",
			Vector2i.ZERO,
			&"player",
			Vector2i(3, 0),
			1,
			true
		) == null,
		"Melee AI must not attack the same distant target."
	)


func _check_grenade_ability() -> void:
	var core_package := load(
		"res://content/packages/core/core_package.tres"
	) as ContentPackage
	_expect(core_package != null, "Grenade check requires the core package.")

	if core_package == null:
		return

	var packages: Array[ContentPackage] = [core_package]
	var load_result := ContentLoader.load_packages(packages)
	_expect(
		load_result.is_successful,
		"Core package with grenade must pass content validation."
	)

	if not load_result.is_successful:
		return

	var creation_result := BattleSessionFactory.create(
		BattleStartRequest.new(
			&"core:debug_battle",
			load_result.snapshot,
			77
		)
	)
	_expect(
		creation_result.is_successful,
		"Grenade check requires a debug battle session."
	)

	if not creation_result.is_successful:
		return

	var session := creation_result.session
	var player_id := &"core:debug_battle:player_1"
	var ally_id := &"core:debug_battle:player_2"
	var enemy_id := &"core:debug_battle:enemy_1"
	var outside_enemy_id := &"core:debug_battle:enemy_2"
	var player := session.get_unit(player_id)
	_expect(
		player.ability_ids.has(&"core:grenade")
		and player.ability_ranges[&"core:grenade"] == 3
		and player.ability_area_radii[&"core:grenade"] == 1,
		"Melee unit snapshot must expose grenade range and area radius."
	)

	var rejected := session.step(
		UseAbilityCommand.at_hex(
			player_id,
			Vector2i(11, 7),
			&"core:grenade"
		)
	)
	_expect(
		not rejected.accepted,
		"Grenade center beyond throw range must be rejected."
	)
	_expect(
		session.get_unit(player_id).turn.main_action_available,
		"Rejected grenade must not spend the main action."
	)

	var resolution := session.step(
		UseAbilityCommand.at_hex(
			player_id,
			Vector2i(8, 7),
			&"core:grenade"
		)
	)
	_expect(resolution.accepted, "Grenade at a valid center must be accepted.")
	_expect(
		resolution.events.size() == 4
		and resolution.events[0] is AreaAbilityUsedEvent,
		"Grenade must emit one area event and damage three affected units."
	)

	if resolution.events.size() > 0 and resolution.events[0] is AreaAbilityUsedEvent:
		var area_event := resolution.events[0] as AreaAbilityUsedEvent
		_expect(
			area_event.affected_hexes.size() == 7,
			"Grenade radius one must contain exactly seven existing hexes."
		)

	_expect(
		session.get_unit(player_id).health.current == 8,
		"Grenade must damage its user when the user is inside the area."
	)
	_expect(
		session.get_unit(ally_id).health.current == 6,
		"Grenade must apply friendly fire to an ally inside the area."
	)
	_expect(
		session.get_unit(enemy_id).health.current == 4,
		"Grenade must damage an enemy inside the area."
	)
	_expect(
		session.get_unit(outside_enemy_id).health.current == 5,
		"Grenade must not damage a unit outside the seven-hex area."
	)
	_expect(
		not session.get_unit(player_id).turn.main_action_available,
		"Grenade must spend the main action."
	)

	var ended := session.step(EndTurnCommand.new(player_id))
	_expect(ended.accepted, "Melee unit must be able to end its turn after grenade.")
	ended = session.step(EndTurnCommand.new(ally_id))
	_expect(ended.accepted, "Second ally must hand the turn to enemy AI.")
	var ai_command := session.get_next_ai_command()
	_expect(
		ai_command is UseAbilityCommand
		and (ai_command as UseAbilityCommand).targets_hex,
		"Melee AI must target a hex when it chooses grenade."
	)


func _check_battle_session_factory() -> void:
	var core_package := load(
		"res://content/packages/core/core_package.tres"
	) as ContentPackage
	_expect(core_package != null, "Core content package must load.")

	if core_package == null:
		return

	var packages: Array[ContentPackage] = [core_package]
	var load_result := ContentLoader.load_packages(packages)
	_expect(
		load_result.is_successful,
		"Core content package must produce a valid ContentSnapshot."
	)

	if not load_result.is_successful:
		return

	var request := BattleStartRequest.new(
		&"core:debug_battle",
		load_result.snapshot,
		42
	)
	var creation_result := BattleSessionFactory.create(request)
	_expect(
		creation_result.is_successful,
		"BattleSessionFactory must create the debug battle session."
	)

	if not creation_result.is_successful:
		return

	var session := creation_result.session
	var player_id := &"core:debug_battle:player_1"
	var enemy_id := &"core:debug_battle:enemy_1"
	var player_snapshot := session.get_unit(player_id)
	_expect(
		player_snapshot != null,
		"BattleSession must resolve a unit by its runtime placement id."
	)

	if player_snapshot == null:
		return

	var original_hex := player_snapshot.hex
	player_snapshot.hex = Vector2i(99, 99)
	_expect(
		session.get_unit(player_id).hex == original_hex,
		"Mutating UnitSnapshot must not change internal battle state."
	)

	var initial_revision := session.get_state_revision()
	var rejected := session.step(
		MoveCommand.new(enemy_id, Vector2i(8, 7))
	)
	_expect(
		not rejected.accepted,
		"BattleSession must reject a command from an inactive unit."
	)
	_expect(
		session.get_state_revision() == initial_revision,
		"Rejected BattleSession command must not change state revision."
	)


func _check_battle_scene() -> void:
	var packed_scene := load("res://debug_battle_launcher.tscn") as PackedScene
	_expect(packed_scene != null, "Debug battle launcher scene must load.")

	if packed_scene == null:
		return

	var launcher := packed_scene.instantiate()
	_expect(launcher != null, "Debug battle launcher must instantiate.")

	if launcher == null:
		return

	root.add_child(launcher)
	await process_frame
	await process_frame

	var map_view := launcher.get_node_or_null(
		"BattleScreen/BattleMap"
	) as BattleMapView
	var controller := launcher.get_node_or_null(
		"BattleScreen/BattleMap/BattleController"
	) as BattleController
	var input_router := launcher.get_node_or_null(
		"BattleScreen/BattleMap/BattleInputRouter"
	) as BattleInputRouter
	var hud := launcher.get_node_or_null(
		"BattleScreen/BattleMap/BattleUI"
	) as BattleHUD
	var selection_layer := launcher.get_node_or_null(
		"BattleScreen/BattleMap/SelectionLayer"
	) as TileMapLayer
	var terrain_layer := launcher.get_node_or_null(
		"BattleScreen/BattleMap/TerrainLayer"
	) as TileMapLayer
	var path_layer := launcher.get_node_or_null(
		"BattleScreen/BattleMap/PathLayer"
	) as TileMapLayer
	var targetable_layer := launcher.get_node_or_null(
		"BattleScreen/BattleMap/TargetableLayer"
	) as TileMapLayer
	var ability_area_layer := launcher.get_node_or_null(
		"BattleScreen/BattleMap/AbilityAreaLayer"
	) as TileMapLayer
	_expect(map_view != null, "Battle launcher must expose BattleMapView.")
	_expect(controller != null and input_router != null and hud != null, "Battle scene must expose controller, input router and HUD.")
	_expect(terrain_layer != null and selection_layer != null and path_layer != null and targetable_layer != null and ability_area_layer != null, "Battle scene must expose terrain, selection, path, targetable and ability area layers.")

	if map_view == null or controller == null or input_router == null or hud == null or terrain_layer == null or selection_layer == null or path_layer == null or targetable_layer == null or ability_area_layer == null:
		launcher.queue_free()
		await process_frame
		return

	var session := controller.get("_battle_session") as BattleSession
	var actors: Dictionary = controller.get("_unit_actors")
	_expect(session != null, "BattleController must initialize BattleSession.")

	if session == null:
		launcher.queue_free()
		await process_frame
		return

	var player_id := &"core:debug_battle:player_1"
	var ranged_player_id := &"core:debug_battle:player_2"
	var enemy_id := &"core:debug_battle:enemy_1"
	var ranged_enemy_id := &"core:debug_battle:enemy_2"
	var player := session.get_unit(player_id)
	var ranged_player := session.get_unit(ranged_player_id)
	var ranged_enemy := session.get_unit(ranged_enemy_id)
	var player_actor := actors.get(player_id) as UnitActor
	var ranged_player_actor := actors.get(ranged_player_id) as UnitActor
	var ranged_enemy_actor := actors.get(ranged_enemy_id) as UnitActor
	var hex_grid := session.get_hex_grid()
	var hud_root := hud.get_node_or_null("HUDRoot") as Control
	var strategist_panel := hud_root.get_node_or_null("StrategistPanel") as PanelContainer
	var active_unit_panel := hud_root.get_node_or_null("ActiveUnitPanel") as PanelContainer
	var turn_queue_panel := hud_root.get_node_or_null("TurnQueuePanel") as PanelContainer
	var target_panel := hud_root.get_node_or_null("TargetPanel") as PanelContainer
	var action_panel := hud_root.get_node_or_null("ActionPanel") as PanelContainer
	var system_panel := hud_root.get_node_or_null("SystemPanel") as PanelContainer
	var speed_panel := hud_root.get_node_or_null("SpeedPanel") as PanelContainer
	var movement_label := active_unit_panel.get_node_or_null(
		"Content/UnitHeader/Stats/MovementLabel"
	) as Label
	var movement_button := action_panel.get_node_or_null(
		"Content/SkillButtons/MovementButton"
	) as Button
	var grenade_button := action_panel.get_node_or_null(
		"Content/SkillButtons/GrenadeButton"
	) as Button
	var basic_attack_button := action_panel.get_node_or_null(
		"Content/SkillButtons/BasicAttackButton"
	) as Button
	var end_turn_button := action_panel.get_node_or_null(
		"Content/SkillButtons/EndTurnButton"
	) as Button
	var settings_button := system_panel.get_node_or_null(
		"Content/SettingsButton"
	) as Button
	var speed_1_button := speed_panel.get_node_or_null(
		"Content/Buttons/Speed1Button"
	) as Button
	var speed_2_button := speed_panel.get_node_or_null(
		"Content/Buttons/Speed2Button"
	) as Button
	var speed_label := speed_panel.get_node_or_null(
		"Content/SpeedLabel"
	) as Label
	var resolution_option := speed_panel.get_node_or_null(
		"Content/ResolutionRow/ResolutionOption"
	) as OptionButton
	var fullscreen_check := speed_panel.get_node_or_null(
		"Content/FullscreenCheck"
	) as CheckButton
	var display_status_label := speed_panel.get_node_or_null(
		"Content/DisplayStatusLabel"
	) as Label
	var target_placeholder := target_panel.get_node_or_null(
		"Content/TargetPlaceholder"
	) as Label
	var target_content := target_panel.get_node_or_null(
		"Content/TargetContent"
	) as HBoxContainer
	var target_portrait := target_panel.get_node_or_null(
		"Content/TargetContent/TargetPortrait"
	) as TextureRect
	var turn_order_container := turn_queue_panel.get_node_or_null(
		"Content/TurnOrderContainer"
	) as HBoxContainer
	_expect(
		movement_label != null
		and movement_button != null
		and grenade_button != null
		and basic_attack_button != null
		and end_turn_button != null
		and settings_button != null
		and speed_panel != null
		and speed_1_button != null
		and speed_2_button != null
		and speed_label != null
		and resolution_option != null
		and fullscreen_check != null
		and display_status_label != null
		and target_placeholder != null
		and target_content != null
		and target_portrait != null
		and turn_order_container != null,
		"Battle HUD must expose unit, target, turn order and settings controls."
	)
	_expect(
		resolution_option != null
		and resolution_option.item_count == 4
		and resolution_option.get_item_text(0) == "1920 × 1080"
		and resolution_option.get_item_text(3) == "1280 × 720"
		and fullscreen_check != null
		and fullscreen_check.text == "НА ВЕСЬ ЭКРАН"
		and display_status_label != null
		and not display_status_label.text.is_empty(),
		"Display settings must expose supported resolutions and fullscreen mode."
	)
	_expect(
		strategist_panel != null
		and active_unit_panel != null
		and turn_queue_panel != null
		and target_panel != null
		and action_panel != null
		and system_panel != null,
		"Battle HUD must contain all battlefield-first interface regions."
	)

	if (
		movement_label == null
		or movement_button == null
		or grenade_button == null
		or basic_attack_button == null
		or end_turn_button == null
		or settings_button == null
		or speed_panel == null
		or speed_1_button == null
		or speed_2_button == null
		or speed_label == null
		or target_placeholder == null
		or target_content == null
		or target_portrait == null
		or turn_order_container == null
	):
		launcher.queue_free()
		await process_frame
		return

	_expect(not speed_panel.visible, "Settings panel must start collapsed.")
	_expect(
		not target_panel.visible,
		"Target panel must stay hidden while no unit is hovered."
	)
	settings_button.pressed.emit()
	_expect(speed_panel.visible, "Settings button must open display settings.")
	settings_button.pressed.emit()
	_expect(not speed_panel.visible, "Settings button must close display settings.")

	_expect(player != null, "Battle session must expose the first player snapshot.")
	_expect(player_actor != null and actors.size() == 4, "Battle scene must create all four unit actors.")
	_expect(
		ranged_player != null
		and ranged_enemy != null
		and ranged_player.basic_attack_range == 3
		and ranged_enemy.basic_attack_range == 3,
		"Debug battle must contain one ranged unit on each side."
	)
	_expect(
		not (player_actor.get_node("CombatRoleLabel") as Label).visible,
		"Melee unit must not show the ranged marker."
	)
	_expect(
		ranged_player_actor != null
		and (ranged_player_actor.get_node("CombatRoleLabel") as Label).visible,
		"Ranged ally must show a visible ranged marker."
	)
	_expect(
		ranged_enemy_actor != null
		and (ranged_enemy_actor.get_node("CombatRoleLabel") as Label).visible,
		"Ranged enemy must show a visible ranged marker."
	)

	if (
		player == null
		or player_actor == null
		or ranged_player == null
		or ranged_enemy == null
		or ranged_player_actor == null
		or ranged_enemy_actor == null
	):
		launcher.queue_free()
		await process_frame
		return

	_expect(session.get_active_unit_id() == player.unit_id, "Battle scene must start with the first player active.")
	_expect(movement_label.text == "ОД   3 / 3", "HUD must show full player movement.")
	_expect(turn_order_container.get_child_count() == 4, "Turn queue must show all four combatants.")
	_expect(hex_grid.get_movement_cost(Vector2i(8, 6)) == 2, "Scene grid must read difficult terrain cost.")
	_expect(
		terrain_layer.get_cell_source_id(
			HexCoordinateMapper.axial_to_offset(Vector2i(8, 6))
		) != terrain_layer.get_cell_source_id(
			HexCoordinateMapper.axial_to_offset(Vector2i(7, 7))
		),
		"Difficult terrain must keep a visibly distinct tile after grid rendering."
	)
	_expect(selection_layer.get_used_cells().has(HexCoordinateMapper.axial_to_offset(player.hex)), "Selection must start on the player.")
	var grid_bounds := map_view.get_grid_global_bounds()
	var viewport_width := map_view.get_viewport_rect().size.x
	var left_grid_margin := grid_bounds.position.x
	var right_grid_margin := viewport_width - grid_bounds.end.x
	_expect(
		absf(left_grid_margin - right_grid_margin) <= 1.0,
		"Battle grid must have equal left and right margins: left=%s right=%s."
		% [left_grid_margin, right_grid_margin]
	)
	_expect(
		grid_bounds.end.x
		<= speed_panel.get_global_rect().position.x,
		"Settings panel must stay outside the battle grid: grid=%s panel=%s."
		% [grid_bounds, speed_panel.get_global_rect()]
	)
	_expect(
		active_unit_panel.is_visible_in_tree()
		and active_unit_panel.get_global_rect().has_point(
			Vector2(20.0, active_unit_panel.get_viewport_rect().size.y - 20.0)
		),
		"Active unit panel must be visible in the bottom-left corner: panel=%s viewport=%s."
		% [active_unit_panel.get_global_rect(), active_unit_panel.get_viewport_rect()]
	)
	_expect(
		movement_button.is_visible_in_tree() and not movement_button.disabled,
		"Active player must have a visible movement-mode button."
	)
	_expect(
		grenade_button.is_visible_in_tree() and not grenade_button.disabled,
		"Melee player must have a visible and available grenade button."
	)
	_expect(
		target_portrait.stretch_mode
		== TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		and target_portrait.custom_minimum_size.y <= 132.0,
		"Target portrait must fit completely inside a compact right panel slot."
	)
	_expect(not basic_attack_button.disabled, "Active unit panel must expose the basic attack skill.")

	input_router.hex_hovered.emit(Vector2i(9, 7))
	_expect(
		target_panel.visible
		and target_content.visible
		and not target_placeholder.visible,
		"Hovering any unit must open the right tactical analysis panel."
	)
	input_router.hex_hover_exited.emit()
	_expect(
		not target_panel.visible,
		"Hover exit must hide the tactical analysis panel."
	)
	settings_button.pressed.emit()
	_expect(speed_panel.visible, "Settings button must open animation speed controls.")
	speed_2_button.pressed.emit()
	_expect(speed_label.text.contains("2x"), "Speed controls must display the selected speed.")
	speed_1_button.pressed.emit()
	settings_button.pressed.emit()
	_expect(not speed_panel.visible, "Settings button must close animation speed controls.")

	grenade_button.pressed.emit()
	_expect(
		targetable_layer.get_used_cells().has(
			HexCoordinateMapper.axial_to_offset(Vector2i(8, 7))
		),
		"Grenade selection must highlight valid center hexes."
	)
	movement_button.pressed.emit()
	_expect(
		not targetable_layer.get_used_cells().has(
			HexCoordinateMapper.axial_to_offset(Vector2i(8, 7))
		),
		"Movement button must leave grenade targeting mode."
	)
	grenade_button.pressed.emit()
	input_router.hex_hovered.emit(Vector2i(8, 7))
	_expect(
		ability_area_layer.get_used_cells().size() == 7,
		"Grenade hover must preview the full seven-hex damage area."
	)
	input_router.hex_selected.emit(Vector2i(8, 7))
	_expect(
		map_view.get_node_or_null("GrenadeProjectile") != null,
		"Grenade use must create a visible thrown projectile."
	)
	await create_timer(0.3).timeout
	_expect(
		map_view.get_node_or_null("GrenadeExplosionCore") != null
		and map_view.get_node_or_null("GrenadeExplosionRing") != null,
		"Grenade impact must create a visible explosion and shockwave."
	)
	await create_timer(1.1).timeout
	player = session.get_unit(player_id)
	_expect(
		player.health.current == 8,
		"Scene grenade must apply friendly fire to its melee user."
	)
	_expect(
		ability_area_layer.get_used_cells().is_empty(),
		"Grenade area overlay must clear after explosion presentation."
	)

	input_router.hex_hovered.emit(Vector2i(7, 6))
	var path_stroke := map_view.get("_path_stroke") as Line2D
	_expect(not path_layer.get_used_cells().is_empty(), "Reachable hover must draw a path.")
	_expect(
		path_stroke != null
		and path_stroke.points.size() >= 2
		and path_stroke.width >= 4.0
		and path_stroke.default_color.a >= 0.95,
		"Reachable path must include a strong high-contrast route line."
	)
	input_router.hex_hover_exited.emit()
	_expect(
		path_layer.get_used_cells().is_empty()
		and path_stroke.points.is_empty(),
		"Hover exit must clear every path visual."
	)

	_expect(controller.set_playback_speed(1000.0), "Scene smoke must enable fast presentation.")
	input_router.hex_selected.emit(Vector2i(7, 6))
	await process_frame
	await process_frame
	player = session.get_unit(player_id)
	_expect(player.hex == Vector2i(7, 6) and player.turn.movement_remaining == 2, "Player click must execute a MoveCommand through BattleSession.")
	_expect(player_actor.global_position.is_equal_approx(map_view.hex_to_global_position(player.hex)), "Player actor must follow its snapshot.")
	_expect(movement_label.text == "ОД   2 / 3", "HUD must update after player movement.")

	end_turn_button.pressed.emit()
	await process_frame
	ranged_player = session.get_unit(ranged_player_id)
	var enemy := session.get_unit(enemy_id)
	_expect(
		session.get_active_unit_id() == ranged_player_id,
		"Second player turn must activate the ranged ally."
	)
	_expect(not grenade_button.visible, "Ranged ally must not expose the grenade button.")
	_expect(
		targetable_layer.get_used_cells().has(
			HexCoordinateMapper.axial_to_offset(enemy.hex)
		),
		"Ranged target highlight must include an enemy two hexes away."
	)

	_expect(
		controller.set_playback_speed(1.0),
		"Scene smoke must restore normal presentation speed."
	)
	input_router.hex_selected.emit(enemy.hex)
	_expect(
		map_view.get_node_or_null("RangedAttackProjectile") != null
		and map_view.get_node_or_null("RangedAttackTracer") != null,
		"Ranged attack must create a visible projectile and tracer."
	)
	await create_timer(0.3).timeout
	enemy = session.get_unit(enemy_id)
	_expect(
		enemy.health.current == 2,
		"Ranged scene attack must damage the distant enemy."
	)
	_expect(
		map_view.get_node_or_null("RangedAttackProjectile") == null
		and map_view.get_node_or_null("RangedAttackTracer") == null,
		"Ranged projectile visuals must be removed after presentation."
	)

	launcher.queue_free()
	await process_frame
