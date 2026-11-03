class_name BattleObjectiveFactory
extends RefCounted


## `unit_ids` maps placement ids to the runtime unit ids of this battle.
static func create(
	definition: BattleObjectiveDefinition,
	unit_ids: Dictionary[StringName, StringName] = {}
) -> BattleObjective:
	if definition == null:
		push_error("BattleObjectiveDefinition is required.")
		return null

	match definition.type:
		BattleObjectiveType.Value.ELIMINATE_FACTION:
			return EliminateFactionObjective.new(
				definition.target_faction,
				definition.description
			)
		BattleObjectiveType.Value.SURVIVE_ROUNDS:
			return SurviveRoundsObjective.new(definition.rounds, definition.target_faction, definition.description)
		BattleObjectiveType.Value.ELIMINATE_TARGETS:
			return EliminateTargetsObjective.new(to_unit_ids(definition.target_placement_ids, unit_ids), definition.target_faction, definition.description)

	push_error("Unsupported battle objective type.")
	return null


static func to_unit_ids(placement_ids: Array[StringName], unit_ids: Dictionary[StringName, StringName]) -> Array[StringName]:
	var result: Array[StringName] = []
	for placement_id: StringName in placement_ids:
		result.append(unit_ids.get(placement_id, placement_id))
	return result
