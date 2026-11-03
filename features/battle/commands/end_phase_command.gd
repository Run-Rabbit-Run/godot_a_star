class_name EndPhaseCommand
extends BattleCommand
## Ends the turns of every remaining unit of the acting faction and passes the phase.

var faction: BattleFaction.Value


func _init(p_faction: BattleFaction.Value) -> void:
	faction = p_faction
