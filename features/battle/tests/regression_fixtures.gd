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

## Fixed copy of the authored battle: assigning another starting battle in the editor
## must not change what the regressions exercise.
const BATTLE_PATH := "res://features/battle/tests/fixtures/regression_battle.json"

var _skills: SkillLibrary

## Skill library of the project's packages, built once per test run.
func skills() -> SkillLibrary:
	if _skills == null:
		_skills = SkillLibrary.new(GameContentSettings.read().content_packages)
	return _skills

func content() -> ContentLoadResult:
	return UnitLibrary.load_content(GameContentSettings.read().content_packages, false)

func request(include_presentation := false) -> BattleStartRequest:
	return ProjectBattleLoader.load_battle(GameContentSettings.read().content_packages, BATTLE_PATH, 7, include_presentation).request

## The regression battle with the authored spear guard first, all sides under the player.
## Shared with tools/units/spear_preview.tscn, so the regression and the manual stand agree.
func spear_request() -> BattleStartRequest:
	var loaded := ProjectBattleLoader.load_battle(GameContentSettings.read().content_packages, BATTLE_PATH, 7)
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
