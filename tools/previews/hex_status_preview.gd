extends Node
## F6: ordinary saved battlefield with temporary terrain and all creation abilities.
## The authored battle, units, and preferences are never saved by this scene.

const STATES: Array[StringName] = [&"core:water", &"core:electricity", &"core:fire", &"core:oil", &"core:acid", &"core:plasma"]
const CREATION_ABILITIES: Array[StringName] = [&"core:create_electricity", &"core:create_water", &"core:create_fire", &"core:create_oil", &"core:create_acid"]


func _ready() -> void:
	DisplayServer.window_set_title("A_star · состояния гексов и юнитов")
	var request := create_request()
	if request == null:
		return
	var screen := preload("res://features/battle/battle_screen.tscn").instantiate() as BattleScreen
	if not screen.setup(request):
		push_error(screen.initialization_error)
		screen.free()
		return
	add_child(screen)
	(screen.get_node("BattleMap/BattleController") as BattleController).set_playback_speed(4.0)


## Snapshot getters return detached copies, so the sandbox publishes its changes as overrides.
static func create_request() -> BattleStartRequest:
	var settings := GameContentSettings.read()
	var loaded := ProjectBattleLoader.load_battle(settings.content_packages, settings.battle_document_path, 1)
	if loaded.request == null:
		push_error(loaded.error_message)
		return null
	var snapshot := loaded.request.content_snapshot
	var battle := snapshot.get_battle_definition(loaded.request.battle_id)
	var map := snapshot.get_map_definition(battle.map_id)
	# Placements may share a definition; one override per ID keeps the result deterministic.
	var unit_overrides: Dictionary[StringName, UnitDefinition] = {}
	for index in range(battle.unit_placements.size()):
		var placement := battle.unit_placements[index]
		var definition: UnitDefinition = unit_overrides.get(placement.definition_id)
		if definition == null:
			definition = snapshot.get_unit_definition(placement.definition_id)
			definition.base_stats.armor_levels = 3
			definition.base_stats.max_health = 100
			unit_overrides[placement.definition_id] = definition
		if index == 0:
			definition.ability_ids.assign(CREATION_ABILITIES)
		for cell: BattleMapCellDefinition in map.cells:
			if cell.hex == placement.start_hex:
				cell.hex_state_id = STATES[index % STATES.size()]
				cell.movement_cost = HexStateCatalog.get_movement_cost(cell.hex_state_id)
	var overrides: Array[UnitDefinition] = []
	overrides.assign(unit_overrides.values())
	loaded.request.content_snapshot = snapshot.with_battle_document(map, battle, overrides)
	return loaded.request
