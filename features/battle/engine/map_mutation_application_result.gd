class_name MapMutationApplicationResult
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


static func rejected(reason: String) -> MapMutationApplicationResult:
	var no_events: Array[BattleEvent] = []
	return MapMutationApplicationResult.new(false, reason, no_events)


static func success(
	p_events: Array[BattleEvent]
) -> MapMutationApplicationResult:
	return MapMutationApplicationResult.new(true, "", p_events)