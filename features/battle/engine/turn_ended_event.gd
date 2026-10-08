class_name TurnEndedEvent
extends BattleEvent


var previous_unit_id: StringName
var next_unit_id: StringName
var round_number: int
## Automatic paralysis skips still resolve their own end-of-turn effects.
var was_skipped := false


func _init(
	p_previous_unit_id: StringName,
	p_next_unit_id: StringName,
	p_round_number: int
) -> void:
	previous_unit_id = p_previous_unit_id
	next_unit_id = p_next_unit_id
	round_number = maxi(p_round_number, 0)
