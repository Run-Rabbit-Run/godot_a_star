extends RefCounted

const PLANS := BattleMapDefinition.CameraPlan


func run(suite: Node) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	suite.get_tree().root.add_child(viewport)
	var screen := (load("res://features/battle/battle_screen.tscn") as PackedScene).instantiate()
	viewport.add_child(screen)
	var map := screen.get_node("BattleMap") as BattleMapView
	var actor := Node2D.new()
	map.get_node("Units").add_child(actor)
	var definition := BattleMapDefinition.new()
	definition.presentation_frame = Vector2i(18, 12)
	definition.has_custom_grid_offset = true
	var cells: Array[Vector2i] = []
	for row in range(2, 10):
		for column in range(4, 14):
			cells.append(HexCoordinateMapper.offset_to_axial(Vector2i(column, row)))
	var grid := HexGrid.new(cells)
	map.set_map_presentation(definition)
	map.render_grid(grid)
	var far := map.scale
	var far_position := map.position
	var actor_far := actor.global_scale
	definition.camera_plan = PLANS.MEDIUM
	map.set_map_presentation(definition)
	suite.expect(map.scale.is_equal_approx(far * 1.15) and actor.global_scale.is_equal_approx(actor_far * 1.15), "Medium increases board and figures uniformly")
	definition.camera_plan = PLANS.CLOSE
	map.set_map_presentation(definition)
	suite.expect(map.scale.is_equal_approx(far * 1.30) and actor.global_scale.is_equal_approx(actor_far * 1.30), "Close increases board and figures more than medium")
	var first := map.hex_to_global_position(cells.front())
	var last := map.hex_to_global_position(cells.back())
	suite.expect(first.x > 100 and first.y > 210 and last.x < 1820 and last.y < 850, "The zoomed edge hexes stay inside the safe grid surface")

	var zoomed_scale := map.scale
	var zoomed_position := map.position
	grid.add_cell(Vector2i.ZERO, &"core:default", 1, true)
	map.render_grid(grid)
	suite.expect(map.scale.is_equal_approx(zoomed_scale) and map.position.is_equal_approx(zoomed_position), "An added outer hex does not reframe a running battle")
	definition.camera_plan = PLANS.FAR
	map.set_map_presentation(definition)
	suite.expect(map.scale.is_equal_approx(far) and map.position.is_equal_approx(far_position), "Far reproduces the original frame")

	definition.camera_plan = PLANS.CLOSE
	map.set_map_presentation(definition)
	viewport.size = Vector2i(1440, 1080)
	await suite.get_tree().process_frame
	suite.expect(map.scale.is_equal_approx(zoomed_scale * 0.75) and actor.global_scale.is_equal_approx(actor_far * 1.30 * 0.75), "Resize scales the board and the actors together")
	var router := map.get_node("BattleInputRouter") as BattleInputRouter
	router.setup(grid)
	var selected: Array[Vector2i] = []
	router.hex_selected.connect(func(hex: Vector2i) -> void: selected.append(hex))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = map.get_canvas_transform() * map.hex_to_global_position(cells.back())
	router.call("_unhandled_input", click)
	suite.expect(selected == [cells.back()], "Click on a zoomed edge hex selects it after resize")

	cells.clear()
	for row in range(12):
		for column in range(18):
			cells.append(HexCoordinateMapper.offset_to_axial(Vector2i(column, row)))
	# A fresh map snapshots the full field at its first render.
	var full := (load("res://features/battle/battle_screen.tscn") as PackedScene).instantiate()
	viewport.add_child(full)
	var full_map := full.get_node("BattleMap") as BattleMapView
	full_map.set_map_presentation(definition)
	full_map.render_grid(HexGrid.new(cells))
	suite.expect(full_map.scale.is_equal_approx(far * 0.75), "Close falls back to the existing projection on a full board")
	viewport.queue_free()
	await suite.get_tree().process_frame
