extends Node
## F6: manual sandbox using the normal BattleScreen and command pipeline.
## Changes exist only in this scene's loaded content; authored files are never saved.

func _ready() -> void:
	DisplayServer.window_set_title("A_star · типы урона и умения")
	var request := create_request()
	if request == null:
		return
	var screen := preload("res://features/battle/battle_screen.tscn").instantiate() as BattleScreen
	if not screen.setup(request):
		push_error(screen.initialization_error)
		screen.free()
		return
	add_child(screen)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-preview="):
			await get_tree().create_timer(1.0).timeout
			for size_argument: String in OS.get_cmdline_user_args():
				if size_argument.begins_with("--preview-size="):
					var dimensions := size_argument.trim_prefix("--preview-size=").split("x")
					if dimensions.size() == 2 and dimensions[0].is_valid_int() and dimensions[1].is_valid_int():
						DisplayServer.window_set_size(Vector2i(maxi(640, int(dimensions[0])), maxi(360, int(dimensions[1]))))
			await get_tree().create_timer(0.4).timeout
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			var path := argument.trim_prefix("--capture-preview=")
			var error := image.save_png(path)
			if error != OK:
				push_error("Preview capture failed: %s" % error_string(error))
			get_tree().quit(error)


## Snapshot getters return detached copies, so the sandbox publishes its changes as overrides.
static func create_request() -> BattleStartRequest:
	var settings := GameContentSettings.read()
	var loaded := ProjectBattleLoader.load_battle(settings.content_packages, settings.battle_document_path, 1)
	if loaded.request == null:
		push_error(loaded.error_message)
		return null
	var snapshot := loaded.request.content_snapshot
	# Demonstrate a first-turn lock without changing the authored laser resource.
	var laser := snapshot.get_ability_definition(&"core:laser")
	laser.initial_cooldown_turns = 1
	var battle := snapshot.get_battle_definition(loaded.request.battle_id)
	var positions: Array[Vector2i] = [Vector2i(1, 6), Vector2i(1, 4), Vector2i(1, 8), Vector2i(3, 6), Vector2i(4, 6), Vector2i(3, 5)]
	var passives: Array[StringName] = [&"core:electric_attack", &"core:fire_attack", &"core:water_attack", &"core:acid_attack", &"core:plasma_attack", &"core:electric_attack"]
	for side: BattleSideDefinition in battle.sides:
		side.control_source = BattleControlSource.Value.PLAYER
		side.ai_profile_id = &""
	# Placements may share a definition; one override per ID keeps the result deterministic.
	var unit_overrides: Dictionary[StringName, UnitDefinition] = {}
	for index in range(battle.unit_placements.size()):
		var placement := battle.unit_placements[index]
		placement.start_hex = positions[index % positions.size()]
		placement.ai_profile_override_id = &""
		var definition: UnitDefinition = unit_overrides.get(placement.definition_id)
		if definition == null:
			definition = snapshot.get_unit_definition(placement.definition_id)
			definition.base_stats.max_health = 100
			definition.base_stats.movement_points = 4
			definition.base_stats.basic_attack_damage = 3
			definition.base_stats.basic_attack_range = 6
			definition.ability_ids.assign([&"core:electromagnetic_shot", &"core:electric_turret", &"core:emp_grenade", &"core:laser"])
			unit_overrides[placement.definition_id] = definition
		definition.passive_ability_ids.assign([passives[index % passives.size()]])
	var turret := UnitPlacementDefinition.new()
	turret.placement_id = &"preview:turret"
	turret.definition_id = &"core:electric_turret_unit"
	turret.side_id = battle.unit_placements[0].side_id
	turret.start_hex = Vector2i(2, 7)
	battle.unit_placements.append(turret)
	var overrides: Array[UnitDefinition] = []
	overrides.assign(unit_overrides.values())
	var abilities: Array[AbilityDefinition] = [laser]
	loaded.request.content_snapshot = snapshot.with_battle_document(snapshot.get_map_definition(battle.map_id), battle, overrides, abilities)
	return loaded.request
