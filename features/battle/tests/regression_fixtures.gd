extends RefCounted

func unit(id: StringName, faction: BattleFaction.Value, hex: Vector2i, hp := 100, movement := 8) -> UnitState:
	return UnitState.new(id, &"core:test_unit", faction, hex, TurnState.new(movement), HealthState.new(hp), 2, 1)

func state(cells: Array[Vector2i], units: Array[UnitState] = []) -> BattleState:
	var registry: Dictionary[StringName, UnitState] = {}
	var order: Array[StringName] = []
	for participant: UnitState in units:
		registry[participant.unit_id] = participant
		order.append(participant.unit_id)
	return BattleState.new(&"core:test", HexGrid.new(cells), registry, order, ObjectiveSystem.new(EliminateFactionObjective.new(BattleFaction.Value.ENEMY, "Defeat enemies"), BattleFaction.Value.PLAYER), 7)

func ability(id: StringName, mode: AbilityDefinition.TargetMode, radius := 0) -> AbilityDefinition:
	var value := AbilityDefinition.new()
	value.id = id
	value.display_name = "Test ability"
	value.range = 8
	value.target_mode = mode
	value.area_radius = radius
	var effect := AbilityEffectDefinition.new()
	effect.effect_type_id = &"core:damage"
	effect.parameters = {"amount": 3}
	value.effects.append(effect)
	return value

func content() -> ContentLoadResult:
	return UnitLibrary.load_content(GameContentSettings.read().content_packages, false)

func request(include_presentation := false) -> BattleStartRequest:
	var settings := GameContentSettings.read()
	return ProjectBattleLoader.load_battle(settings.content_packages, settings.battle_document_path, 7, include_presentation).request
