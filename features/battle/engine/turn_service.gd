class_name TurnService
extends RefCounted


var _turn_order: Array[StringName] = []
var _active_index := -1
var _round_number := 0


func _init(turn_order: Array[StringName]) -> void:
	_turn_order.assign(turn_order)


func start() -> StringName:
	_active_index = -1
	_round_number = 0

	if _turn_order.is_empty():
		return StringName()

	_active_index = 0
	_round_number = 1

	return get_active_unit_id()


func get_active_unit_id() -> StringName:
	if _active_index < 0 or _active_index >= _turn_order.size():
		return StringName()

	return _turn_order[_active_index]


func get_round_number() -> int:
	return _round_number


func get_participant_count() -> int:
	return _turn_order.size()


## До start() переход запрещён; после старта порядок циклический.
func advance_turn() -> StringName:
	if _turn_order.is_empty() or _active_index < 0:
		return StringName()

	_active_index = (_active_index + 1) % _turn_order.size()

	if _active_index == 0:
		_round_number += 1

	return get_active_unit_id()