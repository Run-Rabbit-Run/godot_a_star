extends Node
## F6: ordinary saved battlefield with temporary terrain and all creation abilities.
## The authored battle, units, and preferences are never saved by this scene.

func _ready() -> void:
	DisplayServer.window_set_title("A_star · состояния гексов и юнитов")
	var settings := GameContentSettings.read()
	var loaded := ProjectBattleLoader.load_battle(settings.content_packages, settings.battle_document_path, 1)
	if loaded.request == null:
		push_error(loaded.error_message)
		return
	var snapshot := loaded.request.content_snapshot
	var battle := snapshot.get_battle_definition(loaded.request.battle_id)
	var map := snapshot.get_map_definition(battle.map_id)
	var states: Array[StringName] = [&"core:water", &"core:electricity", &"core:fire", &"core:oil", &"core:acid", &"core:plasma"]
	for index in range(battle.unit_placements.size()):
		var placement := battle.unit_placements[index]
		var definition := snapshot.get_unit_definition(placement.definition_id)
		definition.base_stats.armor_levels = 3
		definition.base_stats.max_health = 100
		if index == 0:
			definition.ability_ids.assign([&"core:create_electricity", &"core:create_water", &"core:create_fire", &"core:create_oil", &"core:create_acid"])
		for cell: BattleMapCellDefinition in map.cells:
			if cell.hex == placement.start_hex:
				cell.hex_state_id = states[index % states.size()]
				cell.movement_cost = HexStateCatalog.get_movement_cost(cell.hex_state_id)
	var screen := preload("res://features/battle/battle_screen.tscn").instantiate() as BattleScreen
	if not screen.setup(loaded.request):
		push_error(screen.initialization_error)
		screen.free()
		return
	add_child(screen)
	(screen.get_node("BattleMap/BattleController") as BattleController).set_playback_speed(4.0)
