class_name BattleStartRequest
extends RefCounted


var battle_id: StringName
var content_snapshot: ContentSnapshot
var deterministic_seed: int


func _init(
	p_battle_id: StringName,
	p_content_snapshot: ContentSnapshot,
	p_deterministic_seed: int
) -> void:
	battle_id = p_battle_id
	content_snapshot = p_content_snapshot
	deterministic_seed = p_deterministic_seed
