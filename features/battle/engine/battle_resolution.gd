class_name BattleResolution
extends RefCounted


var accepted: bool
var rejection_reason: String
var events: Array[BattleEvent] = []
var state_revision: int
var next_active_unit_id: StringName
var battle_result: BattleResult


func _init(
	p_accepted: bool,
	p_rejection_reason: String,
	p_events: Array[BattleEvent],
	p_state_revision: int,
	p_next_active_unit_id: StringName,
	p_battle_result: BattleResult
) -> void:
	accepted = p_accepted
	rejection_reason = p_rejection_reason
	events.assign(p_events)
	state_revision = maxi(p_state_revision, 0)
	next_active_unit_id = p_next_active_unit_id
	battle_result = p_battle_result


static func rejected(
	reason: String,
	p_state_revision: int,
	p_next_active_unit_id: StringName,
	p_battle_result: BattleResult = null
) -> BattleResolution:
	var no_events: Array[BattleEvent] = []
	return BattleResolution.new(
		false,
		reason,
		no_events,
		p_state_revision,
		p_next_active_unit_id,
		p_battle_result
	)


static func success(
	p_events: Array[BattleEvent],
	p_state_revision: int,
	p_next_active_unit_id: StringName,
	p_battle_result: BattleResult = null
) -> BattleResolution:
	return BattleResolution.new(
		true,
		"",
		p_events,
		p_state_revision,
		p_next_active_unit_id,
		p_battle_result
	)