class_name TurnEndedEvent
extends BattleEvent
## A unit finished its turn in the phase; its end-of-turn effects precede this event.

var unit_id: StringName
var round_number: int
## A paralyzed unit did not act: its end-of-turn effects resolved with the phase end.
var was_skipped := false


func _init(p_unit_id: StringName, p_round_number: int) -> void:
	unit_id = p_unit_id
	round_number = maxi(p_round_number, 0)
