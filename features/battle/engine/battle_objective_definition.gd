class_name BattleObjectiveDefinition
extends Resource


@export var type: BattleObjectiveType.Value = BattleObjectiveType.Value.ELIMINATE_FACTION
@export var description: String
@export var target_faction: BattleFaction.Value = BattleFaction.Value.ENEMY
## SURVIVE_ROUNDS: the round that has to end with the protected faction still standing.
@export var rounds := 5
## Any objective: the battle is lost when this round ends without a victory.
@export var round_limit := DEFAULT_ROUND_LIMIT
## ELIMINATE_TARGETS: placements of the target faction that have to be defeated.
@export var target_placement_ids: Array[StringName] = []
## Any objective: placements of the protected faction whose defeat loses the battle.
@export var protected_placement_ids: Array[StringName] = []

const DEFAULT_ROUND_LIMIT := 99
const MAX_ROUND_LIMIT := 999
