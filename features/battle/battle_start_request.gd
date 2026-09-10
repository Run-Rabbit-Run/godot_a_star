class_name BattleStartRequest
extends RefCounted


var battle_definition: BattleDefinition
var deterministic_seed: int


func _init(
	p_battle_definition: BattleDefinition,
	p_deterministic_seed: int
) -> void:
	battle_definition = p_battle_definition
	deterministic_seed = p_deterministic_seed
