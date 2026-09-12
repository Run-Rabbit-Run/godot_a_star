class_name CampaignAdvanceResult
extends RefCounted


var accepted: bool
var rejection_reason: String
var previous_scenario_id: StringName
var next_scenario_id: StringName
var campaign_completed: bool


func _init(
	p_accepted: bool,
	p_rejection_reason: String,
	p_previous_scenario_id: StringName,
	p_next_scenario_id: StringName,
	p_campaign_completed: bool
) -> void:
	accepted = p_accepted
	rejection_reason = p_rejection_reason
	previous_scenario_id = p_previous_scenario_id
	next_scenario_id = p_next_scenario_id
	campaign_completed = p_campaign_completed