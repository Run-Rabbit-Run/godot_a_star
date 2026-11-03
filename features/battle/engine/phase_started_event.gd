class_name PhaseStartedEvent
extends BattleEvent
## A faction begins its phase; its start-of-turn effects follow this event.

var faction: BattleFaction.Value
var round_number: int


func _init(p_faction: BattleFaction.Value, p_round_number: int) -> void:
	faction = p_faction
	round_number = maxi(p_round_number, 0)
