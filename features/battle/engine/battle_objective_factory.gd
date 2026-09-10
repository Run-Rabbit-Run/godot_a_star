class_name BattleObjectiveFactory
extends RefCounted


static func create(
	definition: BattleObjectiveDefinition
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

	push_error("Unsupported battle objective type.")
	return null
