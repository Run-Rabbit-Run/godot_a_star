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
	var player := UnitState.new(&"player", Vector2i(0, 0), TurnState.new(3))
	var enemy_turn := TurnState.new(3)
	enemy_turn.spend_movement(2)
	var enemy := UnitState.new(&"enemy", Vector2i(2, 0), enemy_turn)
	var states: Dictionary[StringName, UnitState] = {
		player.unit_id: player,
		enemy.unit_id: enemy,
	}
	var order: Array[StringName] = [player.unit_id, enemy.unit_id]
	var engine := BattleEngine.new(grid, states, order)
	var empty_blocked: Dictionary[Vector2i, bool] = {}
	var enemy_blocked: Dictionary[Vector2i, bool] = {
		enemy.hex: true,
	}

	_expect(engine.get_active_unit_id() == player.unit_id, "BattleEngine must start with the first unit.")
	_expect(not engine.execute_move(MoveCommand.new(enemy.unit_id, Vector2i(1, 0)), empty_blocked), "Inactive unit command must be rejected.")
	_expect(engine.execute_move(MoveCommand.new(player.unit_id, Vector2i(1, 0)), enemy_blocked), "Active unit must execute a reachable move.")
	_expect(player.hex == Vector2i(1, 0) and player.turn.movement_remaining == 2, "Move must update position and spend its cost.")
	_expect(engine.end_turn() == enemy.unit_id and enemy.turn.movement_remaining == 3, "Ending turn must activate and restore the enemy.")
	_expect(engine.end_turn() == player.unit_id and player.turn.movement_remaining == 3, "Second ending must wrap and restore the player.")
	_expect(not engine.start_unit_turn(&"missing"), "Unknown unit turn must be rejected.")


func _check_battle_scene() -> void:
	var packed_scene := load("res://battle_map.tscn") as PackedScene
	_expect(packed_scene != null, "Battle map scene must load.")

	if packed_scene == null:
		return

	var map_view := packed_scene.instantiate() as BattleMapView
	_expect(map_view != null, "Battle map root must be BattleMapView.")

	if map_view == null:
		return

	root.add_child(map_view)
	await process_frame
	await process_frame

	var controller := map_view.get_node_or_null("BattleController") as BattleController
	var input_router := map_view.get_node_or_null("BattleInputRouter") as BattleInputRouter
	var hud := map_view.get_node_or_null("BattleUI") as BattleHUD
	var selection_layer := map_view.get_node_or_null("SelectionLayer") as TileMapLayer
	var path_layer := map_view.get_node_or_null("PathLayer") as TileMapLayer
	_expect(controller != null and input_router != null and hud != null, "Battle scene must expose controller, input router and HUD.")
	_expect(selection_layer != null and path_layer != null, "Battle scene must expose selection and path layers.")

	if controller == null or input_router == null or hud == null or selection_layer == null or path_layer == null:
		map_view.queue_free()
		await process_frame
		return

	var engine := controller.get("_battle_engine") as BattleEngine
	var hex_grid := controller.get("_hex_grid") as HexGrid
	var actors: Dictionary = controller.get("_unit_actors")
	var player := engine.get_unit(&"debug_player")
	var enemy := engine.get_unit(&"debug_enemy")
	var player_actor := actors.get(&"debug_player") as UnitActor
	var enemy_actor := actors.get(&"debug_enemy") as UnitActor
	var vbox := hud.get_node("MovementPanel/VBoxContainer") as VBoxContainer
	var movement_label := vbox.get_node("MovementLabel") as Label
	var end_turn_button := vbox.get_node("EndTurnButton") as Button

	_expect(engine.get_active_unit_id() == player.unit_id, "Battle scene must start with the player active.")
	_expect(movement_label.text == "Перемещение: 3 / 3", "HUD must show full player movement.")
	_expect(hex_grid.get_movement_cost(Vector2i(8, 6)) == 2, "Scene grid must read difficult terrain cost.")
	_expect(selection_layer.get_used_cells().has(HexCoordinateMapper.axial_to_offset(player.hex)), "Selection must start on the player.")

	input_router.hex_hovered.emit(Vector2i(9, 5))
	_expect(not path_layer.get_used_cells().is_empty(), "Reachable hover must draw a path.")
	input_router.hex_hover_exited.emit()
	_expect(path_layer.get_used_cells().is_empty(), "Hover exit must clear the path.")

	input_router.hex_selected.emit(Vector2i(7, 6))
	_expect(player.hex == Vector2i(7, 6) and player.turn.movement_remaining == 2, "Player click must execute a MoveCommand.")
	_expect(player_actor.global_position.is_equal_approx(map_view.hex_to_global_position(player.hex)), "Player actor must follow its state.")
	_expect(movement_label.text == "Перемещение: 2 / 3", "HUD must update after player movement.")

	end_turn_button.pressed.emit()
	_expect(engine.get_active_unit_id() == enemy.unit_id, "End turn button must activate the enemy.")
	_expect(movement_label.text == "Перемещение: 3 / 3", "Enemy turn must start with full movement.")
	var enemy_before_blocked_click := enemy.hex
	input_router.hex_selected.emit(player.hex)
	_expect(enemy.hex == enemy_before_blocked_click, "Enemy must not enter the occupied player cell.")
	input_router.hex_selected.emit(Vector2i(10, 7))
	_expect(enemy.hex == Vector2i(10, 7) and enemy.turn.movement_remaining == 2, "Enemy must move through the same command flow.")
	_expect(enemy_actor.global_position.is_equal_approx(map_view.hex_to_global_position(enemy.hex)), "Enemy actor must follow its state.")

	end_turn_button.pressed.emit()
	_expect(engine.get_active_unit_id() == player.unit_id, "Second end turn must return control to the player.")
	_expect(player.turn.movement_remaining == 3 and movement_label.text == "Перемещение: 3 / 3", "Returning player must restore movement and HUD.")

	map_view.queue_free()
	await process_frame
