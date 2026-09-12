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
	var path_layer := launcher.get_node_or_null(
		"BattleScreen/BattleMap/PathLayer"
	) as TileMapLayer
	_expect(map_view != null, "Battle launcher must expose BattleMapView.")
	_expect(controller != null and input_router != null and hud != null, "Battle scene must expose controller, input router and HUD.")
	_expect(selection_layer != null and path_layer != null, "Battle scene must expose selection and path layers.")

	if map_view == null or controller == null or input_router == null or hud == null or selection_layer == null or path_layer == null:
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
	var player := session.get_unit(player_id)
	var player_actor := actors.get(player_id) as UnitActor
	var hex_grid := session.get_hex_grid()
	var vbox := hud.get_node("MovementPanel/VBoxContainer") as VBoxContainer
	var movement_label := vbox.get_node("MovementLabel") as Label

	_expect(player != null, "Battle session must expose the first player snapshot.")
	_expect(player_actor != null and actors.size() == 4, "Battle scene must create all four unit actors.")

	if player == null or player_actor == null:
		launcher.queue_free()
		await process_frame
		return

	_expect(session.get_active_unit_id() == player.unit_id, "Battle scene must start with the first player active.")
	_expect(movement_label.text == "Перемещение: 3 / 3", "HUD must show full player movement.")
	_expect(hex_grid.get_movement_cost(Vector2i(8, 6)) == 2, "Scene grid must read difficult terrain cost.")
	_expect(selection_layer.get_used_cells().has(HexCoordinateMapper.axial_to_offset(player.hex)), "Selection must start on the player.")

	input_router.hex_hovered.emit(Vector2i(7, 6))
	_expect(not path_layer.get_used_cells().is_empty(), "Reachable hover must draw a path.")
	input_router.hex_hover_exited.emit()
	_expect(path_layer.get_used_cells().is_empty(), "Hover exit must clear the path.")

	_expect(controller.set_playback_speed(1000.0), "Scene smoke must enable fast presentation.")
	input_router.hex_selected.emit(Vector2i(7, 6))
	await process_frame
	await process_frame
	player = session.get_unit(player_id)
	_expect(player.hex == Vector2i(7, 6) and player.turn.movement_remaining == 2, "Player click must execute a MoveCommand through BattleSession.")
	_expect(player_actor.global_position.is_equal_approx(map_view.hex_to_global_position(player.hex)), "Player actor must follow its snapshot.")
	_expect(movement_label.text == "Перемещение: 2 / 3", "HUD must update after player movement.")

	launcher.queue_free()
	await process_frame
