extends Node
## F6: fixed manual spear scenario, using the ordinary game/editor presentation.
## Content overrides are detached and never saved to authored battle documents.

func _ready() -> void:
	var request := create_request()
	if request == null:
		return
	var mode := "battle"
	var capture := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--spear-view="):
			mode = argument.trim_prefix("--spear-view=")
		if argument.begins_with("--capture-preview="):
			capture = argument.trim_prefix("--capture-preview=")
		if argument.begins_with("--preview-size="):
			var size := argument.trim_prefix("--preview-size=").split("x")
			DisplayServer.window_set_size(Vector2i(int(size[0]), int(size[1])))
	DisplayServer.window_set_title("A_star · копейщик · " + mode)
	if mode == "editor":
		var editor := preload("res://tools/battles/battle_editor.tscn").instantiate() as BattleEditorShell
		add_child(editor)
		editor.set("_snapshot", request.content_snapshot)
		(editor.get("_view") as EditorBattleView).snapshot = request.content_snapshot
		editor.call("_replace_document", BattleDocument.from_snapshot(request.content_snapshot, request.battle_id), "", false)
	elif mode == "unit":
		var editor := preload("res://tools/units/unit_editor.tscn").instantiate() as UnitEditor
		add_child(editor)
		var loaded := UnitLibrary.read_document("res://content/authored/units/spear_guard.json")
		editor.call("_set_document", loaded.document)
		(editor.get("_status") as Label).text = "Открыт копейщик из библиотеки проекта."
	else:
		var screen := preload("res://features/battle/battle_screen.tscn").instantiate() as BattleScreen
		if not screen.setup(request):
			push_error(screen.initialization_error)
			screen.free()
			return
		add_child(screen)
	if OS.get_cmdline_user_args().has("--exercise-preview") or OS.get_cmdline_user_args().has("--landed-preview"):
		await _exercise_battle()
	if not capture.is_empty():
		await get_tree().create_timer(1.6).timeout
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--preview-size="):
				var dimensions := argument.trim_prefix("--preview-size=").split("x")
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				DisplayServer.window_set_size(Vector2i(int(dimensions[0]), int(dimensions[1])))
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		var error := get_viewport().get_texture().get_image().save_png(capture)
		get_tree().quit(error)

static func create_request() -> BattleStartRequest:
	var settings := GameContentSettings.read()
	var loaded := ProjectBattleLoader.load_battle(settings.content_packages, "res://features/battle/tests/fixtures/regression_battle.json", 7)
	if loaded.request == null:
		push_error(loaded.error_message)
		return null
	var snapshot := loaded.request.content_snapshot
	var battle := snapshot.get_battle_definition(loaded.request.battle_id)
	var positions: Array[Vector2i] = [Vector2i(1, 6), Vector2i(2, 6), Vector2i(1, 8), Vector2i(3, 6), Vector2i(4, 6), Vector2i(3, 5)]
	battle.unit_placements[0].definition_id = &"custom_units:spear_guard"
	var units: Array[UnitDefinition] = []
	for index in range(battle.unit_placements.size()):
		var placement := battle.unit_placements[index]
		placement.start_hex = positions[index % positions.size()]
		placement.ai_profile_override_id = &""
		var unit := snapshot.get_unit_definition(placement.definition_id)
		unit.base_stats.max_health = 100
		units.append(unit)
	for side: BattleSideDefinition in battle.sides:
		side.control_source = BattleControlSource.Value.PLAYER
		side.ai_profile_id = &""
	loaded.request.content_snapshot = snapshot.with_battle_document(snapshot.get_map_definition(battle.map_id), battle, units)
	return loaded.request

## Script-driven checks through the controller's ordinary ability/hex/end-turn handlers.
func _exercise_battle() -> void:
	await get_tree().create_timer(1.0).timeout
	var screen := get_child(0) as BattleScreen
	var controller: BattleController = screen.get("_battle_controller")
	var session: BattleSession = controller.get("_battle_session")
	var owner_id := session.get_active_unit_id()
	controller.call("_on_ability_requested", &"core:spear_throw")
	await controller.call("_on_hex_selected", Vector2i(4, 6))
	if OS.get_cmdline_user_args().has("--landed-preview"):
		return
	for _turn in range(5):
		await controller.call("_on_end_turn_requested")
	if session.get_active_unit_id() != owner_id or not session.get_unit(owner_id).pending_spear_return.is_empty():
		push_error("Graphical spear return failed")
		get_tree().quit(1)
		return
	controller.call("_on_ability_requested", &"core:spear_sweep")
	await controller.call("_on_hex_selected", session.get_unit(owner_id).hex)
	for _turn in range(5):
		await controller.call("_on_end_turn_requested")
	controller.call("_on_ability_requested", &"core:spear_pin")
	await controller.call("_on_hex_selected", Vector2i(3, 6))
	var hud: BattleHUD = controller.get("_hud")
	(hud.get("_battle_log_button") as Button).button_pressed = true
	var log_text: String = (hud.get("_battle_log_entries") as RichTextLabel).get_parsed_text()
	if not log_text.contains("Копьё возвращается") or not log_text.contains("Взмах копьём") or not log_text.contains("Пригвоздить"):
		push_error("Graphical ability log missing spear actions")
		get_tree().quit(1)
		return
	print("Spear graphical flow passed: throw, return, sweep, pin via controller; script-driven, no physical mouse input")
