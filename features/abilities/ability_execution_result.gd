class_name AbilityExecutionResult
extends RefCounted


var accepted: bool
var rejection_reason: String
var events: Array[BattleEvent] = []
## Set when a detached state was already changed before the ability failed.
var state_changed := false


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


## A handler failed after the effects started; a live battle has already discarded them.
static func failed(reason: String, p_state_changed: bool) -> AbilityExecutionResult:
	var result := rejected(reason)
	result.state_changed = p_state_changed
	return result


static func success(
	p_events: Array[BattleEvent]
) -> AbilityExecutionResult:
	return AbilityExecutionResult.new(true, "", p_events)