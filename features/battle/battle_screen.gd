class_name BattleScreen
extends Node


signal battle_finished(result: BattleResult)


@onready var _battle_controller: BattleController = (
	$BattleMap/BattleController
)

var _start_request: BattleStartRequest
var _has_started := false


func _ready() -> void:
	if _start_request != null:
		_start_battle()


func setup(request: BattleStartRequest) -> bool:
	var validation := BattleStartRequestValidator.validate(request)

	if not validation.is_valid:
		push_error("BattleScreen setup failed: %s" % validation.error_message)
		return false

	if _start_request != null or _has_started:
		push_error("BattleScreen setup can only be called once.")
		return false

	_start_request = request

	if is_node_ready():
		return _start_battle()

	return true


func _start_battle() -> bool:
	if _has_started:
		return false

	if not _battle_controller.battle_finished.is_connected(
		_on_battle_finished
	):
		_battle_controller.battle_finished.connect(
			_on_battle_finished
		)

	if not _battle_controller.setup(_start_request):
		return false

	_has_started = true
	return true


func _on_battle_finished(result: BattleResult) -> void:
	battle_finished.emit(result)