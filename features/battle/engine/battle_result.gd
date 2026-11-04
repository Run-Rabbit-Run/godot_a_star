class_name BattleResult
extends RefCounted


var battle_id: StringName
var deterministic_seed: int
var outcome: BattleOutcome.Value
var round_number: int
var objective_result: ObjectiveResult
## The faction's own units when the battle ended; summoned units and constructions are not counted.
var participants: Dictionary[BattleFaction.Value, int] = {}
## Defeated own units per faction.
var defeated: Dictionary[BattleFaction.Value, int] = {}


func _init(
	p_battle_id: StringName,
	p_deterministic_seed: int,
	p_outcome: BattleOutcome.Value,
	p_round_number: int,
	p_objective_result: ObjectiveResult
) -> void:
	battle_id = p_battle_id
	deterministic_seed = p_deterministic_seed
	outcome = p_outcome
	round_number = p_round_number
	objective_result = p_objective_result