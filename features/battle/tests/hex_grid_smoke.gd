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
	_check_hex_state_path_impacts()
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


func _find_ability_button(action_panel: Control, ability_id: StringName) -> Button:
	return action_panel.get_node_or_null(
		"Content/SkillButtons/%s" % BattleHUD.get_ability_button_name(ability_id)
	) as Button


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


func _create_hex_state_path_engine(
	state_ids: Dictionary[Vector2i, StringName],
	player_health: int = 10
) -> BattleEngine:
	var cells: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(2, 0),
		Vector2i(3, 0),
		Vector2i(4, 0),
	]
	var costs: Dictionary[Vector2i, int] = {}

	for cell: Vector2i in cells:
		costs[cell] = HexStateCatalog.get_movement_cost(
			state_ids.get(cell, StringName())
		)

	var grid := HexGrid.new(cells, costs, {}, {}, state_ids)
	var player := UnitState.new(
		&"player", &"player_definition", BattleFaction.Value.PLAYER,
		Vector2i.ZERO, TurnState.new(5), HealthState.new(player_health), 2
	)
	var enemy := UnitState.new(
		&"enemy", &"enemy_definition", BattleFaction.Value.ENEMY,
		Vector2i(4, 0), TurnState.new(5), HealthState.new(10), 2
	)
	var states: Dictionary[StringName, UnitState] = {
		player.unit_id: player,
		enemy.unit_id: enemy,
	}
	var order: Array[StringName] = [player.unit_id, enemy.unit_id]
	var objective := EliminateFactionObjective.new(
		BattleFaction.Value.ENEMY, "Eliminate enemies."
	)
	return BattleEngine.new(BattleState.new(
		&"hex_state_path_smoke", grid, states, order,
		ObjectiveSystem.new(objective, BattleFaction.Value.PLAYER), 123
	))


func _check_hex_state_path_impacts() -> void:
	var intermediate: Dictionary[Vector2i, StringName] = {
		Vector2i(1, 0): &"core:fire",
	}
	var engine := _create_hex_state_path_engine(intermediate)
	var resolution := engine.execute(MoveCommand.new(&"player", Vector2i(3, 0)))
	resolution.events = _movement_events(resolution.events)
	var player := engine.get_unit(&"player")
	_expect(resolution.accepted, "A route through fire must be accepted.")
	_expect(player.hex == Vector2i(3, 0), "The unit must reach the destination after surviving fire.")
	_expect(player.health.current == 9, "Intermediate fire must deal damage even when not the destination.")
	_expect(player.turn.movement_remaining == 2, "The traversed route must spend three movement points.")
	_expect(resolution.events.size() == 3, "Intermediate fire must split movement and damage events.")
	if resolution.events.size() == 3:
		_expect(resolution.events[0] is UnitMovedEvent and resolution.events[1] is UnitDamagedEvent and resolution.events[2] is UnitMovedEvent, "Damage must be presented at the crossed hex before movement continues.")
		var damage := resolution.events[1] as UnitDamagedEvent
		_expect(damage.source_hex_state_id == &"core:fire", "Damage event must identify the crossed hex state.")

	var destination: Dictionary[Vector2i, StringName] = {
		Vector2i(3, 0): &"core:fire",
	}
	engine = _create_hex_state_path_engine(destination)
	resolution = engine.execute(MoveCommand.new(&"player", Vector2i(3, 0)))
	resolution.events = _movement_events(resolution.events)
	_expect(engine.get_unit(&"player").health.current == 9, "Fire must also damage a unit stopping on it.")
	_expect(resolution.events.size() == 2 and resolution.events[0] is UnitMovedEvent and resolution.events[1] is UnitDamagedEvent, "Destination impact must follow arrival.")

	var repeated: Dictionary[Vector2i, StringName] = {
		Vector2i(1, 0): &"core:fire",
		Vector2i(2, 0): &"core:acid",
	}
	engine = _create_hex_state_path_engine(repeated)
	resolution = engine.execute(MoveCommand.new(&"player", Vector2i(3, 0)))
	resolution.events = _movement_events(resolution.events)
	_expect(engine.get_unit(&"player").health.current == 8, "Every crossed damaging hex must apply its own damage once.")
	_expect(resolution.events.size() == 5, "Both crossed hazards must emit movement and damage in order.")
	if resolution.events.size() == 5:
		_expect((resolution.events[1] as UnitDamagedEvent).source_hex_state_id == &"core:fire" and (resolution.events[3] as UnitDamagedEvent).source_hex_state_id == &"core:acid", "Hazards must resolve in route order.")

	engine = _create_hex_state_path_engine(intermediate, 1)
	resolution = engine.execute(MoveCommand.new(&"player", Vector2i(3, 0)))
	resolution.events = _movement_events(resolution.events)
	player = engine.get_unit(&"player")
	_expect(player.health.is_defeated() and player.hex == Vector2i(1, 0), "A lethal intermediate hazard must stop the unit on that hex.")
	_expect(player.turn.movement_remaining == 4, "A fatal route must only spend movement for traversed cells.")
	_expect(resolution.events.size() == 2 and resolution.events[0] is UnitMovedEvent and resolution.events[1] is UnitDamagedEvent, "A fatal intermediate impact must not animate the remaining route.")

	var costly: Dictionary[Vector2i, StringName] = {
		Vector2i(1, 0): &"core:oil",
	}
	engine = _create_hex_state_path_engine(costly)
	resolution = engine.execute(MoveCommand.new(&"player", Vector2i(3, 0)))
	resolution.events = _movement_events(resolution.events)
	_expect(resolution.accepted and engine.get_unit(&"player").turn.movement_remaining == 0 and engine.get_unit(&"player").health.current == 10, "Oil costs two movement points and acquires an additional one-point status penalty without damage.")


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
		resolution.events.size() >= 2
		and resolution.events[0] is UnitDamagedEvent
		and resolution.events[1] is TurnEndedEvent,
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
		resolution.events.filter(func(event: BattleEvent) -> bool: return event is UnitDamagedEvent).size() == 3
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
	_expect(not ended.accepted and session.get_active_unit_id() == ally_id, "Grenade automatically hands the turn to the ally; former user cannot end it twice.")
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


func _movement_events(events: Array[BattleEvent]) -> Array[BattleEvent]:
	var result: Array[BattleEvent] = []
	for event: BattleEvent in events:
		if event is UnitMovedEvent or event is UnitDamagedEvent:
			result.append(event)
	return result


func _check_battle_scene() -> void:
	# A fixed core fixture avoids coupling assertions to the owner's saved battle.
	var packages: Array[ContentPackage] = [load("res://content/packages/core/core_package.tres")]
	var content := ContentLoader.load_packages(packages)
	_expect(content.is_successful, "Core graphical fixture loads")
	if not content.is_successful:
		return
	var screen := (load("res://features/battle/battle_screen.tscn") as PackedScene).instantiate() as BattleScreen
	_expect(screen.setup(BattleStartRequest.new(&"core:debug_battle", content.snapshot, 42)), "Screen accepts core request")
	root.add_child(screen)
	await process_frame
	await process_frame
	var controller := screen.get_node("BattleMap/BattleController") as BattleController
	var session := controller.get("_battle_session") as BattleSession
	var actors: Dictionary = controller.get("_unit_actors")
	_expect(session != null and actors.size() == 4, "Core fixture creates four actors")
	var map := screen.get_node("BattleMap") as BattleMapView
	_expect(map.get_node("TerrainLayer").get_used_cells().size() == session.get_hex_grid().get_cells().size(), "Graphical terrain matches logical cells")
	var hud := screen.get_node("BattleMap/BattleUI") as BattleHUD
	_expect(hud.get("_target_effects_label") != null and hud.get("_speed_4_button") != null, "HUD exposes target effects and playback controls")
	screen.queue_free()
	await process_frame
