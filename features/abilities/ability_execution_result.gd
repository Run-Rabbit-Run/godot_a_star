class_name AbilityExecutionResult
extends RefCounted


var accepted: bool
var rejection_reason: String
var events: Array[BattleEvent] = []


func _init(
	p_accepted: bool,
	p_rejection_reason: String,
	p_events: Array[BattleEvent]
) -> void:
	accepted = p_accepted
	rejection_reason = p_rejection_reason
	events.assign(p_events)


static func rejected(reason: String) -> AbilityExecutionResult:
	var no_events: Array[BattleEvent] = []
	return AbilityExecutionResult.new(false, reason, no_events)


static func success(
	p_events: Array[BattleEvent]
) -> AbilityExecutionResult:
	return AbilityExecutionResult.new(true, "", p_events)