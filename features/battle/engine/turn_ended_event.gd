class_name TurnEndedEvent
extends BattleEvent
## A unit finished its turn in the phase.

var unit_id: StringName
var round_number: int
## A paralyzed unit did not act: its turn ended with the phase end.
var was_skipped := false


func _init(p_unit_id: StringName, p_round_number: int) -> void:
	unit_id = p_unit_id
	round_number = maxi(p_round_number, 0)
