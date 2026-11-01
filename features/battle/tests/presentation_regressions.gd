extends RefCounted
## Graphical battle: screen setup, HUD, battle log and presentation of events.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")


func run_presentation(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var scene := load("res://features/battle/battle_screen.tscn") as PackedScene
	var screen := scene.instantiate() as BattleScreen
	var request := fixture.request(true)
	if request == null:
		screen.free()
		return
	suite.expect(screen.setup(request), "BattleScreen accepts validated request")
	suite.get_tree().root.add_child(screen)
	await suite.get_tree().process_frame
	await suite.get_tree().process_frame
	var controller := screen.get_node("BattleMap/BattleController") as BattleController
	var hud := screen.get_node("BattleMap/BattleUI") as BattleHUD
	hud.show_target("Test", null, "Противник", 10, 20, 2, 1, 4, 4, true, {&"core:burning": 2})
	suite.expect("Нет активных эффектов" not in (hud.get("_target_effects_label") as Label).text, "Target HUD displays actual statuses")
	hud.set_interaction_enabled(false)
	suite.expect(not (hud.get("_speed_4_button") as Button).disabled, "Playback speed remains available during presentation")
	var log_panel := hud.get_node("HUDRoot/BattleLogPanel") as PanelContainer
	var log_button := hud.get_node("HUDRoot/BattleLogButton") as Button
	var log_entries := hud.get_node("HUDRoot/BattleLogPanel/Content/Entries") as RichTextLabel
	suite.expect(not log_panel.visible and not log_button.button_pressed, "Battle log starts hidden")
	var before_log := log_entries.get_parsed_text()
	hud.append_battle_log("Hidden event [b]plain text[/b]")
	log_button.button_pressed = true
	suite.expect(log_panel.visible and "Hidden event [b]plain text[/b]" in log_entries.get_parsed_text(), "Opening log retains hidden events as literal text")
	suite.expect(not log_button.disabled, "Log is available during presentation")
	log_button.button_pressed = false
	log_button.button_pressed = true
	suite.expect(log_entries.get_parsed_text() == before_log + "Hidden event [b]plain text[/b]\n", "Toggling log preserves history without duplicate entries")
	suite.expect(log_panel.get_global_rect().end.x < (hud.get_node("HUDRoot/StrategistPanel") as Control).get_global_rect().position.x, "Log is to the left of round information")
	var logged_round: int = hud.get("_logged_round")
	var before_round := log_entries.get_parsed_text()
	hud.log_round(logged_round)
	suite.expect(log_entries.get_parsed_text() == before_round, "Repeated round refresh does not duplicate its heading")
	var log_units: Dictionary[StringName, UnitDefinition] = {}
	var victim := UnitDefinition.new()
	victim.display_name = "Victim"
	log_units[&"victim"] = victim
	var damage := UnitDamagedEvent.new(&"source", &"victim", 4, 0, true)
	damage.source_status_id = &"core:burning"
	var damage_text := BattleLogFormatter.describe(damage, log_units, null)
	suite.expect(UnitStatusCatalog.display_name(&"core:burning") in damage_text and "Victim" in damage_text and "4" in damage_text and "погибает" in damage_text, "Damage log identifies periodic source, damage and defeat")
	var status_unit := fixture.unit(&"victim", BattleFaction.Value.ENEMY, Vector2i.ZERO)
	var status_text := BattleLogFormatter.describe(UnitStatusChangedEvent.new(status_unit, {&"core:burning": 1}), log_units, null)
	suite.expect("снят" in status_text, "Log reports removed statuses")
	controller.set("_is_presenting", true)
	var revision := (controller.get("_battle_session") as BattleSession).get_state_revision()
	var rejected: BattleResolution = await controller.apply_map_mutations([MapMutation.apply_hex_state(Vector2i.ZERO, &"core:fire")])
	suite.expect(not rejected.accepted and (controller.get("_battle_session") as BattleSession).get_state_revision() == revision, "Concurrent public mutation rejected without state changes")
	controller.set("_is_presenting", false)
	var map := screen.get_node("BattleMap") as BattleMapView
	var layout_map := BattleDocumentSerializer.load(fixture.BATTLE_PATH).map_definition
	layout_map.has_custom_grid_offset = true
	layout_map.grid_offset_y = 0
	map.set_map_presentation(layout_map)
	var initial_position := map.position
	var backdrop: TextureRect = map.get("_battle_backdrop")
	var backdrop_position := backdrop.global_position
	var initial_hex := map.hex_to_global_position(Vector2i.ZERO)
	layout_map.grid_offset_y = 96
	map.set_map_presentation(layout_map)
	var pixel_scale := ReferenceCanvas.fit_scale(suite.get_viewport().get_visible_rect().size)
	suite.expect(map.position.is_equal_approx(initial_position + Vector2(0, 96 * pixel_scale)), "Runtime board uses the authored vertical offset at viewport scale")
	suite.expect(map.hex_to_global_position(Vector2i.ZERO).is_equal_approx(initial_hex + Vector2(0, 96 * pixel_scale)), "Runtime hex projection follows the shifted board")
	suite.expect(backdrop.global_position == backdrop_position, "Grid shifting leaves the backdrop fixed")
	map.call("_fit_battlefield_to_viewport")
	suite.expect(map.position.is_equal_approx(initial_position + Vector2(0, 96 * pixel_scale)), "Refitting retains the offset without accumulating it")
	var layer: TileMapLayer = map.get_node("TerrainLayer")
	var screen_point := map.hex_to_global_position(Vector2i.ZERO)
	suite.expect(HexCoordinateMapper.offset_to_axial(layer.local_to_map(layer.to_local(screen_point))) == Vector2i.ZERO, "Runtime input conversion remains aligned after shifting")
	layout_map.grid_offset_y = -48
	map.set_map_presentation(layout_map)
	suite.expect(map.position.is_equal_approx(initial_position + Vector2(0, -48 * pixel_scale)), "Runtime board supports upward offsets")
	layout_map.has_custom_grid_offset = false
	map.set_map_presentation(layout_map)
	suite.expect(map.position.is_equal_approx(initial_position + Vector2(0, BattleGridLayoutSettings.load_default() * pixel_scale)), "Runtime uses the project default for maps without their own height")
	layout_map.has_custom_grid_offset = true
	layout_map.grid_offset_y = 0
	map.set_map_presentation(layout_map)
	var grid := HexGrid.new([Vector2i.ZERO, Vector2i(1, 0)])
	grid.set_traversal(Vector2i(1, 0), false, 1)
	map.render_grid(grid)
	var markers := map.get_node("TerrainProperties") as Node2D
	suite.expect(markers.get_child_count() > 0, "Blocked terrain receives visible markers")
	suite.expect(markers.get_child_count() == 1, "Plain cells receive no marker nodes")
	var marker_labels := markers.find_children("*", "Label", true, false)
	var upright := (marker_labels[0] as Label).scale * map.scale if not marker_labels.is_empty() else Vector2.ZERO
	suite.expect(not marker_labels.is_empty() and is_equal_approx(upright.x, upright.y), "Marker text keeps upright proportions on the scaled board")
	var hex_state_art := map.get_node("HexStateVisuals") as Node2D
	suite.expect(markers.z_index == hex_state_art.z_index and markers.get_index() > hex_state_art.get_index(), "Markers draw above hex-state art")
	# Hex details consume displayed events; the permanent movement-cost digit is gone.
	var details := map.get_node("HexStateDetails") as HexStateDetails
	grid.set_hex_state(Vector2i.ZERO, &"core:burning_oil")
	map.render_grid(grid)
	suite.expect(markers.find_children("*", "Label", true, false).size() == 1, "State movement cost has no permanent numeric marker")
	var timers: Dictionary = details.get("_labels")
	suite.expect(timers.has(Vector2i.ZERO) and timers[Vector2i.ZERO].text == "3" and not timers[Vector2i.ZERO].visible, "State duration starts at three and is hidden without Alt")
	details.hover(Vector2i.ZERO)
	details.set("_hover_time", 0.35)
	details.call("_update_popup")
	var popup := details.get_node("HexStatePopup") as PanelContainer
	var body: Label = details.get("_body")
	suite.expect(popup.visible and "Горящее масло" == (details.get("_title") as Label).text and "Стоимость прохода: 2" in body.text and "Осталось ходов (раундов): 3" in body.text, "Hover popup shows state, cost and current duration")
	suite.expect("Горение ×3" in body.text and "Тягучее масло ×3" in body.text and "2 огненного" in body.text, "Hover properties match catalog effects and damage")
	var timer_event := MapMutationEvent.new(MapMutationKind.Value.APPLY_HEX_STATE, Vector2i.ZERO, &"core:default", true, 2)
	timer_event.hex_state_id = &"core:burning_oil"
	timer_event.hex_state_turns = 2
	timer_event.hex_state_changed = false
	map.apply_map_event(timer_event)
	suite.expect(timers[Vector2i.ZERO].text == "2" and "Осталось ходов (раундов): 2" in body.text, "Timer events update both badge and open popup")
	details.clear_hover()
	suite.expect(not popup.visible, "Leaving hex hides its popup")
	timer_event.hex_state_id = &""
	timer_event.hex_state_turns = 0
	timer_event.hex_state_changed = true
	map.apply_map_event(timer_event)
	suite.expect(not timers.has(Vector2i.ZERO), "Expiration removes duration badge")
	grid.set_hex_state(Vector2i.ZERO, &"")
	map.render_grid(grid)
	var selected: Array[Vector2i] = []
	var router := screen.get_node("BattleMap/BattleInputRouter") as BattleInputRouter
	router.setup(grid)
	router.hex_selected.connect(func(hex: Vector2i) -> void: selected.append(hex))
	router.set_interaction_enabled(true)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = map.get_canvas_transform() * map.hex_to_global_position(Vector2i.ZERO)
	router.set("_has_hovered_hex", false)
	router.call("_unhandled_input", click)
	suite.expect(selected.size() == 1 and selected[0] == Vector2i.ZERO, "Click computes fresh hex without prior hover")
	# Failure injection exercises complete state restore without emitting a test error log.
	controller.battle_failed.disconnect(screen._on_battle_failed)
	var failure_count := [0]
	controller.battle_failed.connect(func(_message: String) -> void: failure_count[0] += 1)
	var bad := BattleResolution.success([], revision, "", null)
	bad.terminal_error = "Injected terminal failure"
	var stopped: bool = await controller.call("_present_resolution", bad, controller.get("_unit_actors"), controller.get("_unit_views").definitions, map, hud)
	suite.expect(not stopped and controller.get("_runtime_failed"), "Terminal failure stops graphical playback")
	suite.expect(map.get_node("TerrainLayer").get_used_cells().size() == (controller.get("_battle_session") as BattleSession).get_hex_grid().get_cells().size(), "Failure repairs full visual map from authoritative grid")
	controller.call("_fail_runtime", "Repeated failure")
	suite.expect(failure_count[0] == 1, "Failure emitted exactly once")
	var parent := Node2D.new()
	var actor := Node2D.new()
	var sprite := Sprite2D.new()
	suite.get_tree().root.add_child(parent)
	parent.add_child(actor)
	actor.add_child(sprite)
	var animator := UnitMovementAnimator.new()
	var profile := UnitMovementProfile.new()
	profile.seconds_per_hex = 0.05
	var tween := animator.create_motion(actor, sprite, [Vector2(100, 0)], profile)
	parent.scale = Vector2(2, 3)
	parent.position = Vector2(20, 10)
	await tween.finished
	suite.expect(actor.position.is_equal_approx(Vector2(100, 0)) and actor.global_position.is_equal_approx(Vector2(220, 10)), "Movement follows resized/transformed battlefield parent")
	parent.queue_free()
	screen.queue_free()
	await suite.get_tree().process_frame
