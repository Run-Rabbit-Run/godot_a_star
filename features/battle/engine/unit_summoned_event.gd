class_name UnitSummonedEvent
extends BattleEvent

var summoner_id: StringName
var unit: UnitSnapshot
var definition: UnitDefinition

func _init(source: StringName, state: UnitState, content: UnitDefinition) -> void:
	summoner_id = source
	unit = UnitSnapshot.new(state)
	definition = content
